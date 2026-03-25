import 'dart:convert';
import 'dart:io';

import 'package:clash/models/codex_profile.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class StoredProfiles {
  const StoredProfiles({required this.activeProfileId, required this.profiles});

  final String? activeProfileId;
  final List<CodexProfile> profiles;
}

class ProfileStore {
  Future<StoredProfiles> load() async {
    final file = await _profilesFile();
    if (!await file.exists()) {
      return const StoredProfiles(activeProfileId: null, profiles: []);
    }

    final raw = await file.readAsString();
    if (raw.trim().isEmpty) {
      return const StoredProfiles(activeProfileId: null, profiles: []);
    }

    final json = jsonDecode(raw) as Map<String, dynamic>;
    final profileItems = (json['profiles'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(CodexProfile.fromJson)
        .toList();

    return StoredProfiles(
      activeProfileId: json['activeProfileId'] as String?,
      profiles: profileItems,
    );
  }

  Future<void> save({
    required String? activeProfileId,
    required List<CodexProfile> profiles,
  }) async {
    final file = await _profilesFile();
    await file.parent.create(recursive: true);

    final payload = {
      'activeProfileId': activeProfileId,
      'profiles': profiles.map((profile) => profile.toJson()).toList(),
    };

    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
    );
  }

  Future<String> defaultCodexHomeForLabel(String label) async {
    final homeRoot = Platform.environment['HOME'] ?? '.';
    final slug = _slugify(label);
    return p.join(homeRoot, '.codex-clash', 'profiles', slug);
  }

  Future<File> _profilesFile() async {
    final supportDir = await getApplicationSupportDirectory();
    return File(p.join(supportDir.path, 'profiles.json'));
  }

  String _slugify(String input) {
    final compact = input.trim().toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]+'),
      '-',
    );
    final trimmed = compact.replaceAll(RegExp(r'^-+|-+$'), '');
    return trimmed.isEmpty ? 'profile' : trimmed;
  }
}
