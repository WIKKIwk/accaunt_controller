import 'dart:convert';
import 'dart:io';

import 'package:clash/models/codex_profile.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class StoredProfiles {
  const StoredProfiles({
    required this.activeProfileId,
    required this.defaultCliProfileId,
    required this.profiles,
    required this.themeModeName,
    required this.palettePresetName,
  });

  final String? activeProfileId;
  final String? defaultCliProfileId;
  final List<CodexProfile> profiles;
  final String themeModeName;
  final String palettePresetName;
}

class DiscoveredProfilesResult {
  const DiscoveredProfilesResult({
    required this.profiles,
    required this.importedCount,
  });

  final List<CodexProfile> profiles;
  final int importedCount;
}

class ProfileStore {
  Future<StoredProfiles> load() async {
    final file = await _profilesFile();
    if (!await file.exists()) {
      return const StoredProfiles(
        activeProfileId: null,
        defaultCliProfileId: null,
        profiles: [],
        themeModeName: 'dark',
        palettePresetName: 'lavender',
      );
    }

    final raw = await file.readAsString();
    if (raw.trim().isEmpty) {
      return const StoredProfiles(
        activeProfileId: null,
        defaultCliProfileId: null,
        profiles: [],
        themeModeName: 'dark',
        palettePresetName: 'lavender',
      );
    }

    final json = jsonDecode(raw) as Map<String, dynamic>;
    final profileItems = (json['profiles'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(CodexProfile.fromJson)
        .toList();

    return StoredProfiles(
      activeProfileId: json['activeProfileId'] as String?,
      defaultCliProfileId: json['defaultCliProfileId'] as String?,
      profiles: profileItems,
      themeModeName: (json['themeMode'] as String?) ?? 'dark',
      palettePresetName: (json['palettePreset'] as String?) ?? 'lavender',
    );
  }

  Future<void> save({
    required String? activeProfileId,
    required String? defaultCliProfileId,
    required List<CodexProfile> profiles,
    required String themeModeName,
    required String palettePresetName,
  }) async {
    final file = await _profilesFile();
    await file.parent.create(recursive: true);

    final payload = {
      'activeProfileId': activeProfileId,
      'defaultCliProfileId': defaultCliProfileId,
      'themeMode': themeModeName,
      'palettePreset': palettePresetName,
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

  Future<DiscoveredProfilesResult> mergeDiscoveredProfiles(
    List<CodexProfile> existingProfiles, {
    String? homeRoot,
  }) async {
    final resolvedHomeRoot = homeRoot ?? Platform.environment['HOME'] ?? '.';
    final existingByHome = <String, CodexProfile>{
      for (final profile in existingProfiles)
        _normalizeHome(profile.codexHome): profile,
    };

    final merged = <CodexProfile>[...existingProfiles];
    var importedCount = 0;

    for (final codexHome in await _candidateCodexHomes(
      existingProfiles,
      resolvedHomeRoot,
    )) {
      final normalizedHome = _normalizeHome(codexHome);
      final existingProfile = existingByHome[normalizedHome];
      if (existingProfile != null) {
        final refreshedProfile = await _refreshExistingProfileFromDisk(
          existingProfile,
        );
        if (refreshedProfile != existingProfile) {
          final index = merged.indexWhere((profile) => profile.id == existingProfile.id);
          if (index != -1) {
            merged[index] = refreshedProfile;
          }
          existingByHome[normalizedHome] = refreshedProfile;
        }
        continue;
      }

      final discoveredProfile = await _buildDiscoveredProfile(normalizedHome);
      if (discoveredProfile == null) {
        continue;
      }

      merged.add(discoveredProfile);
      existingByHome[normalizedHome] = discoveredProfile;
      importedCount += 1;
    }

    return DiscoveredProfilesResult(
      profiles: merged,
      importedCount: importedCount,
    );
  }

  Future<CodexProfile> _refreshExistingProfileFromDisk(
    CodexProfile profile,
  ) async {
    final isImportedProfile =
        profile.id.startsWith('imported-') ||
        (profile.notes?.startsWith('Auto-imported') ?? false);
    if (!isImportedProfile) {
      return profile;
    }

    final discoveredProfile = await _buildDiscoveredProfile(
      _normalizeHome(profile.codexHome),
    );
    if (discoveredProfile == null) {
      return profile;
    }

    return profile.copyWith(
      label: discoveredProfile.label,
      notes: discoveredProfile.notes,
      createdAt: discoveredProfile.createdAt,
    );
  }

  Future<File> _profilesFile() async {
    final supportDir = await getApplicationSupportDirectory();
    return File(p.join(supportDir.path, 'profiles.json'));
  }

  Future<List<String>> _candidateCodexHomes(
    List<CodexProfile> existingProfiles,
    String homeRoot,
  ) async {
    final homes = <String>{
      p.join(homeRoot, '.codex'),
      ...existingProfiles.map((profile) => profile.codexHome),
    };

    final managedProfilesDir = Directory(
      p.join(homeRoot, '.codex-clash', 'profiles'),
    );
    if (await managedProfilesDir.exists()) {
      await for (final entity in managedProfilesDir.list()) {
        if (entity is Directory) {
          homes.add(entity.path);
        }
      }
    }

    return homes.map(_normalizeHome).toList()..sort();
  }

  Future<CodexProfile?> _buildDiscoveredProfile(String codexHome) async {
    final authFile = File(p.join(codexHome, 'auth.json'));
    final sessionsDir = Directory(p.join(codexHome, 'sessions'));
    final hasAuth = await authFile.exists();
    final hasSessions = await sessionsDir.exists();
    if (!hasAuth && !hasSessions) {
      return null;
    }

    final metadata = hasAuth ? await _readAuthMetadata(authFile) : null;
    final label = _discoveredLabel(codexHome, metadata);
    final createdAt = hasAuth
        ? await authFile.lastModified()
        : (await sessionsDir.stat()).modified;

    return CodexProfile(
      id: 'imported-${_slugify(codexHome)}',
      label: label,
      codexHome: codexHome,
      createdAt: createdAt,
      notes: _discoveredNotes(metadata, hasAuth: hasAuth, hasSessions: hasSessions),
    );
  }

  Future<_DiscoveredAuthMetadata?> _readAuthMetadata(File authFile) async {
    try {
      final raw = await authFile.readAsString();
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) {
        return null;
      }

      final tokens = json['tokens'];
      final tokenMap = tokens is Map<String, dynamic> ? tokens : null;
      final topAccountId =
          json['account_id'] as String? ?? tokenMap?['account_id'] as String?;
      final idPayload = _parseJwtPayload(tokenMap?['id_token'] as String?);
      final accessPayload = _parseJwtPayload(
        tokenMap?['access_token'] as String?,
      );
      final authPayload = _readNestedMap(
            idPayload,
            const ['https://api.openai.com/auth'],
          ) ??
          _readNestedMap(accessPayload, const ['https://api.openai.com/auth']);
      final profilePayload = _readNestedMap(
        accessPayload,
        const ['https://api.openai.com/profile'],
      );
      final organizations = authPayload?['organizations'];
      String? organizationTitle;
      if (organizations is List && organizations.isNotEmpty) {
        final firstOrg = organizations.first;
        if (firstOrg is Map<String, dynamic>) {
          organizationTitle = firstOrg['title'] as String?;
        }
      }

      return _DiscoveredAuthMetadata(
        accountId:
            topAccountId ??
            authPayload?['chatgpt_account_id'] as String? ??
            authPayload?['chatgpt_account_user_id'] as String?,
        email:
            idPayload?['email'] as String? ??
            profilePayload?['email'] as String?,
        name: idPayload?['name'] as String?,
        planType: authPayload?['chatgpt_plan_type'] as String?,
        organizationTitle: organizationTitle,
      );
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? _parseJwtPayload(String? token) {
    if (token == null || token.isEmpty) {
      return null;
    }

    final segments = token.split('.');
    if (segments.length < 2) {
      return null;
    }

    try {
      final normalized = base64Url.normalize(segments[1]);
      final decoded = utf8.decode(base64Url.decode(normalized));
      final json = jsonDecode(decoded);
      return json is Map<String, dynamic> ? json : null;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? _readNestedMap(
    Map<String, dynamic>? source,
    List<String> keys,
  ) {
    dynamic current = source;
    for (final key in keys) {
      if (current is! Map<String, dynamic>) {
        return null;
      }
      current = current[key];
    }
    return current is Map<String, dynamic> ? current : null;
  }

  String _discoveredLabel(String codexHome, _DiscoveredAuthMetadata? metadata) {
    if (metadata?.email case final email? when email.trim().isNotEmpty) {
      return email.trim();
    }
    if (metadata?.name case final name? when name.trim().isNotEmpty) {
      return name.trim();
    }
    final baseName = p.basename(codexHome);
    if (baseName == '.codex') {
      return 'Default Codex';
    }
    return _titleCase(baseName.replaceAll('-', ' ').replaceAll('_', ' '));
  }

  String? _discoveredNotes(
    _DiscoveredAuthMetadata? metadata, {
    required bool hasAuth,
    required bool hasSessions,
  }) {
    final parts = <String>[];
    if (hasAuth) {
      parts.add('Auto-imported from local Codex login');
    } else if (hasSessions) {
      parts.add('Auto-imported from local Codex session history');
    }
    if (metadata?.name case final name? when name.trim().isNotEmpty) {
      parts.add('Name: ${name.trim()}');
    }
    if (metadata?.email case final email? when email.trim().isNotEmpty) {
      parts.add('Email: ${email.trim()}');
    }
    if (metadata?.planType case final plan? when plan.trim().isNotEmpty) {
      parts.add('Plan: ${plan.trim()}');
    }
    if (metadata?.organizationTitle case final org? when org.trim().isNotEmpty) {
      parts.add('Workspace: ${org.trim()}');
    }
    return parts.isEmpty ? null : parts.join(' | ');
  }

  String _normalizeHome(String path) => p.normalize(p.absolute(path));

  String _slugify(String input) {
    final compact = input.trim().toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]+'),
      '-',
    );
    final trimmed = compact.replaceAll(RegExp(r'^-+|-+$'), '');
    return trimmed.isEmpty ? 'profile' : trimmed;
  }

  String _titleCase(String input) {
    final words = input
        .split(RegExp(r'\s+'))
        .where((word) => word.trim().isNotEmpty)
        .toList();
    if (words.isEmpty) {
      return 'Profile';
    }
    return words
        .map(
          (word) => '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}',
        )
        .join(' ');
  }
}

class _DiscoveredAuthMetadata {
  const _DiscoveredAuthMetadata({
    this.accountId,
    this.email,
    this.name,
    this.planType,
    this.organizationTitle,
  });

  final String? accountId;
  final String? email;
  final String? name;
  final String? planType;
  final String? organizationTitle;
}
