import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/app_urls.dart';
import '../../../core/services/app_config_provider.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/utils/app_error.dart';
import '../../../core/utils/external_links.dart';
import '../../../core/utils/result.dart';
import '../../../core/utils/share_utils.dart';
import '../../auth/providers/auth_provider.dart';
import '../domain/account_deletion_copy.dart';
import '../domain/models/profile.dart';
import '../providers/profile_provider.dart';
import 'widgets/colorblind_selector.dart';
import 'widgets/contact_support_tile.dart';
import 'widgets/edit_name_dialog.dart';
import 'widgets/guest_account_card.dart';
import 'widgets/theme_mode_dropdown.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  late bool _hapticEnabled;
  late bool _soundEnabled;
  late String _colorblindMode;
  bool _settingsInitialized = false;
  bool _busy = false;

  void _initSettingsFromProfile(UserProfile? profile) {
    if (_settingsInitialized) return;
    _hapticEnabled = profile?.hapticEnabled ?? StorageService.hapticEnabled;
    _soundEnabled = profile?.soundEnabled ?? StorageService.soundEnabled;
    _colorblindMode = profile?.colorblindMode ?? StorageService.colorblindMode;
    _settingsInitialized = true;
  }

  void _initSettingsFromStorage() {
    if (_settingsInitialized) return;
    _hapticEnabled = StorageService.hapticEnabled;
    _soundEnabled = StorageService.soundEnabled;
    _colorblindMode = StorageService.colorblindMode;
    _settingsInitialized = true;
  }

  @override
  Widget build(BuildContext context) {
    final profileState = ref.watch(profileNotifierProvider);
    ref.watch(authNotifierProvider);
    final user = SupabaseService.auth.currentUser;
    final isAnonymous = user?.isAnonymous ?? true;

    ref.listen<bool>(deletionCancelledFlagProvider, (_, raised) {
      if (!raised) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Deletion cancelled. Welcome back!'),
        ),
      );
      ref.read(deletionCancelledFlagProvider.notifier).consume();
    });

    profileState.whenData(_initSettingsFromProfile);
    if (!_settingsInitialized) {
      _initSettingsFromStorage();
    }

    final profile = profileState.valueOrNull;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsetsDirectional.all(AppSizes.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Profile',
              style: Theme.of(context).textTheme.displayMedium,
            ),
            const SizedBox(height: AppSizes.lg),
            _buildAvatarSection(context, profile, isAnonymous),
            const SizedBox(height: AppSizes.xl),
            if (isAnonymous) ...[
              const GuestAccountCard(),
              const SizedBox(height: AppSizes.lg),
            ] else ...[
              _buildAccountSection(context, user, profile),
              const SizedBox(height: AppSizes.md),
            ],
            Text(
              'Settings',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSizes.md),
            _buildSettingsCard(context, profile),
            const SizedBox(height: AppSizes.md),
            Text(
              'App',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSizes.md),
            _buildAppCard(context, isAnonymous),
            const SizedBox(height: AppSizes.lg),
            if (!isAnonymous)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _busy ? null : () => _signOut(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.palette.error,
                    side: BorderSide(color: context.palette.error),
                  ),
                  child: const Text('Sign Out'),
                ),
              ),
            const SizedBox(height: AppSizes.lg),
          ],
        ),
      ),
    );
  }

  // ─── Sections ─────────────────────────────────────────────────────

  Widget _buildAvatarSection(
    BuildContext context,
    UserProfile? profile,
    bool isAnonymous,
  ) {
    final displayName = profile?.displayName.trim().isNotEmpty == true
        ? profile!.displayName
        : 'Guest Player';
    final initials = _getInitials(displayName);

    return Center(
      child: Column(
        children: [
          Container(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  AppColors.purpleGradientStart,
                  AppColors.purpleGradientEnd,
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.purpleGlow,
                  blurRadius: 16,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: CircleAvatar(
              radius: 40,
              backgroundColor: Colors.transparent,
              backgroundImage: profile?.avatarUrl != null
                  ? NetworkImage(profile!.avatarUrl!)
                  : null,
              child: profile?.avatarUrl == null
                  ? Text(
                      initials,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  : null,
            ),
          ),
          const SizedBox(height: AppSizes.sm),
          Semantics(
            button: profile != null,
            label: 'Display name $displayName. Tap to edit.',
            child: GestureDetector(
              onTap: profile == null
                  ? null
                  : () => _editDisplayName(context, profile.displayName),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    displayName,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (profile != null) ...[
                    const SizedBox(width: AppSizes.xs),
                    Icon(
                      Icons.edit_rounded,
                      size: 18,
                      color: context.palette.accent,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountSection(
    BuildContext context,
    User? user,
    UserProfile? profile,
  ) {
    final email = user?.email ?? 'No email';
    final providers = user?.appMetadata['providers'];
    final providerLabel = providers is List && providers.isNotEmpty
        ? providers.map((p) => _providerName(p.toString())).join(', ')
        : 'Registered';
    final memberSince = profile?.createdAt != null
        ? DateFormat.yMMMd().format(profile!.createdAt!)
        : 'Unknown';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Account',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: AppSizes.md),
        _Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.email_rounded),
                title: const Text('Email'),
                subtitle: Text(email),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.person_rounded),
                title: const Text('Signed in with'),
                subtitle: Text(providerLabel),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.calendar_today_rounded),
                title: const Text('Member Since'),
                subtitle: Text(memberSince),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsCard(
    BuildContext context,
    UserProfile? profile,
  ) {
    final reminder = ref.watch(reminderSettingsProvider).valueOrNull;
    final reminderEnabled = reminder?.enabled ?? false;
    final reminderTime = reminder?.time ?? const TimeOfDay(hour: 9, minute: 0);

    return _Card(
      child: Column(
        children: [
          const ListTile(
            leading: Icon(Icons.palette_rounded),
            title: Text('Theme'),
            trailing: ThemeModeDropdown(),
          ),
          const Divider(height: 1),
          SwitchListTile(
            secondary: const Icon(Icons.vibration_rounded),
            title: const Text('Haptic Feedback'),
            value: _hapticEnabled,
            onChanged: (value) {
              setState(() => _hapticEnabled = value);
              ref.read(profileNotifierProvider.notifier).updateHaptic(value);
            },
          ),
          const Divider(height: 1),
          SwitchListTile(
            secondary: const Icon(Icons.volume_up_rounded),
            title: const Text('Sound Effects'),
            value: _soundEnabled,
            onChanged: (value) {
              setState(() => _soundEnabled = value);
              ref.read(profileNotifierProvider.notifier).updateSound(value);
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.accessibility_new_rounded),
            title: const Text('Colorblind Mode'),
            subtitle: Text(_colorblindModeLabel(_colorblindMode)),
            trailing: Icon(
              Icons.chevron_right_rounded,
              color: context.palette.textTertiary,
            ),
            onTap: () => _showColorblindSelector(context),
          ),
          const Divider(height: 1),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_rounded),
            title: const Text('Daily reminder'),
            subtitle: Text(
              reminderEnabled
                  ? 'Every day at ${_formatTime(context, reminderTime)}'
                  : 'Get a nudge when a new puzzle drops',
            ),
            value: reminderEnabled,
            onChanged: (value) => _toggleReminder(context, value),
          ),
          if (reminderEnabled) ...[
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.schedule_rounded),
              title: const Text('Reminder time'),
              subtitle: Text(_formatTime(context, reminderTime)),
              trailing: Icon(
                Icons.chevron_right_rounded,
                color: context.palette.textTertiary,
              ),
              onTap: () => _pickReminderTime(context, reminderTime),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAppCard(BuildContext context, bool isAnonymous) {
    final version = ref.watch(appVersionLabelProvider).valueOrNull;

    return _Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.info_outline_rounded),
            title: const Text('About'),
            subtitle: Text(
              version == null ? 'Loading version…' : 'Version $version',
            ),
            trailing: Icon(
              Icons.chevron_right_rounded,
              color: context.palette.textTertiary,
            ),
            onTap: () => _showAboutDialog(context, version),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Privacy Policy'),
            trailing: Icon(
              Icons.open_in_new_rounded,
              color: context.palette.textTertiary,
            ),
            onTap: () => _openUrl(context, kPrivacyPolicyUrl),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('Terms of Service'),
            trailing: Icon(
              Icons.open_in_new_rounded,
              color: context.palette.textTertiary,
            ),
            onTap: () => _openUrl(context, kTermsUrl),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.block_rounded),
            title: const Text(AppStrings.blockedUsers),
            subtitle: const Text(AppStrings.blockedUsersSubtitle),
            trailing: Icon(
              Icons.chevron_right_rounded,
              color: context.palette.textTertiary,
            ),
            onTap: () => context.push('/blocked-users'),
          ),
          const Divider(height: 1),
          // Builder: the share sheet anchors to this row.
          Builder(
            builder: (rowContext) => ListTile(
            leading: const Icon(Icons.download_rounded),
            title: const Text('Export my data'),
            subtitle: const Text('Download a JSON copy of your data'),
            trailing: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    Icons.chevron_right_rounded,
                    color: context.palette.textTertiary,
                  ),
            onTap: _busy ? null : () => _exportData(rowContext),
          ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(
              Icons.delete_forever_rounded,
              color: context.palette.error,
            ),
            title: Text(
              'Delete Account',
              style: TextStyle(color: context.palette.error),
            ),
            subtitle: isAnonymous
                ? const Text('Removes this guest profile and its progress')
                : null,
            trailing: Icon(
              Icons.chevron_right_rounded,
              color: context.palette.error,
            ),
            onTap: _busy ? null : () => _showDeleteAccountDialog(context),
          ),
        ],
      ),
    );
  }

  // ─── Helpers ──────────────────────────────────────────────────────

  String _getInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return '${parts.first.characters.first}${parts.last.characters.first}'
        .toUpperCase();
  }

  String _providerName(String provider) => switch (provider) {
        'google' => 'Google',
        'apple' => 'Apple',
        'email' => 'Email',
        _ => provider,
      };

  String _colorblindModeLabel(String mode) {
    return switch (mode) {
      'deuteranopia' => 'Deuteranopia',
      'protanopia' => 'Protanopia',
      'tritanopia' => 'Tritanopia',
      _ => 'None',
    };
  }

  String _formatTime(BuildContext context, TimeOfDay time) =>
      MaterialLocalizations.of(context).formatTimeOfDay(
        time,
        alwaysUse24HourFormat: MediaQuery.of(context).alwaysUse24HourFormat,
      );

  Future<void> _openUrl(BuildContext context, String url) async {
    final ok = await openExternalUrl(url);
    if (!ok && context.mounted) _snack(context, 'Could not open $url');
  }

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // ─── Actions ──────────────────────────────────────────────────────

  Future<void> _editDisplayName(
    BuildContext context,
    String currentName,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => EditNameDialog(currentName: currentName),
    );

    if (result == true) {
      ref.invalidate(profileNotifierProvider);
      _settingsInitialized = false;
    }
  }

  void _showColorblindSelector(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => ColorblindSelector(
        currentMode: _colorblindMode,
      ),
    ).then((_) {
      final profile = ref.read(profileNotifierProvider).valueOrNull;
      if (profile != null) {
        setState(() {
          _colorblindMode = profile.colorblindMode;
        });
      }
    });
  }

  Future<void> _toggleReminder(BuildContext context, bool enabled) async {
    final ok = await ref
        .read(profileNotifierProvider.notifier)
        .updateNotification(enabled);
    ref.invalidate(reminderSettingsProvider);
    if (!ok && context.mounted) {
      _snack(
        context,
        'Notifications are disabled for Icos. Enable them in system '
        'settings to get reminders.',
      );
    }
  }

  Future<void> _pickReminderTime(
    BuildContext context,
    TimeOfDay current,
  ) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: current,
      helpText: 'Daily reminder time',
    );
    if (picked == null) return;
    await ref.read(profileNotifierProvider.notifier).updateReminderTime(picked);
  }

  void _showAboutDialog(BuildContext context, String? version) {
    showAboutDialog(
      context: context,
      applicationName: 'Icos',
      applicationVersion: version ?? '',
      applicationLegalese: 'Copyright 2026 Icos. All rights reserved.',
      children: const [ContactSupportTile()],
      applicationIcon: Container(
        width: 48,
        height: 48,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.purpleGradientStart,
              AppColors.purpleGradientEnd,
            ],
          ),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.route_rounded,
          size: 28,
          color: Colors.white,
        ),
      ),
    );
  }

  Future<void> _exportData(BuildContext context) async {
    // Captured before the awaits: the share sheet anchors to the tapped row.
    final origin = sharePositionOriginFor(context);
    setState(() => _busy = true);
    final result = await ref
        .read(profileNotifierProvider.notifier)
        .exportAndShareData(origin: origin);
    if (!mounted) return;
    setState(() => _busy = false);

    if (result case Failure(error: final error)) {
      if (context.mounted) _snack(context, error.userMessage);
    }
  }

  Future<void> _showDeleteAccountDialog(BuildContext context) async {
    final isGuest = SupabaseService.auth.currentUser?.isAnonymous ?? true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Account'),
        content: Text(AccountDeletionCopy.dialogBody(isGuest: isGuest)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: context.palette.error,
            ),
            child: const Text('Delete Account'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    final result =
        await ref.read(profileNotifierProvider.notifier).deleteAccount();
    if (!mounted) return;
    setState(() => _busy = false);

    switch (result) {
      case Success():
        _snack(this.context, AccountDeletionCopy.doneMessage(isGuest: isGuest));
        this.context.go('/');
      case Failure(error: final error):
        _snack(this.context, error.userMessage);
    }
  }

  Future<void> _signOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text(
          'You can sign back in any time to pick up where you left off.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    await ref.read(authNotifierProvider.notifier).signOut();
    if (!mounted) return;
    setState(() => _busy = false);
    this.context.go('/');
  }
}

/// Theme-aware rounded card used for the settings groups.
class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? context.palette.card : AppColors.lightSurface,
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        border: Border.all(
          color: isDark
              ? context.palette.border.withValues(alpha: 0.3)
              : AppColors.lightGridLine,
        ),
      ),
      child: child,
    );
  }
}
