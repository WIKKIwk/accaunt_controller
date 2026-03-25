import 'dart:async';

import 'package:clash/models/codex_profile.dart';
import 'package:clash/services/codex_command_service.dart';
import 'package:clash/services/profile_store.dart';
import 'package:flutter/foundation.dart';

class AppController extends ChangeNotifier {
  AppController({
    required ProfileStore profileStore,
    required CodexCommandService commandService,
  }) : _profileStore = profileStore,
       _commandService = commandService;

  final ProfileStore _profileStore;
  final CodexCommandService _commandService;

  List<CodexProfile> _profiles = const [];
  String? _activeProfileId;
  Timer? _loginWatchTimer;
  bool _isLoading = true;
  bool _isBusy = false;
  String? _errorMessage;
  String? _statusMessage;

  List<CodexProfile> get profiles => _profiles;
  bool get isLoading => _isLoading;
  bool get isBusy => _isBusy;
  String? get errorMessage => _errorMessage;
  String? get statusMessage => _statusMessage;
  CodexProfile? get activeProfile {
    final targetId = _activeProfileId;
    if (targetId == null) {
      return _profiles.isEmpty ? null : _profiles.first;
    }
    for (final profile in _profiles) {
      if (profile.id == targetId) {
        return profile;
      }
    }
    return _profiles.isEmpty ? null : _profiles.first;
  }

  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    try {
      final stored = await _profileStore.load();
      _profiles = stored.profiles;
      _activeProfileId =
          stored.activeProfileId ?? stored.profiles.firstOrNull?.id;
      final initialProfile = activeProfile;
      if (initialProfile != null) {
        unawaited(_refreshProfileSilently(initialProfile.id));
      }
    } catch (error) {
      _errorMessage = error.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> addProfile({
    required String label,
    required String codexHome,
    String? notes,
  }) async {
    final normalizedLabel = label.trim();
    final normalizedHome = codexHome.trim();
    if (normalizedLabel.isEmpty || normalizedHome.isEmpty) {
      _errorMessage = 'Profile name and CODEX_HOME are both required.';
      notifyListeners();
      return;
    }

    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final profile = CodexProfile(
      id: id,
      label: normalizedLabel,
      codexHome: normalizedHome,
      createdAt: DateTime.now(),
      notes: notes?.trim().isEmpty ?? true ? null : notes?.trim(),
    );

    _profiles = [..._profiles, profile]
      ..sort((left, right) => left.label.compareTo(right.label));
    _activeProfileId = profile.id;
    await _persist(statusMessage: 'Created profile "${profile.label}".');
  }

  Future<void> renameProfile({
    required String profileId,
    required String label,
  }) async {
    final normalizedLabel = label.trim();
    if (normalizedLabel.isEmpty) {
      _errorMessage = 'Profile name cannot be empty.';
      notifyListeners();
      return;
    }

    final profile = _findProfile(profileId);
    if (profile == null) {
      _errorMessage = 'Profile not found.';
      notifyListeners();
      return;
    }

    _profiles =
        _profiles
            .map(
              (item) => item.id == profileId
                  ? item.copyWith(label: normalizedLabel)
                  : item,
            )
            .toList()
          ..sort((left, right) => left.label.compareTo(right.label));

    await _persist(
      statusMessage: 'Renamed "${profile.label}" to "$normalizedLabel".',
    );
  }

  Future<String> suggestCodexHome(String label) {
    return _profileStore.defaultCodexHomeForLabel(label);
  }

  Future<void> selectProfile(String profileId) async {
    _activeProfileId = profileId;
    await _persist(statusMessage: 'Selected profile.');
    unawaited(_refreshProfileSilently(profileId));
  }

  Future<void> refreshActiveProfile() async {
    final profile = activeProfile;
    if (profile == null) {
      return;
    }

    await _runGuarded(() async {
      final probe = await _commandService.probeLogin(profile);
      _profiles = _profiles
          .map(
            (item) =>
                item.id == profile.id ? item.copyWith(lastProbe: probe) : item,
          )
          .toList();
      await _persist(
        statusMessage: 'Updated "${profile.label}" from local Codex data.',
      );
    });
  }

  Future<void> syncActiveProfileLimits() async {
    final profile = activeProfile;
    if (profile == null) {
      return;
    }

    await _runGuarded(() async {
      final probe = await _commandService.probeLogin(
        profile,
        refreshUsage: true,
      );
      _profiles = _profiles
          .map(
            (item) =>
                item.id == profile.id ? item.copyWith(lastProbe: probe) : item,
          )
          .toList();
      await _persist(
        statusMessage:
            'Synced "${profile.label}" limits from Codex. This can take a few seconds.',
      );
    });
  }

  Future<void> launchCodex() async {
    final profile = activeProfile;
    if (profile == null) {
      return;
    }

    await _runGuarded(() async {
      await _commandService.launchCodex(profile);
      _statusMessage = 'Opened Codex for "${profile.label}".';
      notifyListeners();
    });
  }

  Future<void> launchLogin() async {
    final profile = activeProfile;
    if (profile == null) {
      return;
    }

    await _runGuarded(() async {
      await _commandService.launchDeviceAuthLogin(profile);
      _statusMessage =
          'Opened the Codex login flow for "${profile.label}". Finish login in the terminal and this app will re-check automatically.';
      notifyListeners();
      _startLoginWatch(profile.id);
    });
  }

  Future<void> openUsagePage() async {
    await _runGuarded(() async {
      await _commandService.openUsagePage();
      _statusMessage = 'Opened the official Codex usage page.';
      notifyListeners();
    });
  }

  String manualStatusCommandForActive() {
    final profile = activeProfile;
    return profile == null
        ? ''
        : _commandService.buildManualStatusCommand(profile);
  }

  String loginCommandForActive() {
    final profile = activeProfile;
    return profile == null ? '' : _commandService.buildLoginCommand(profile);
  }

  String deviceAuthFallbackCommandForActive() {
    final profile = activeProfile;
    return profile == null
        ? ''
        : _commandService.buildDeviceAuthFallbackCommand(profile);
  }

  String zedHintForActive() {
    final profile = activeProfile;
    return profile == null ? '' : _commandService.buildZedHint(profile);
  }

  Future<void> _persist({String? statusMessage}) async {
    await _profileStore.save(
      activeProfileId: _activeProfileId,
      profiles: _profiles,
    );
    _statusMessage = statusMessage ?? _statusMessage;
    notifyListeners();
  }

  Future<void> _runGuarded(Future<void> Function() action) async {
    _isBusy = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await action();
    } catch (error) {
      _errorMessage = error.toString();
      notifyListeners();
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<void> _refreshProfileSilently(
    String profileId, {
    String? successMessage,
    bool refreshUsage = false,
  }) async {
    final profile = _findProfile(profileId);
    if (profile == null) {
      return;
    }

    try {
      final probe = await _commandService.probeLogin(
        profile,
        refreshUsage: refreshUsage,
      );
      _profiles = _profiles
          .map(
            (item) =>
                item.id == profileId ? item.copyWith(lastProbe: probe) : item,
          )
          .toList();
      await _profileStore.save(
        activeProfileId: _activeProfileId,
        profiles: _profiles,
      );
      if (successMessage != null) {
        _statusMessage = successMessage;
      }
      notifyListeners();
    } catch (_) {
      // Silent background refresh should not interrupt the main UI flow.
    }
  }

  void _startLoginWatch(String profileId) {
    _loginWatchTimer?.cancel();
    var attempts = 0;

    _loginWatchTimer = Timer.periodic(const Duration(seconds: 4), (
      timer,
    ) async {
      attempts += 1;
      final profile = _findProfile(profileId);
      if (profile == null) {
        timer.cancel();
        return;
      }

      try {
        final probe = await _commandService.probeLogin(profile);
        _profiles = _profiles
            .map(
              (item) =>
                  item.id == profileId ? item.copyWith(lastProbe: probe) : item,
            )
            .toList();
        await _profileStore.save(
          activeProfileId: _activeProfileId,
          profiles: _profiles,
        );

        if (probe.isLoggedIn) {
          final enrichedProbe = await _commandService.probeLogin(
            profile,
            refreshUsage: true,
          );
          _profiles = _profiles
              .map(
                (item) => item.id == profileId
                    ? item.copyWith(lastProbe: enrichedProbe)
                    : item,
              )
              .toList();
          await _profileStore.save(
            activeProfileId: _activeProfileId,
            profiles: _profiles,
          );
          _statusMessage = '"${profile.label}" is signed in.';
          timer.cancel();
        } else if (attempts >= 30) {
          _statusMessage =
              '"${profile.label}" is still not signed in. If you finished the browser flow, try "Login" once more and complete the final approval step.';
          timer.cancel();
        }
        notifyListeners();
      } catch (_) {
        if (attempts >= 30) {
          timer.cancel();
        }
      }
    });
  }

  CodexProfile? _findProfile(String profileId) {
    for (final profile in _profiles) {
      if (profile.id == profileId) {
        return profile;
      }
    }
    return null;
  }

  @override
  void dispose() {
    _loginWatchTimer?.cancel();
    super.dispose();
  }
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
