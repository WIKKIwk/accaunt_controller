import 'dart:async';
import 'dart:io';

import 'package:clash/models/app_color_style.dart';
import 'package:clash/models/codex_probe.dart';
import 'package:clash/models/codex_profile.dart';
import 'package:clash/models/codex_usage_snapshot.dart';
import 'package:clash/services/codex_command_service.dart';
import 'package:clash/services/official_usage_parser.dart';
import 'package:clash/services/profile_store.dart';
import 'package:flutter/material.dart';

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
  String? _defaultCliProfileId;
  Timer? _loginWatchTimer;
  Timer? _liveUsagePollTimer;
  final Map<String, StreamSubscription<FileSystemEvent>> _profileWatchers = {};
  final Map<String, Timer> _watchDebounceTimers = {};
  bool _isBootstrappingLive = false;
  ThemeMode _themeMode = ThemeMode.dark;
  AppPalettePreset _palettePreset = AppPalettePreset.lavender;
  bool _isLoading = true;
  bool _isBusy = false;
  String? _errorMessage;
  String? _statusMessage;

  List<CodexProfile> get profiles => _profiles;
  ThemeMode get themeMode => _themeMode;
  AppPalettePreset get palettePreset => _palettePreset;
  bool get isLoading => _isLoading;
  bool get isBusy => _isBusy;
  String? get errorMessage => _errorMessage;
  String? get statusMessage => _statusMessage;
  CodexProfile? get defaultCliProfile {
    final targetId = _defaultCliProfileId;
    if (targetId == null) {
      return null;
    }
    for (final profile in _profiles) {
      if (profile.id == targetId) {
        return profile;
      }
    }
    return null;
  }
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

  bool isDefaultCliProfile(String profileId) => _defaultCliProfileId == profileId;

  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    try {
      final stored = await _profileStore.load();
      final discovered = await _profileStore.mergeDiscoveredProfiles(
        stored.profiles,
      );
      _profiles = discovered.profiles;
      _themeMode = _themeModeFromName(stored.themeModeName);
      _palettePreset = AppPalettePresetX.fromStorageName(
        stored.palettePresetName,
      );
      _defaultCliProfileId = _resolveDefaultCliProfileId(
        stored.defaultCliProfileId,
      );
      _activeProfileId =
          stored.activeProfileId ?? _profiles.firstOrNull?.id;
      if (discovered.importedCount > 0 ||
          stored.defaultCliProfileId != _defaultCliProfileId) {
        await _profileStore.save(
          activeProfileId: _activeProfileId,
          defaultCliProfileId: _defaultCliProfileId,
          profiles: _profiles,
          themeModeName: _themeModeName(_themeMode),
          palettePresetName: _palettePreset.storageName,
        );
        _statusMessage = discovered.importedCount == 1
            ? 'Imported 1 existing Codex account automatically.'
            : 'Imported ${discovered.importedCount} existing Codex accounts automatically.';
      }
      await _restartProfileWatchers();
      final initialProfile = activeProfile;
      if (initialProfile != null) {
        unawaited(_refreshProfileSilently(initialProfile.id));
      }
      unawaited(_bootstrapLiveLimits());
      _startLiveUsagePolling();
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

    _profiles = [..._profiles, profile];
    _activeProfileId = profile.id;
    await _persist(statusMessage: 'Created profile "${profile.label}".');
    await _restartProfileWatchers();
    unawaited(_refreshProfileSilently(profile.id, refreshUsage: true));
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

    _profiles = _profiles
        .map(
          (item) => item.id == profileId
              ? item.copyWith(label: normalizedLabel)
              : item,
        )
        .toList();

    await _persist(
      statusMessage: 'Renamed "${profile.label}" to "$normalizedLabel".',
    );
  }

  Future<void> moveProfileUp(String profileId) async {
    final index = _profiles.indexWhere((profile) => profile.id == profileId);
    if (index <= 0) {
      return;
    }

    final reordered = [..._profiles];
    final current = reordered.removeAt(index);
    reordered.insert(index - 1, current);
    _profiles = reordered;
    await _persist(statusMessage: 'Moved "${current.label}" up.');
  }

  Future<void> moveProfileDown(String profileId) async {
    final index = _profiles.indexWhere((profile) => profile.id == profileId);
    if (index == -1 || index >= _profiles.length - 1) {
      return;
    }

    final reordered = [..._profiles];
    final current = reordered.removeAt(index);
    reordered.insert(index + 1, current);
    _profiles = reordered;
    await _persist(statusMessage: 'Moved "${current.label}" down.');
  }

  Future<void> reorderProfiles(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= _profiles.length) {
      return;
    }

    final reordered = [..._profiles];
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }
    if (newIndex < 0 || newIndex >= reordered.length) {
      return;
    }

    final profile = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, profile);
    _profiles = reordered;
    await _persist(statusMessage: 'Reordered "${profile.label}".');
  }

  Future<String> suggestCodexHome(String label) {
    return _profileStore.defaultCodexHomeForLabel(label);
  }

  Future<void> selectProfile(String profileId) async {
    _activeProfileId = profileId;
    await _persist(statusMessage: 'Selected profile.');
    unawaited(_refreshProfileSilently(profileId));
  }

  Future<void> setThemeMode(ThemeMode themeMode) async {
    _themeMode = themeMode;
    await _persist(statusMessage: 'Theme updated.');
  }

  Future<void> setPalettePreset(AppPalettePreset palettePreset) async {
    _palettePreset = palettePreset;
    await _persist(statusMessage: 'Palette updated.');
  }

  Future<void> refreshActiveProfile() async {
    final profile = activeProfile;
    if (profile == null) {
      return;
    }

    await _runGuarded(() async {
      final probe = await _commandService.probeLogin(
        _effectiveProfile(profile),
      );
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
      await _syncProfileUsageNow(
        profileId: profile.id,
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
      await _commandService.launchCodex(_effectiveProfile(profile));
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
      await _commandService.launchDeviceAuthLogin(_effectiveProfile(profile));
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

  Future<void> makeActiveProfileDefault() async {
    final profile = activeProfile;
    if (profile == null) {
      return;
    }

    await _runGuarded(() async {
      await _switchDefaultCliProfile(profile.id);
      _statusMessage =
          'Set "${profile.label}" as the default terminal Codex account. Reopen your terminal and run codex.';
      notifyListeners();
    });
  }

  Future<void> applyOfficialUsageSnapshot(
    CodexUsageSnapshot snapshot, {
    String? statusMessage,
  }) async {
    final profile = activeProfile;
    if (profile == null) {
      return;
    }

    final currentProbe = profile.lastProbe;
    final nextProbe = CodexProbe(
      loginSummary:
          currentProbe?.loginSummary ?? 'Official usage synced from ChatGPT.',
      checkedAt: DateTime.now(),
      isLoggedIn: currentProbe?.isLoggedIn ?? true,
      usageSnapshot: snapshot,
    );

    _profiles = _profiles
        .map(
          (item) =>
              item.id == profile.id ? item.copyWith(lastProbe: nextProbe) : item,
        )
        .toList();
    await _persist(
      statusMessage:
          statusMessage ??
          'Synced the official usage page for "${profile.label}".',
    );
  }

  String manualStatusCommandForActive() {
    final profile = activeProfile;
    return profile == null
        ? ''
        : _commandService.buildManualStatusCommand(_effectiveProfile(profile));
  }

  String loginCommandForActive() {
    final profile = activeProfile;
    return profile == null
        ? ''
        : _commandService.buildLoginCommand(_effectiveProfile(profile));
  }

  String deviceAuthFallbackCommandForActive() {
    final profile = activeProfile;
    return profile == null
        ? ''
        : _commandService.buildDeviceAuthFallbackCommand(
            _effectiveProfile(profile),
          );
  }

  String zedHintForActive() {
    final profile = activeProfile;
    return profile == null
        ? ''
        : _commandService.buildZedHint(_effectiveProfile(profile));
  }

  Future<void> _persist({String? statusMessage}) async {
    await _profileStore.save(
      activeProfileId: _activeProfileId,
      defaultCliProfileId: _defaultCliProfileId,
      profiles: _profiles,
      themeModeName: _themeModeName(_themeMode),
      palettePresetName: _palettePreset.storageName,
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

  Future<void> _restartProfileWatchers() async {
    for (final subscription in _profileWatchers.values) {
      await subscription.cancel();
    }
    _profileWatchers.clear();

    for (final timer in _watchDebounceTimers.values) {
      timer.cancel();
    }
    _watchDebounceTimers.clear();

    for (final profile in _profiles) {
      final directory = Directory(_effectiveCodexHome(profile));
      await directory.create(recursive: true);
      _profileWatchers[profile.id] = directory.watch(recursive: true).listen((
        event,
      ) {
        final path = event.path;
        if (!path.endsWith('.jsonl') && !path.endsWith('auth.json')) {
          return;
        }

        _watchDebounceTimers[profile.id]?.cancel();
        _watchDebounceTimers[profile.id] = Timer(
          const Duration(milliseconds: 350),
          () {
            if (path.endsWith('auth.json')) {
              unawaited(_refreshProfileSilently(profile.id));
              return;
            }
            unawaited(
              _refreshUsageSnapshotSilently(profile.id, forceRescan: true),
            );
          },
        );
      });
    }

    _startLiveUsagePolling();
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
        _effectiveProfile(profile),
        refreshUsage: refreshUsage,
      );
      final preservedProbe = _preserveOfficialUsageSnapshot(
        currentProbe: profile.lastProbe,
        nextProbe: probe,
        allowOverride: refreshUsage,
      );
      _profiles = _profiles
          .map(
            (item) => item.id == profileId
                ? item.copyWith(lastProbe: preservedProbe)
                : item,
          )
          .toList();
      await _profileStore.save(
        activeProfileId: _activeProfileId,
        defaultCliProfileId: _defaultCliProfileId,
        profiles: _profiles,
        themeModeName: _themeModeName(_themeMode),
        palettePresetName: _palettePreset.storageName,
      );
      if (successMessage != null) {
        _statusMessage = successMessage;
      }
      notifyListeners();
    } catch (_) {
      // Silent background refresh should not interrupt the main UI flow.
    }
  }

  Future<void> _syncProfileUsageNow({
    required String profileId,
    String? statusMessage,
  }) async {
    final profile = _findProfile(profileId);
    if (profile == null) {
      return;
    }

    final probe = await _commandService.probeLogin(
      _effectiveProfile(profile),
      refreshUsage: true,
    );
    _profiles = _profiles
        .map(
          (item) =>
              item.id == profileId ? item.copyWith(lastProbe: probe) : item,
        )
        .toList();
    await _persist(statusMessage: statusMessage);
  }

  Future<void> _refreshUsageSnapshotSilently(
    String profileId, {
    bool forceRescan = false,
  }) async {
    final profile = _findProfile(profileId);
    if (profile == null) {
      return;
    }

    try {
      final snapshot = await _commandService.readLatestUsageSnapshot(
        _effectiveProfile(profile),
        forceRescan: forceRescan,
      );
      if (snapshot == null) {
        return;
      }

      final currentProbe = profile.lastProbe;
      final currentSnapshot = currentProbe?.usageSnapshot;
      if (_isOfficialUsageSnapshot(currentSnapshot)) {
        return;
      }
      if (currentSnapshot != null &&
          !snapshot.capturedAt.isAfter(currentSnapshot.capturedAt)) {
        return;
      }

      final nextProbe = CodexProbe(
        loginSummary: _liveUsageSummary(currentProbe),
        checkedAt: _latestDate(
          currentProbe?.checkedAt,
          snapshot.capturedAt,
        ),
        isLoggedIn: true,
        usageSnapshot: snapshot,
      );

      _profiles = _profiles
          .map(
            (item) =>
                item.id == profileId ? item.copyWith(lastProbe: nextProbe) : item,
          )
          .toList();
      await _profileStore.save(
        activeProfileId: _activeProfileId,
        defaultCliProfileId: _defaultCliProfileId,
        profiles: _profiles,
        themeModeName: _themeModeName(_themeMode),
        palettePresetName: _palettePreset.storageName,
      );
      notifyListeners();
    } catch (_) {
      // Best-effort live usage refresh should stay silent.
    }
  }

  Future<void> _bootstrapLiveLimits() async {
    if (_isBootstrappingLive || _profiles.isEmpty) {
      return;
    }

    _isBootstrappingLive = true;
    try {
      for (final profile in List<CodexProfile>.from(_profiles)) {
        if (!_shouldBootstrapProfile(profile)) {
          continue;
        }
        try {
          await _syncProfileUsageNow(profileId: profile.id);
        } catch (_) {
          // Best-effort startup sync; keep going for the remaining profiles.
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      _statusMessage = 'Live limits refreshed on startup.';
      notifyListeners();
    } finally {
      _isBootstrappingLive = false;
    }
  }

  bool _shouldBootstrapProfile(CodexProfile profile) {
    final probe = profile.lastProbe;
    if (probe == null || !probe.isLoggedIn) {
      return true;
    }
    final snapshot = probe.usageSnapshot;
    if (snapshot == null) {
      return true;
    }
    return DateTime.now().difference(snapshot.capturedAt) >
        const Duration(minutes: 5);
  }

  void _startLiveUsagePolling() {
    _liveUsagePollTimer?.cancel();
    if (_profiles.isEmpty) {
      return;
    }

    var pollCount = 0;
    _liveUsagePollTimer = Timer.periodic(const Duration(seconds: 4), (
      timer,
    ) {
      pollCount += 1;
      final forceRescan = pollCount % 8 == 0;
      for (final profile in List<CodexProfile>.from(_profiles)) {
        unawaited(
          _refreshUsageSnapshotSilently(
            profile.id,
            forceRescan: forceRescan,
          ),
        );
      }
    });
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
        final probe = await _commandService.probeLogin(
          _effectiveProfile(profile),
        );
        _profiles = _profiles
            .map(
              (item) =>
                  item.id == profileId ? item.copyWith(lastProbe: probe) : item,
            )
            .toList();
        await _profileStore.save(
          activeProfileId: _activeProfileId,
          defaultCliProfileId: _defaultCliProfileId,
          profiles: _profiles,
          themeModeName: _themeModeName(_themeMode),
          palettePresetName: _palettePreset.storageName,
        );

        if (probe.isLoggedIn) {
          final enrichedProbe = await _commandService.probeLogin(
            _effectiveProfile(profile),
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
            defaultCliProfileId: _defaultCliProfileId,
            profiles: _profiles,
            themeModeName: _themeModeName(_themeMode),
            palettePresetName: _palettePreset.storageName,
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

  String? _resolveDefaultCliProfileId(String? storedDefaultCliProfileId) {
    if (storedDefaultCliProfileId != null &&
        _findProfile(storedDefaultCliProfileId) != null) {
      return storedDefaultCliProfileId;
    }

    final defaultHome = _normalizeHome(_commandService.defaultCodexHome());
    for (final profile in _profiles) {
      if (_normalizeHome(profile.codexHome) == defaultHome) {
        return profile.id;
      }
    }
    return null;
  }

  Future<void> _switchDefaultCliProfile(String profileId) async {
    final nextProfile = _findProfile(profileId);
    if (nextProfile == null) {
      return;
    }

    final previousDefaultId = _defaultCliProfileId;
    if (previousDefaultId != null && previousDefaultId != profileId) {
      final previousProfile = _findProfile(previousDefaultId);
      if (previousProfile != null &&
          _normalizeHome(previousProfile.codexHome) !=
              _commandService.defaultCodexHome()) {
        await _commandService.syncCodexHome(
          sourceHome: _commandService.defaultCodexHome(),
          targetHome: previousProfile.codexHome,
        );
      }
    }

    await _commandService.makeProfileDefault(nextProfile);
    _defaultCliProfileId = profileId;
    await _persist();
    await _restartProfileWatchers();
    unawaited(_refreshProfileSilently(profileId));
  }

  CodexProfile _effectiveProfile(CodexProfile profile) {
    final effectiveHome = _effectiveCodexHome(profile);
    if (effectiveHome == profile.codexHome) {
      return profile;
    }
    return profile.copyWith(codexHome: effectiveHome);
  }

  String _effectiveCodexHome(CodexProfile profile) {
    if (profile.id == _defaultCliProfileId) {
      return _commandService.defaultCodexHome();
    }
    return profile.codexHome;
  }

  String _normalizeHome(String path) => Directory(path).absolute.path;

  String _liveUsageSummary(CodexProbe? probe) {
    if (probe == null || !probe.isLoggedIn) {
      return 'Signed in from local Codex session activity.';
    }
    return probe.loginSummary;
  }

  DateTime _latestDate(DateTime? left, DateTime right) {
    if (left == null || right.isAfter(left)) {
      return right;
    }
    return left;
  }

  CodexProbe _preserveOfficialUsageSnapshot({
    required CodexProbe? currentProbe,
    required CodexProbe nextProbe,
    required bool allowOverride,
  }) {
    final currentSnapshot = currentProbe?.usageSnapshot;
    if (!allowOverride && _isOfficialUsageSnapshot(currentSnapshot)) {
      return CodexProbe(
        loginSummary: nextProbe.loginSummary,
        checkedAt: nextProbe.checkedAt,
        isLoggedIn: nextProbe.isLoggedIn,
        usageSnapshot: currentSnapshot,
      );
    }
    return nextProbe;
  }

  bool _isOfficialUsageSnapshot(CodexUsageSnapshot? snapshot) =>
      snapshot?.limitName == officialUsageLimitName;

  @override
  void dispose() {
    _loginWatchTimer?.cancel();
    _liveUsagePollTimer?.cancel();
    for (final timer in _watchDebounceTimers.values) {
      timer.cancel();
    }
    for (final subscription in _profileWatchers.values) {
      subscription.cancel();
    }
    super.dispose();
  }

  ThemeMode _themeModeFromName(String name) {
    return switch (name) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      'system' => ThemeMode.system,
      _ => ThemeMode.dark,
    };
  }

  String _themeModeName(ThemeMode mode) {
    return switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
  }
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
