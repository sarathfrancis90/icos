import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/services/app_config_provider.dart';
import '../../../core/services/app_logger.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../core/utils/app_error.dart';
import '../../../core/utils/result.dart';
import '../../auth/providers/auth_provider.dart';
import '../domain/models/profile.dart';
import '../providers/profile_provider.dart';
import 'widgets/colorblind_selector.dart';
import 'widgets/edit_name_dialog.dart';

const String kPrivacyPolicyUrl = 'https://icos.sarathfrancis.work/privacy-policy.html';
const String kTermsUrl = 'https://icos.sarathfrancis.work/terms.html';

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
    final themeMode = ref.watch(themeModeNotifierProvider);
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
              _buildGuestCard(context),
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
            _buildSettingsCard(context, themeMode, profile),
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
                    foregroundColor: AppColors.error,
                    side: const BorderSide(color: AppColors.error),
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
                    const Icon(
                      Icons.edit_rounded,
                      size: 18,
                      color: AppColors.purpleLight,
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

  Widget _buildGuestCard(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.all(AppSizes.md),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.purpleGradientStart.withValues(alpha: 0.25),
            AppColors.purpleGradientEnd.withValues(alpha: 0.15),
          ],
        ),
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        border: Border.all(
          color: AppColors.purpleLight.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person_outline_rounded,
                  color: AppColors.purpleLight),
              const SizedBox(width: AppSizes.sm),
              Text(
                'Guest account',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: AppSizes.sm),
          Text(
            'Create an account to keep your progress across devices, join '
            'groups and never lose your streak. Guest data is removed after '
            '${AppSizes.anonymousPurgeDays} days of inactivity.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight,
                  height: 1.4,
                ),
          ),
          const SizedBox(height: AppSizes.md),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => context.push('/auth'),
              child: const Text('Create account'),
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
    ThemeMode themeMode,
    UserProfile? profile,
  ) {
    final reminder = ref.watch(reminderSettingsProvider).valueOrNull;
    final reminderEnabled = reminder?.enabled ?? false;
    final reminderTime = reminder?.time ?? const TimeOfDay(hour: 9, minute: 0);

    return _Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.palette_rounded),
            title: const Text('Theme'),
            trailing: DropdownButton<ThemeMode>(
              value: themeMode,
              underline: const SizedBox.shrink(),
              dropdownColor: AppColors.elevatedSurface,
              onChanged: (mode) {
                if (mode != null) {
                  ref
                      .read(themeModeNotifierProvider.notifier)
                      .setThemeMode(mode);
                }
              },
              items: const [
                DropdownMenuItem(
                  value: ThemeMode.system,
                  child: Text('System'),
                ),
                DropdownMenuItem(
                  value: ThemeMode.dark,
                  child: Text('Dark'),
                ),
                DropdownMenuItem(
                  value: ThemeMode.light,
                  child: Text('Light'),
                ),
              ],
            ),
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
            trailing: const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textTertiaryDark,
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
              trailing: const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textTertiaryDark,
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
            trailing: const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textTertiaryDark,
            ),
            onTap: () => _showAboutDialog(context, version),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Privacy Policy'),
            trailing: const Icon(
              Icons.open_in_new_rounded,
              color: AppColors.textTertiaryDark,
            ),
            onTap: () => _openUrl(context, kPrivacyPolicyUrl),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('Terms of Service'),
            trailing: const Icon(
              Icons.open_in_new_rounded,
              color: AppColors.textTertiaryDark,
            ),
            onTap: () => _openUrl(context, kTermsUrl),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.download_rounded),
            title: const Text('Export my data'),
            subtitle: const Text('Download a JSON copy of your data'),
            trailing: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.textTertiaryDark,
                  ),
            onTap: _busy ? null : () => _exportData(context),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(
              Icons.delete_forever_rounded,
              color: AppColors.error,
            ),
            title: const Text(
              'Delete Account',
              style: TextStyle(color: AppColors.error),
            ),
            subtitle: isAnonymous
                ? const Text('Removes this guest profile and its progress')
                : null,
            trailing: const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.error,
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
    final uri = Uri.parse(url);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) {
        _snack(context, 'Could not open $url');
      }
    } catch (e) {
      AppLogger.warn('launchUrl failed', error: e, data: {'url': url});
      if (context.mounted) _snack(context, 'Could not open $url');
    }
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
    setState(() => _busy = true);
    final result =
        await ref.read(profileNotifierProvider.notifier).exportData();
    if (!mounted) return;
    setState(() => _busy = false);

    switch (result) {
      case Success(data: final file):
        try {
          await Share.shareXFiles(
            [XFile(file.path, mimeType: 'application/json')],
            subject: 'My Icos data',
            text: 'Your Icos data export',
          );
        } catch (e) {
          AppLogger.warn('Share export failed', error: e);
          if (context.mounted) {
            _snack(context, 'Export saved to ${file.path}');
          }
        }
      case Failure(error: final error):
        if (context.mounted) _snack(context, error.userMessage);
    }
  }

  Future<void> _showDeleteAccountDialog(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Account'),
        content: const Text(
          'Are you sure you want to delete your account? '
          'Your account will be scheduled for deletion and permanently '
          'removed after ${AppSizes.accountDeletionGraceDays} days. '
          'Sign back in within this period to cancel the deletion.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
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
        _snack(
          this.context,
          'Account scheduled for deletion. '
          'Sign in within ${AppSizes.accountDeletionGraceDays} days to cancel.',
        );
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
        color: isDark ? AppColors.cardSurface : AppColors.lightSurface,
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        border: Border.all(
          color: isDark
              ? AppColors.cellBorder.withValues(alpha: 0.3)
              : AppColors.lightGridLine,
        ),
      ),
      child: child,
    );
  }
}
