import 'dart:convert';
import 'dart:io';

import 'package:clash/models/codex_profile.dart';
import 'package:clash/services/profile_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mergeDiscoveredProfiles imports existing local Codex homes', () async {
    final tempHome = await Directory.systemTemp.createTemp(
      'codex-profile-store-test',
    );
    addTearDown(() async {
      if (await tempHome.exists()) {
        await tempHome.delete(recursive: true);
      }
    });

    final defaultCodex = Directory('${tempHome.path}/.codex');
    await defaultCodex.create(recursive: true);
    await File('${defaultCodex.path}/auth.json').writeAsString(_authJson(
      name: 'Oz Kingshark',
      email: 'oz@example.com',
      planType: 'pro',
      organizationTitle: 'Personal',
    ));

    final importedHome = Directory('${tempHome.path}/.codex-clash/profiles/work');
    await importedHome.create(recursive: true);
    await File('${importedHome.path}/auth.json').writeAsString(_authJson(
      name: 'Work User',
      email: 'work@example.com',
      planType: 'business',
      organizationTitle: 'Work',
    ));

    final store = ProfileStore();
    final result = await store.mergeDiscoveredProfiles(
      const [],
      homeRoot: tempHome.path,
    );

    expect(result.importedCount, 2);
    expect(result.profiles.map((profile) => profile.codexHome), containsAll([
      defaultCodex.path,
      importedHome.path,
    ]));
    expect(result.profiles.map((profile) => profile.label), containsAll([
      'oz@example.com',
      'work@example.com',
    ]));
    expect(
      result.profiles
          .firstWhere((profile) => profile.codexHome == defaultCodex.path)
          .notes,
      contains('Plan: pro'),
    );
  });

  test('mergeDiscoveredProfiles does not duplicate an already saved home', () async {
    final tempHome = await Directory.systemTemp.createTemp(
      'codex-profile-store-existing',
    );
    addTearDown(() async {
      if (await tempHome.exists()) {
        await tempHome.delete(recursive: true);
      }
    });

    final defaultCodex = Directory('${tempHome.path}/.codex');
    await defaultCodex.create(recursive: true);
    await File('${defaultCodex.path}/auth.json').writeAsString(_authJson(
      name: 'Saved User',
      email: 'saved@example.com',
      planType: 'plus',
      organizationTitle: 'Personal',
    ));

    final existing = CodexProfile(
      id: 'saved-profile',
      label: 'My Saved Label',
      codexHome: defaultCodex.path,
      createdAt: DateTime.parse('2026-04-26T09:00:00Z'),
      notes: 'Keep this',
    );

    final store = ProfileStore();
    final result = await store.mergeDiscoveredProfiles(
      [existing],
      homeRoot: tempHome.path,
    );

    expect(result.importedCount, 0);
    expect(result.profiles, hasLength(1));
    expect(result.profiles.single.label, 'My Saved Label');
    expect(result.profiles.single.notes, 'Keep this');
  });
}

String _authJson({
  required String name,
  required String email,
  required String planType,
  required String organizationTitle,
}) {
  final idPayload = _base64Url(
    '{"name":"$name","email":"$email","https://api.openai.com/auth":{"chatgpt_plan_type":"$planType","organizations":[{"title":"$organizationTitle"}]}}',
  );
  return '{"auth_mode":"chatgpt","tokens":{"id_token":"header.$idPayload.signature","account_id":"account-1"}}';
}

String _base64Url(String value) {
  final bytes = utf8.encode(value);
  return base64Url.encode(bytes).replaceAll('=', '');
}
