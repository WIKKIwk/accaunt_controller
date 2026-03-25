import 'package:clash/app_controller.dart';
import 'package:clash/models/codex_probe.dart';
import 'package:clash/models/codex_profile.dart';
import 'package:clash/models/codex_usage_snapshot.dart';
import 'package:clash/services/codex_command_service.dart';
import 'package:clash/services/profile_store.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final controller = AppController(
    profileStore: ProfileStore(),
    commandService: CodexCommandService(),
  );
  await controller.initialize();

  runApp(ClashApp(controller: controller));
}

class ClashApp extends StatelessWidget {
  const ClashApp({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final lightScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF4D7C99),
      brightness: Brightness.light,
    );
    final darkScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF84C7F2),
      brightness: Brightness.dark,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Codex Clash',
      themeMode: controller.themeMode,
      theme: ThemeData(colorScheme: lightScheme, useMaterial3: true),
      darkTheme: ThemeData(colorScheme: darkScheme, useMaterial3: true),
      home: ClashHomePage(controller: controller),
    );
  }
}

enum AppSection { home, accounts, settings }

class ClashHomePage extends StatefulWidget {
  const ClashHomePage({super.key, required this.controller});

  final AppController controller;

  @override
  State<ClashHomePage> createState() => _ClashHomePageState();
}

class _ClashHomePageState extends State<ClashHomePage> {
  AppSection _section = AppSection.home;
  bool _navExpanded = true;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('Codex Clash'), centerTitle: true),
          body: widget.controller.isLoading
              ? const Center(child: CircularProgressIndicator())
              : SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _NavigationPanel(
                          expanded: _navExpanded,
                          currentSection: _section,
                          onToggleExpanded: () {
                            setState(() {
                              _navExpanded = !_navExpanded;
                            });
                          },
                          onSectionSelected: (section) {
                            setState(() {
                              _section = section;
                            });
                          },
                          onAddAccount: () =>
                              _showAddProfileDialog(context, widget.controller),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            child: switch (_section) {
                              AppSection.home => _HomeDashboard(
                                key: const ValueKey('home'),
                                controller: widget.controller,
                                onManageAccount: (profile) async {
                                  await widget.controller.selectProfile(
                                    profile.id,
                                  );
                                  if (mounted) {
                                    setState(() {
                                      _section = AppSection.accounts;
                                    });
                                  }
                                },
                              ),
                              AppSection.accounts => _AccountsWorkspace(
                                key: const ValueKey('accounts'),
                                controller: widget.controller,
                                onAddAccount: () => _showAddProfileDialog(
                                  context,
                                  widget.controller,
                                ),
                              ),
                              AppSection.settings => _SettingsWorkspace(
                                key: const ValueKey('settings'),
                                controller: widget.controller,
                              ),
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        );
      },
    );
  }
}

class _NavigationPanel extends StatelessWidget {
  const _NavigationPanel({
    required this.expanded,
    required this.currentSection,
    required this.onToggleExpanded,
    required this.onSectionSelected,
    required this.onAddAccount,
  });

  final bool expanded;
  final AppSection currentSection;
  final VoidCallback onToggleExpanded;
  final ValueChanged<AppSection> onSectionSelected;
  final VoidCallback onAddAccount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: expanded ? 248 : 88,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: Row(
                children: [
                  IconButton(
                    onPressed: onToggleExpanded,
                    icon: Icon(expanded ? Icons.menu_open : Icons.menu),
                    tooltip: expanded ? 'Collapse menu' : 'Expand menu',
                  ),
                  if (expanded) ...[
                    const SizedBox(width: 4),
                    Text(
                      'Modules',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: NavigationRail(
                extended: expanded,
                backgroundColor: Colors.transparent,
                selectedIndex: currentSection.index,
                onDestinationSelected: (index) =>
                    onSectionSelected(AppSection.values[index]),
                labelType: expanded
                    ? NavigationRailLabelType.none
                    : NavigationRailLabelType.all,
                leading: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: expanded
                      ? FilledButton.tonalIcon(
                          onPressed: onAddAccount,
                          icon: const Icon(Icons.add),
                          label: const Text('Add account'),
                        )
                      : IconButton.filledTonal(
                          onPressed: onAddAccount,
                          tooltip: 'Add account',
                          icon: const Icon(Icons.add),
                        ),
                ),
                destinations: const [
                  NavigationRailDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home_rounded),
                    label: Text('Home'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.manage_accounts_outlined),
                    selectedIcon: Icon(Icons.manage_accounts_rounded),
                    label: Text('Accounts'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.settings_outlined),
                    selectedIcon: Icon(Icons.settings_rounded),
                    label: Text('Settings'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeDashboard extends StatelessWidget {
  const _HomeDashboard({
    super.key,
    required this.controller,
    required this.onManageAccount,
  });

  final AppController controller;
  final Future<void> Function(CodexProfile profile) onManageAccount;

  @override
  Widget build(BuildContext context) {
    final profiles = controller.profiles;
    final scheme = Theme.of(context).colorScheme;

    if (profiles.isEmpty) {
      return _EmptyModuleState(
        icon: Icons.home_outlined,
        title: 'No accounts yet',
        description:
            'Add your first account and this Home dashboard will show every account limit in one place.',
      );
    }

    final signedInCount = profiles.where((profile) {
      return profile.lastProbe?.isLoggedIn ?? false;
    }).length;
    final needingLoginCount = profiles.length - signedInCount;
    final accountsWithLimits = profiles.where((profile) {
      return profile.lastProbe?.usageSnapshot?.windows.isNotEmpty ?? false;
    }).length;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1040),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Home', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text(
                'A quick dashboard of every Codex account and its current limits.',
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _MetricChip(label: '${profiles.length} accounts'),
                  _MetricChip(label: '$signedInCount signed in'),
                  _MetricChip(label: '$needingLoginCount need login'),
                  _MetricChip(label: '$accountsWithLimits with limits'),
                ],
              ),
              const SizedBox(height: 20),
              Card(
                elevation: 0,
                color: scheme.surfaceContainerLow,
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'All accounts',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'A proportional overview of all current account limits.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 20),
                      for (var index = 0; index < profiles.length; index++) ...[
                        if (index > 0) const Divider(height: 32),
                        _HomeAccountRow(
                          profile: profiles[index],
                          onManage: () => onManageAccount(profiles[index]),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeAccountRow extends StatelessWidget {
  const _HomeAccountRow({required this.profile, required this.onManage});

  final CodexProfile profile;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final probe = profile.lastProbe;
    final snapshot = probe?.usageSnapshot;
    final isLoggedIn = probe?.isLoggedIn ?? false;
    final windows =
        snapshot?.windows.take(2).toList() ?? const <CodexUsageWindow>[];

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AccountIdentity(
                profile: profile,
                isLoggedIn: isLoggedIn,
                summary: _compactLimitSummary(probe),
              ),
              const SizedBox(height: 16),
              _LimitsPreview(isLoggedIn: isLoggedIn, windows: windows),
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: onManage,
                icon: const Icon(Icons.arrow_forward),
                label: const Text('Manage'),
              ),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 250,
              child: _AccountIdentity(
                profile: profile,
                isLoggedIn: isLoggedIn,
                summary: _compactLimitSummary(probe),
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: _LimitsPreview(isLoggedIn: isLoggedIn, windows: windows),
            ),
            const SizedBox(width: 24),
            FilledButton.tonalIcon(
              onPressed: onManage,
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Manage'),
            ),
          ],
        );
      },
    );
  }
}

class _AccountIdentity extends StatelessWidget {
  const _AccountIdentity({
    required this.profile,
    required this.isLoggedIn,
    required this.summary,
  });

  final CodexProfile profile;
  final bool isLoggedIn;
  final String? summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              child: Text(profile.label.characters.first.toUpperCase()),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(profile.label, style: theme.textTheme.titleMedium),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _StatusChip(
              label: isLoggedIn ? 'Signed in' : 'Not signed in',
              icon: isLoggedIn
                  ? Icons.check_circle_outline
                  : Icons.info_outline,
            ),
            if (summary != null)
              _StatusChip(label: summary!, icon: Icons.timelapse_rounded),
          ],
        ),
      ],
    );
  }
}

class _LimitsPreview extends StatelessWidget {
  const _LimitsPreview({required this.isLoggedIn, required this.windows});

  final bool isLoggedIn;
  final List<CodexUsageWindow> windows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (!isLoggedIn) {
      return Text(
        'This account needs login before limits can be shown.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      );
    }

    if (windows.isEmpty) {
      return Text(
        'No local limit snapshot yet. Open this account and use "Sync limits" once.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      );
    }

    return Column(
      children: [
        for (var index = 0; index < windows.length; index++) ...[
          _DashboardLimitRow(window: windows[index]),
          if (index < windows.length - 1) const SizedBox(height: 14),
        ],
      ],
    );
  }
}

class _DashboardLimitRow extends StatelessWidget {
  const _DashboardLimitRow({required this.window});

  final CodexUsageWindow window;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(window.label, style: theme.textTheme.labelLarge),
            ),
            Text(
              '${window.remainingPercent}% left',
              style: theme.textTheme.labelLarge?.copyWith(
                color: scheme.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: window.remainingPercent / 100,
          minHeight: 8,
          borderRadius: BorderRadius.circular(999),
        ),
      ],
    );
  }
}

class _AccountsWorkspace extends StatelessWidget {
  const _AccountsWorkspace({
    super.key,
    required this.controller,
    required this.onAddAccount,
  });

  final AppController controller;
  final VoidCallback onAddAccount;

  @override
  Widget build(BuildContext context) {
    if (controller.profiles.isEmpty || controller.activeProfile == null) {
      return _EmptyModuleState(
        icon: Icons.manage_accounts_outlined,
        title: 'No selected account',
        description:
            'Add an account and select it here to manage login and refresh its limits.',
        action: FilledButton.icon(
          onPressed: onAddAccount,
          icon: const Icon(Icons.add),
          label: const Text('Add account'),
        ),
      );
    }

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 320,
            child: _AccountsListCard(controller: controller),
          ),
          VerticalDivider(width: 1, thickness: 1),
          Expanded(child: _AccountDetailCard(controller: controller)),
        ],
      ),
    );
  }
}

class _AccountsListCard extends StatelessWidget {
  const _AccountsListCard({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Accounts', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Select a profile to manage its login and limits.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ReorderableListView.builder(
                buildDefaultDragHandles: false,
                itemBuilder: (context, index) {
                  final profile = controller.profiles[index];
                  return Padding(
                    key: ValueKey(profile.id),
                    padding: EdgeInsets.only(
                      bottom: index == controller.profiles.length - 1 ? 0 : 12,
                    ),
                    child: ReorderableDelayedDragStartListener(
                      index: index,
                      child: _AccountListTile(
                        profile: profile,
                        selected: controller.activeProfile?.id == profile.id,
                        onTap: () => controller.selectProfile(profile.id),
                        onRename: () => _showRenameProfileDialog(
                          context,
                          controller,
                          profile,
                        ),
                      ),
                    ),
                  );
                },
                itemCount: controller.profiles.length,
                onReorder: controller.reorderProfiles,
              ),
            ),
            if (controller.errorMessage case final error?)
              _InlineBanner(message: error, tone: BannerTone.error),
            if (controller.statusMessage case final message?)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: _InlineBanner(message: message, tone: BannerTone.info),
              ),
          ],
        ),
      ),
    );
  }
}

class _AccountListTile extends StatelessWidget {
  const _AccountListTile({
    required this.profile,
    required this.selected,
    required this.onTap,
    required this.onRename,
  });

  final CodexProfile profile;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onRename;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final probe = profile.lastProbe;

    Future<void> openMenu(Offset globalPosition) async {
      final overlay =
          Overlay.of(context).context.findRenderObject() as RenderBox;
      final position = RelativeRect.fromRect(
        Rect.fromPoints(globalPosition, globalPosition),
        Offset.zero & overlay.size,
      );

      final action = await showMenu<String>(
        context: context,
        position: position,
        items: const [
          PopupMenuItem<String>(value: 'rename', child: Text('Rename')),
        ],
      );

      switch (action) {
        case 'rename':
          onRename();
        case null:
          break;
      }
    }

    return Card(
      elevation: 0,
      color: selected ? scheme.secondaryContainer : scheme.surfaceContainer,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onSecondaryTapDown: (details) async {
          await openMenu(details.globalPosition);
        },
        child: ListTile(
          title: Text(profile.label),
          subtitle: Text(
            probe == null
                ? 'Checking...'
                : probe.isLoggedIn
                ? 'Signed in'
                : 'Not signed in',
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.drag_indicator),
              IconButton(
                tooltip: 'More',
                onPressed: () async {
                  final box = context.findRenderObject() as RenderBox;
                  final center = box.localToGlobal(
                    box.size.center(Offset.zero),
                  );
                  await openMenu(center);
                },
                icon: const Icon(Icons.more_vert),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountDetailCard extends StatelessWidget {
  const _AccountDetailCard({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final profile = controller.activeProfile!;
    final probe = profile.lastProbe;
    final actionsDisabled = controller.isBusy;

    return Card(
      elevation: 0,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              profile.label,
                              style: theme.textTheme.headlineMedium,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Rename account',
                            onPressed: () => _showRenameProfileDialog(
                              context,
                              controller,
                              profile,
                            ),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _StatusChip(
                            label: probe == null
                                ? 'Checking...'
                                : probe.isLoggedIn
                                ? 'Signed in'
                                : 'Not signed in',
                            icon: probe?.isLoggedIn ?? false
                                ? Icons.check_circle_outline
                                : Icons.info_outline,
                          ),
                          if (_compactLimitSummary(probe) case final summary?)
                            _StatusChip(
                              label: summary,
                              icon: Icons.timelapse_rounded,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.icon(
                      onPressed: actionsDisabled
                          ? null
                          : controller.launchLogin,
                      icon: const Icon(Icons.login),
                      label: const Text('Login'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: actionsDisabled
                          ? null
                          : controller.refreshActiveProfile,
                      icon: const Icon(Icons.sync),
                      label: const Text('Check now'),
                    ),
                    MenuAnchor(
                      menuChildren: [
                        MenuItemButton(
                          onPressed: actionsDisabled
                              ? null
                              : controller.syncActiveProfileLimits,
                          leadingIcon: const Icon(Icons.bolt),
                          child: const Text('Sync limits'),
                        ),
                        MenuItemButton(
                          onPressed: actionsDisabled
                              ? null
                              : controller.launchCodex,
                          leadingIcon: const Icon(Icons.terminal),
                          child: const Text('Launch Codex'),
                        ),
                        MenuItemButton(
                          onPressed: actionsDisabled
                              ? null
                              : controller.openUsagePage,
                          leadingIcon: const Icon(Icons.open_in_new),
                          child: const Text('Usage page'),
                        ),
                      ],
                      builder: (context, menuController, child) {
                        return OutlinedButton.icon(
                          onPressed: actionsDisabled
                              ? null
                              : () {
                                  if (menuController.isOpen) {
                                    menuController.close();
                                  } else {
                                    menuController.open();
                                  }
                                },
                          icon: const Icon(Icons.more_horiz),
                          label: const Text('More actions'),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text('Limits', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              probe?.loginSummary ?? 'Checking account status...',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            _LimitsSection(probe: probe),
            const SizedBox(height: 20),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: const Text('Technical details'),
              subtitle: Text(
                'Profile folder, plan, and last check time',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              children: [
                const Divider(),
                _MetaLine(label: 'Profile folder', value: profile.codexHome),
                _MetaLine(
                  label: 'Last checked',
                  value: probe == null
                      ? 'Not checked yet'
                      : _formatDate(probe.checkedAt),
                ),
                _MetaLine(
                  label: 'Plan',
                  value: probe?.usageSnapshot?.planType ?? 'Unknown',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(label),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

class _SettingsWorkspace extends StatelessWidget {
  const _SettingsWorkspace({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 840),
        child: Card(
          elevation: 0,
          color: scheme.surfaceContainerLow,
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Settings', style: theme.textTheme.headlineMedium),
                const SizedBox(height: 8),
                Text(
                  'Adjust app appearance and other preferences.',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                Card.outlined(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Appearance', style: theme.textTheme.titleLarge),
                        const SizedBox(height: 8),
                        Text(
                          'Choose how Codex Clash should look.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 20),
                        SegmentedButton<ThemeMode>(
                          segments: const [
                            ButtonSegment<ThemeMode>(
                              value: ThemeMode.light,
                              icon: Icon(Icons.light_mode_outlined),
                              label: Text('Light'),
                            ),
                            ButtonSegment<ThemeMode>(
                              value: ThemeMode.dark,
                              icon: Icon(Icons.dark_mode_outlined),
                              label: Text('Dark'),
                            ),
                            ButtonSegment<ThemeMode>(
                              value: ThemeMode.system,
                              icon: Icon(Icons.brightness_auto_outlined),
                              label: Text('System'),
                            ),
                          ],
                          selected: {controller.themeMode},
                          onSelectionChanged: (selection) async {
                            final selectedMode = selection.first;
                            await controller.setThemeMode(selectedMode);
                          },
                        ),
                        const SizedBox(height: 20),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(switch (controller.themeMode) {
                            ThemeMode.light => Icons.light_mode,
                            ThemeMode.dark => Icons.dark_mode,
                            ThemeMode.system => Icons.brightness_auto,
                          }),
                          title: const Text('Current theme'),
                          subtitle: Text(switch (controller.themeMode) {
                            ThemeMode.light => 'Light',
                            ThemeMode.dark => 'Dark',
                            ThemeMode.system => 'Follow system',
                          }),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LimitsSection extends StatelessWidget {
  const _LimitsSection({required this.probe});

  final CodexProbe? probe;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final snapshot = probe?.usageSnapshot;

    if (probe == null || !probe!.isLoggedIn) {
      return Text(
        'Sign in to this profile first. Then press "Check now".',
        style: theme.textTheme.bodyLarge?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      );
    }

    if (snapshot == null || snapshot.windows.isEmpty) {
      return Text(
        'No local limit snapshot yet. Press "Sync limits" once, then "Check now" will stay fast.',
        style: theme.textTheme.bodyLarge?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final window in snapshot.windows) ...[
          Card.outlined(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              window.label,
                              style: theme.textTheme.titleMedium,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Resets ${_formatDate(window.resetsAt)}',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '${window.remainingPercent}% left',
                        style: theme.textTheme.headlineSmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: window.remainingPercent / 100,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(value, style: theme.textTheme.bodyLarge),
        ],
      ),
    );
  }
}

class _InlineBanner extends StatelessWidget {
  const _InlineBanner({required this.message, required this.tone});

  final String message;
  final BannerTone tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (tone) {
      BannerTone.info => scheme.secondary,
      BannerTone.error => scheme.error,
    };

    return Card(
      elevation: 0,
      color: color.withValues(alpha: 0.14),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          message,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: color),
        ),
      ),
    );
  }
}

class _EmptyModuleState extends StatelessWidget {
  const _EmptyModuleState({
    required this.icon,
    required this.title,
    required this.description,
    this.action,
  });

  final IconData icon;
  final String title;
  final String description;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Card(
          elevation: 0,
          color: scheme.surfaceContainerLow,
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 48, color: scheme.primary),
                const SizedBox(height: 16),
                Text(title, style: theme.textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(
                  description,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                if (action != null) ...[const SizedBox(height: 20), action!],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _showAddProfileDialog(
  BuildContext context,
  AppController controller,
) async {
  final labelController = TextEditingController();
  final homeController = TextEditingController();
  final notesController = TextEditingController();
  var showAdvanced = false;

  String resolvedLabel() {
    final typedLabel = labelController.text.trim();
    if (typedLabel.isNotEmpty) {
      return typedLabel;
    }
    return 'Account ${controller.profiles.length + 1}';
  }

  Future<String> resolvedHome() async {
    final typedHome = homeController.text.trim();
    if (typedHome.isNotEmpty) {
      return typedHome;
    }
    return controller.suggestCodexHome(resolvedLabel());
  }

  await showDialog<void>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Add account'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: labelController,
                    decoration: const InputDecoration(
                      labelText: 'Account name',
                      hintText: 'Optional',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () {
                        setState(() {
                          showAdvanced = !showAdvanced;
                        });
                      },
                      icon: Icon(showAdvanced ? Icons.expand_less : Icons.tune),
                      label: Text(
                        showAdvanced
                            ? 'Hide advanced options'
                            : 'Advanced options',
                      ),
                    ),
                  ),
                  if (showAdvanced) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: homeController,
                      decoration: const InputDecoration(
                        labelText: 'Profile folder',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notesController,
                      maxLines: 3,
                      decoration: const InputDecoration(labelText: 'Notes'),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  final finalLabel = resolvedLabel();
                  final finalHome = await resolvedHome();

                  await controller.addProfile(
                    label: finalLabel,
                    codexHome: finalHome,
                    notes: notesController.text,
                  );

                  if (context.mounted) {
                    Navigator.of(context).pop();
                  }
                },
                child: const Text('Create'),
              ),
            ],
          );
        },
      );
    },
  );
}

Future<void> _showRenameProfileDialog(
  BuildContext context,
  AppController controller,
  CodexProfile profile,
) async {
  final labelController = TextEditingController(text: profile.label);

  await showDialog<void>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Rename account'),
        content: TextField(
          controller: labelController,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Account name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              await controller.renameProfile(
                profileId: profile.id,
                label: labelController.text,
              );
              if (context.mounted) {
                Navigator.of(context).pop();
              }
            },
            child: const Text('Save'),
          ),
        ],
      );
    },
  );
}

String? _compactLimitSummary(CodexProbe? probe) {
  final snapshot = probe?.usageSnapshot;
  if (snapshot == null || snapshot.windows.isEmpty) {
    return null;
  }

  return snapshot.windows
      .map(
        (window) =>
            '${window.label.replaceAll(' limit', '')} ${window.remainingPercent}% left',
      )
      .join(' • ');
}

String _formatDate(DateTime dateTime) {
  final local = dateTime.toLocal();
  final month = _monthNames[local.month - 1];
  final twoDigitMinute = local.minute.toString().padLeft(2, '0');
  return '$month ${local.day}, ${local.year} ${local.hour}:$twoDigitMinute';
}

const List<String> _monthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

enum BannerTone { info, error }
