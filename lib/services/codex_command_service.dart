import 'dart:convert';
import 'dart:io';

import 'package:clash/models/codex_probe.dart';
import 'package:clash/models/codex_profile.dart';
import 'package:clash/models/codex_usage_snapshot.dart';

class CodexCommandService {
  Future<CodexProbe> probeLogin(
    CodexProfile profile, {
    bool refreshUsage = false,
  }) async {
    await Directory(profile.codexHome).create(recursive: true);

    final result = await Process.run('codex', [
      'login',
      'status',
    ], environment: _environmentFor(profile));

    final output = '${result.stdout}${result.stderr}'.trim();
    final summary = output.isEmpty ? 'Unable to read login status' : output;
    final isLoggedIn = _isLoggedInSummary(summary);

    if (isLoggedIn && refreshUsage) {
      await _captureUsageSnapshot(profile);
    }

    final usageSnapshot = isLoggedIn
        ? await _readLatestUsageSnapshot(profile)
        : null;

    return CodexProbe(
      loginSummary: summary,
      checkedAt: DateTime.now(),
      isLoggedIn: isLoggedIn,
      usageSnapshot: usageSnapshot,
    );
  }

  Future<void> launchCodex(CodexProfile profile) async {
    await _launchInTerminal(
      profile: profile,
      title: 'Codex ${profile.label}',
      innerCommand: 'codex',
    );
  }

  Future<void> launchDeviceAuthLogin(CodexProfile profile) async {
    await _launchInTerminal(
      profile: profile,
      title: 'Codex Login ${profile.label}',
      innerCommand: 'codex login',
    );
  }

  Future<void> openUsagePage() async {
    final result = await Process.run('xdg-open', [
      'https://chatgpt.com/codex/settings/usage',
    ]);

    if (result.exitCode != 0) {
      throw ProcessException(
        'xdg-open',
        const ['https://chatgpt.com/codex/settings/usage'],
        '${result.stdout}${result.stderr}',
        result.exitCode,
      );
    }
  }

  String buildManualStatusCommand(CodexProfile profile) {
    final escapedPath = _shellEscape(profile.codexHome);
    return 'CODEX_HOME=$escapedPath codex';
  }

  String buildLoginCommand(CodexProfile profile) {
    final escapedPath = _shellEscape(profile.codexHome);
    return 'CODEX_HOME=$escapedPath codex login';
  }

  String buildDeviceAuthFallbackCommand(CodexProfile profile) {
    final escapedPath = _shellEscape(profile.codexHome);
    return 'CODEX_HOME=$escapedPath codex login --device-auth';
  }

  String buildZedHint(CodexProfile profile) {
    return '"env": {\n'
        '  "CODEX_HOME": "${profile.codexHome}"\n'
        '}';
  }

  Future<void> _launchInTerminal({
    required CodexProfile profile,
    required String title,
    required String innerCommand,
  }) async {
    await Directory(profile.codexHome).create(recursive: true);

    final terminal = await _pickTerminal();
    final escapedTitle = _shellEscape(title);
    final escapedPath = _shellEscape(profile.codexHome);
    final script =
        'export CODEX_HOME=$escapedPath; $innerCommand; printf "\\nPress Enter to close..."; read _';

    final args = switch (terminal.binary) {
      'x-terminal-emulator' => ['-T', title, '-e', 'bash', '-lc', script],
      'gnome-terminal' => ['--title=$title', '--', 'bash', '-lc', script],
      'konsole' => [
        '--noclose',
        '-p',
        'tabtitle=$title',
        '-e',
        'bash',
        '-lc',
        script,
      ],
      'kitty' => ['--title', title, 'bash', '-lc', script],
      'wezterm' => [
        'start',
        '--cwd',
        Directory.current.path,
        '--',
        'bash',
        '-lc',
        script,
      ],
      'alacritty' => ['-T', title, '-e', 'bash', '-lc', script],
      _ => ['-lc', 'printf "Launching $escapedTitle\\n"; $script'],
    };

    final result = await Process.start(
      terminal.binary,
      args,
      mode: ProcessStartMode.detached,
    );

    if (result.pid <= 0) {
      throw const ProcessException('terminal', [], 'Failed to launch terminal');
    }
  }

  Future<_TerminalCommand> _pickTerminal() async {
    const candidates = <_TerminalCommand>[
      _TerminalCommand('x-terminal-emulator'),
      _TerminalCommand('gnome-terminal'),
      _TerminalCommand('konsole'),
      _TerminalCommand('kitty'),
      _TerminalCommand('wezterm'),
      _TerminalCommand('alacritty'),
    ];

    for (final candidate in candidates) {
      final result = await Process.run('sh', [
        '-lc',
        'command -v ${candidate.binary}',
      ]);
      if (result.exitCode == 0) {
        return candidate;
      }
    }

    return const _TerminalCommand('bash');
  }

  Map<String, String> _environmentFor(CodexProfile profile) {
    return {
      ...Platform.environment,
      'CODEX_HOME': profile.codexHome,
      'TERM': 'xterm-256color',
    };
  }

  String _shellEscape(String value) {
    return "'${value.replaceAll("'", "'\"'\"'")}'";
  }

  bool _isLoggedInSummary(String summary) {
    final normalized = summary.trim().toLowerCase();
    if (normalized.startsWith('logged in')) {
      return true;
    }
    if (normalized.startsWith('not logged in')) {
      return false;
    }
    return false;
  }

  Future<void> _captureUsageSnapshot(CodexProfile profile) async {
    final homeDir = Platform.environment['HOME'] ?? profile.codexHome;
    await Process.run('codex', [
      'exec',
      '--skip-git-repo-check',
      '--json',
      '-C',
      homeDir,
      'Reply with exactly ok',
    ], environment: _environmentFor(profile));
  }

  Future<CodexUsageSnapshot?> _readLatestUsageSnapshot(
    CodexProfile profile,
  ) async {
    final sessionsDir = Directory('${profile.codexHome}/sessions');
    if (!await sessionsDir.exists()) {
      return null;
    }

    final files = <File>[];
    await for (final entity in sessionsDir.list(recursive: true)) {
      if (entity is File && entity.path.endsWith('.jsonl')) {
        files.add(entity);
      }
    }

    if (files.isEmpty) {
      return null;
    }

    files.sort((left, right) {
      final modifiedDiff = right.statSync().modified.compareTo(
        left.statSync().modified,
      );
      if (modifiedDiff != 0) {
        return modifiedDiff;
      }
      return right.path.compareTo(left.path);
    });

    for (final file in files) {
      final snapshot = await _parseUsageSnapshot(file);
      if (snapshot != null) {
        return snapshot;
      }
    }

    return null;
  }

  Future<CodexUsageSnapshot?> _parseUsageSnapshot(File file) async {
    final lines = await file.readAsLines();

    for (final line in lines.reversed) {
      if (line.trim().isEmpty) {
        continue;
      }

      dynamic decoded;
      try {
        decoded = jsonDecode(line);
      } catch (_) {
        continue;
      }

      if (decoded is! Map<String, dynamic>) {
        continue;
      }
      if (decoded['type'] != 'event_msg') {
        continue;
      }

      final payload = decoded['payload'];
      if (payload is! Map<String, dynamic>) {
        continue;
      }
      if (payload['type'] != 'token_count') {
        continue;
      }

      final rateLimits = payload['rate_limits'];
      if (rateLimits is! Map<String, dynamic>) {
        continue;
      }

      final windows = <CodexUsageWindow>[];
      final primary = rateLimits['primary'];
      final secondary = rateLimits['secondary'];

      if (primary is Map<String, dynamic>) {
        windows.add(_parseWindow(primary));
      }
      if (secondary is Map<String, dynamic>) {
        windows.add(_parseWindow(secondary));
      }
      if (windows.isEmpty) {
        continue;
      }

      windows.sort(
        (left, right) => left.windowMinutes.compareTo(right.windowMinutes),
      );

      final timestamp = decoded['timestamp'] as String?;
      return CodexUsageSnapshot(
        capturedAt:
            DateTime.tryParse(timestamp ?? '') ??
            file.statSync().modified.toUtc(),
        windows: windows,
        planType: rateLimits['plan_type'] as String?,
        limitName: rateLimits['limit_name'] as String?,
      );
    }

    return null;
  }

  CodexUsageWindow _parseWindow(Map<String, dynamic> windowJson) {
    final minutes = (windowJson['window_minutes'] as num?)?.toInt() ?? 0;
    final usedPercent = (windowJson['used_percent'] as num?)?.toDouble() ?? 0;
    final resetsAtSeconds = (windowJson['resets_at'] as num?)?.toInt() ?? 0;

    return CodexUsageWindow(
      label: _windowLabel(minutes),
      windowMinutes: minutes,
      usedPercent: usedPercent,
      resetsAt: DateTime.fromMillisecondsSinceEpoch(
        resetsAtSeconds * 1000,
        isUtc: true,
      ).toLocal(),
    );
  }

  String _windowLabel(int minutes) {
    if (minutes == 300) {
      return '5h limit';
    }
    if (minutes == 10080) {
      return 'Weekly limit';
    }
    if (minutes > 0 && minutes % 60 == 0) {
      return '${minutes ~/ 60}h limit';
    }
    return '$minutes min limit';
  }
}

class _TerminalCommand {
  const _TerminalCommand(this.binary);

  final String binary;
}
