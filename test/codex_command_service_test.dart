import 'dart:io';

import 'package:clash/models/codex_profile.dart';
import 'package:clash/services/codex_command_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('readLatestUsageSnapshot follows the latest token_count update', () async {
    final tempDir = await Directory.systemTemp.createTemp('codex-usage-test');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final sessionsDir = Directory(
      '${tempDir.path}/sessions/2026/04/26',
    );
    await sessionsDir.create(recursive: true);
    final sessionFile = File('${sessionsDir.path}/rollout-test.jsonl');
    await sessionFile.writeAsString(_tokenCountEvent(34.0));

    final service = CodexCommandService();
    final profile = CodexProfile(
      id: 'profile-1',
      label: 'Work',
      codexHome: tempDir.path,
      createdAt: DateTime.parse('2026-04-26T08:00:00Z'),
    );

    final initialSnapshot = await service.readLatestUsageSnapshot(
      profile,
      forceRescan: true,
    );
    expect(initialSnapshot, isNotNull);
    expect(initialSnapshot?.windows.single.remainingPercent, 66);

    await Future<void>.delayed(const Duration(milliseconds: 20));
    await sessionFile.writeAsString(
      '${_tokenCountEvent(34.0)}\n${_tokenCountEvent(41.0)}',
    );

    final updatedSnapshot = await service.readLatestUsageSnapshot(profile);
    expect(updatedSnapshot, isNotNull);
    expect(updatedSnapshot?.windows.single.remainingPercent, 59);
  });

  test('makeProfileDefault copies the selected auth.json into default .codex', () async {
    final tempHome = await Directory.systemTemp.createTemp('codex-default-test');
    addTearDown(() async {
      if (await tempHome.exists()) {
        await tempHome.delete(recursive: true);
      }
    });

    final sourceHome = Directory('${tempHome.path}/profiles/work');
    await sourceHome.create(recursive: true);
    final sourceAuth = File('${sourceHome.path}/auth.json');
    await sourceAuth.writeAsString('{"account":"work"}');

    final service = CodexCommandService();
    final profile = CodexProfile(
      id: 'profile-2',
      label: 'Work',
      codexHome: sourceHome.path,
      createdAt: DateTime.parse('2026-04-26T08:00:00Z'),
    );

    await service.makeProfileDefault(profile, homeRoot: tempHome.path);

    final defaultAuth = File('${tempHome.path}/.codex/auth.json');
    expect(await defaultAuth.exists(), isTrue);
    expect(await defaultAuth.readAsString(), '{"account":"work"}');
  });
}

String _tokenCountEvent(double usedPercent) {
  return '{"timestamp":"2026-04-26T09:04:28.809Z","type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"limit_id":"codex","limit_name":null,"primary":{"used_percent":$usedPercent,"window_minutes":10080,"resets_at":1777796030},"secondary":null,"credits":null,"plan_type":"free","rate_limit_reached_type":null}}}';
}
