import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:clash/models/codex_probe.dart';
import 'package:clash/models/codex_profile.dart';
import 'package:clash/models/codex_usage_snapshot.dart';

class CodexCommandService {
  final Map<String, _UsageSnapshotCacheEntry> _usageSnapshotCache = {};

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
        ? await readLatestUsageSnapshot(profile, forceRescan: refreshUsage)
        : null;

    return CodexProbe(
      loginSummary: summary,
      checkedAt: DateTime.now(),
      isLoggedIn: isLoggedIn,
      usageSnapshot: usageSnapshot,
    );
  }

  Future<CodexUsageSnapshot?> readLatestUsageSnapshot(
    CodexProfile profile, {
    bool forceRescan = false,
  }) async {
    final cacheKey = profile.codexHome;
    final cached = _usageSnapshotCache[cacheKey];

    if (!forceRescan && cached != null) {
      final cachedFile = File(cached.filePath);
      if (await cachedFile.exists()) {
        final modifiedAt = await cachedFile.lastModified();
        if (modifiedAt == cached.modifiedAt) {
          return cached.snapshot;
        }

        final refreshedSnapshot = await _parseUsageSnapshot(cachedFile);
        if (refreshedSnapshot != null) {
          _usageSnapshotCache[cacheKey] = _UsageSnapshotCacheEntry(
            filePath: cached.filePath,
            modifiedAt: modifiedAt,
            snapshot: refreshedSnapshot,
          );
          return refreshedSnapshot;
        }
      }
    }

    final latest = await _findLatestUsageSnapshot(profile);
    if (latest == null) {
      _usageSnapshotCache.remove(cacheKey);
      return null;
    }

    _usageSnapshotCache[cacheKey] = _UsageSnapshotCacheEntry(
      filePath: latest.file.path,
      modifiedAt: latest.modifiedAt,
      snapshot: latest.snapshot,
    );
    return latest.snapshot;
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
    final command = _openCommand();
    final result = await Process.run(command.$1, command.$2);

    if (result.exitCode != 0) {
      throw ProcessException(
        command.$1,
        command.$2,
        '${result.stdout}${result.stderr}',
        result.exitCode,
      );
    }
  }

  Future<void> makeProfileDefault(
    CodexProfile profile, {
    String? homeRoot,
  }) async {
    final normalizedSourceHome = _normalizePath(profile.codexHome);
    final defaultHome = defaultCodexHome(homeRoot: homeRoot);
    await syncCodexHome(sourceHome: normalizedSourceHome, targetHome: defaultHome);
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

    if (Platform.isMacOS) {
      await _launchInMacOSTerminal(
        profile: profile,
        title: title,
        innerCommand: innerCommand,
      );
      return;
    }

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

  Future<void> _launchInMacOSTerminal({
    required CodexProfile profile,
    required String title,
    required String innerCommand,
  }) async {
    final scriptFile = File(
      '${Directory.systemTemp.path}/codex-clash-${DateTime.now().microsecondsSinceEpoch}.command',
    );
    final escapedPath = _shellEscape(profile.codexHome);
    final script = [
      '#!/bin/bash',
      'export CODEX_HOME=$escapedPath',
      'printf "\\\\033]0;$title\\\\007"',
      innerCommand,
      'printf "\\nPress Enter to close..."',
      'read -r _',
    ].join('\n');

    await scriptFile.writeAsString(script);
    await Process.run('chmod', ['700', scriptFile.path]);

    final result = await Process.run('open', [
      '-a',
      'Terminal',
      scriptFile.path,
    ]);

    if (result.exitCode != 0) {
      throw ProcessException(
        'open',
        ['-a', 'Terminal', scriptFile.path],
        '${result.stdout}${result.stderr}',
        result.exitCode,
      );
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

  String defaultCodexHome({String? homeRoot}) {
    final resolvedHome = homeRoot ?? Platform.environment['HOME'] ?? '.';
    return _normalizePath('$resolvedHome/.codex');
  }

  String _normalizePath(String value) => File(value).absolute.path;

  Future<void> syncCodexHome({
    required String sourceHome,
    required String targetHome,
  }) async {
    final normalizedSourceHome = _normalizePath(sourceHome);
    final normalizedTargetHome = _normalizePath(targetHome);
    if (normalizedSourceHome == normalizedTargetHome) {
      return;
    }

    final sourceDir = Directory(normalizedSourceHome);
    if (!await sourceDir.exists()) {
      throw FileSystemException(
        'Codex home does not exist.',
        normalizedSourceHome,
      );
    }

    final sourceAuthFile = File('$normalizedSourceHome/auth.json');
    if (!await sourceAuthFile.exists()) {
      throw const FileSystemException(
        'This profile does not have a local Codex login yet.',
        'auth.json',
      );
    }

    final targetDir = Directory(normalizedTargetHome);
    await targetDir.create(recursive: true);

    await _copyFileIfPresent(
      sourcePath: '$normalizedSourceHome/auth.json',
      targetPath: '$normalizedTargetHome/auth.json',
    );
    await _copyFileIfPresent(
      sourcePath: '$normalizedSourceHome/session_index.jsonl',
      targetPath: '$normalizedTargetHome/session_index.jsonl',
      deleteTargetIfMissing: true,
    );
    await _copyDirectoryIfPresent(
      sourcePath: '$normalizedSourceHome/sessions',
      targetPath: '$normalizedTargetHome/sessions',
      replaceTarget: true,
    );
  }

  Future<void> _copyFileIfPresent({
    required String sourcePath,
    required String targetPath,
    bool deleteTargetIfMissing = false,
  }) async {
    final sourceFile = File(sourcePath);
    final targetFile = File(targetPath);
    if (!await sourceFile.exists()) {
      if (deleteTargetIfMissing && await targetFile.exists()) {
        await targetFile.delete();
      }
      return;
    }

    await targetFile.parent.create(recursive: true);
    if (await targetFile.exists()) {
      await targetFile.delete();
    }
    await sourceFile.copy(targetFile.path);
  }

  Future<void> _copyDirectoryIfPresent({
    required String sourcePath,
    required String targetPath,
    bool replaceTarget = false,
  }) async {
    final sourceDir = Directory(sourcePath);
    final targetDir = Directory(targetPath);
    if (!await sourceDir.exists()) {
      if (replaceTarget && await targetDir.exists()) {
        await targetDir.delete(recursive: true);
      }
      return;
    }

    if (replaceTarget && await targetDir.exists()) {
      await targetDir.delete(recursive: true);
    }
    await targetDir.create(recursive: true);

    await for (final entity in sourceDir.list(recursive: true, followLinks: false)) {
      final relativePath = entity.path.substring(sourcePath.length + 1);
      final destinationPath = '$targetPath/$relativePath';
      if (entity is Directory) {
        await Directory(destinationPath).create(recursive: true);
      } else if (entity is File) {
        final outputFile = File(destinationPath);
        await outputFile.parent.create(recursive: true);
        await entity.copy(outputFile.path);
      }
    }
  }

  (String, List<String>) _openCommand() {
    const usageUrl = 'https://chatgpt.com/codex/settings/usage';
    if (Platform.isMacOS) {
      return ('open', [usageUrl]);
    }
    return ('xdg-open', [usageUrl]);
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

  Future<_UsageSnapshotResult?> _findLatestUsageSnapshot(
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
        return _UsageSnapshotResult(
          file: file,
          modifiedAt: file.statSync().modified,
          snapshot: snapshot,
        );
      }
    }

    return null;
  }

  Future<CodexUsageSnapshot?> _parseUsageSnapshot(File file) async {
    final lines = await _readRecentLines(file);

    for (final line in lines) {
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

  Future<List<String>> _readRecentLines(File file) async {
    const initialChunkSize = 64 * 1024;
    final recentChunk = await _readTailChunk(file, initialChunkSize);
    final recentLines = LineSplitter.split(recentChunk).toList().reversed;
    if (recentLines.isNotEmpty) {
      return recentLines.toList();
    }

    return (await file.readAsLines()).reversed.toList();
  }

  Future<String> _readTailChunk(File file, int maxBytes) async {
    final randomAccessFile = await file.open();
    try {
      final length = await randomAccessFile.length();
      final start = math.max(0, length - maxBytes);
      await randomAccessFile.setPosition(start);
      final bytes = await randomAccessFile.read(length - start);
      var content = utf8.decode(bytes, allowMalformed: true);

      if (start > 0) {
        final firstBreak = content.indexOf('\n');
        if (firstBreak == -1) {
          return '';
        }
        content = content.substring(firstBreak + 1);
      }

      return content;
    } finally {
      await randomAccessFile.close();
    }
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

class _UsageSnapshotResult {
  const _UsageSnapshotResult({
    required this.file,
    required this.modifiedAt,
    required this.snapshot,
  });

  final File file;
  final DateTime modifiedAt;
  final CodexUsageSnapshot snapshot;
}

class _UsageSnapshotCacheEntry {
  const _UsageSnapshotCacheEntry({
    required this.filePath,
    required this.modifiedAt,
    required this.snapshot,
  });

  final String filePath;
  final DateTime modifiedAt;
  final CodexUsageSnapshot snapshot;
}
