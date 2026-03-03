import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/app_sizes.dart';
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

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  late bool _hapticEnabled;
  late bool _soundEnabled;
  late bool _notificationEnabled;
  late String _colorblindMode;
  bool _settingsInitialized = false;

  void _initSettingsFromProfile(UserProfile? profile) {
    if (_settingsInitialized) return;
    _hapticEnabled = profile?.hapticEnabled ?? StorageService.hapticEnabled;
    _soundEnabled = profile?.soundEnabled ?? StorageService.soundEnabled;
    _notificationEnabled = profile?.notificationEnabled ?? true;
    _colorblindMode = profile?.colorblindMode ?? StorageService.colorblindMode;
    _settingsInitialized = true;
  }

  void _initSettingsFromStorage() {
    if (_settingsInitialized) return;
    _hapticEnabled = StorageService.hapticEnabled;
    _soundEnabled = StorageService.soundEnabled;
    _notificationEnabled = true;
    _colorblindMode = StorageService.colorblindMode;
    _settingsInitialized = true;
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeNotifierProvider);
    final profileState = ref.watch(profileNotifierProvider);
    // Watch auth state to rebuild when auth changes
    ref.watch(authNotifierProvider);
    final user = SupabaseService.auth.currentUser;
    final isAnonymous = user?.isAnonymous ?? true;

    // Initialize local settings state from profile or storage
    profileState.whenData((profile) {
      _initSettingsFromProfile(profile);
    });
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

            // Avatar section
            _buildAvatarSection(context, profile, isAnonymous),
            const SizedBox(height: AppSizes.xl),

            // Account info section
            if (!isAnonymous) ...[
              _buildAccountSection(context, user, profile),
              const SizedBox(height: AppSizes.md),
            ],

            // Settings section
            Text(
              'Settings',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSizes.md),
            _buildSettingsCard(context, themeMode, profile),
            const SizedBox(height: AppSizes.md),

            // App section
            Text(
              'App',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSizes.md),
            _buildAppCard(context),
            const SizedBox(height: AppSizes.lg),

            // Sign out button
            if (!isAnonymous)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => _signOut(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.error,
                    ),
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

  Widget _buildAvatarSection(
    BuildContext context,
    UserProfile? profile,
    bool isAnonymous,
  ) {
    final displayName = profile?.displayName ?? 'Guest Player';
    final initials = _getInitials(displayName);

    return Center(
      child: Column(
        children: [
          CircleAvatar(
            radius: 40,
            backgroundColor: Theme.of(context).colorScheme.primary,
            backgroundImage: profile?.avatarUrl != null
                ? NetworkImage(profile!.avatarUrl!)
                : null,
            child: profile?.avatarUrl == null
                ? Text(
                    initials,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                : null,
          ),
          const SizedBox(height: AppSizes.sm),
          GestureDetector(
            onTap: isAnonymous ? null : () => _editDisplayName(context, displayName),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  displayName,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (!isAnonymous) ...[
                  const SizedBox(width: AppSizes.xs),
                  Icon(
                    Icons.edit_rounded,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ],
              ],
            ),
          ),
          if (isAnonymous) ...[
            const SizedBox(height: AppSizes.xs),
            OutlinedButton(
              onPressed: () => context.push('/auth'),
              child: const Text('Create Account'),
            ),
          ],
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
    final bool isAnonymous = user?.isAnonymous ?? true;
    final accountType = isAnonymous ? 'Guest' : 'Registered';
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
        Card(
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
                title: const Text('Account Type'),
                subtitle: Text(accountType),
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
    return Card(
      child: Column(
        children: [
          // Theme selector
          ListTile(
            leading: const Icon(Icons.palette_rounded),
            title: const Text('Theme'),
            trailing: DropdownButton<ThemeMode>(
              value: themeMode,
              underline: const SizedBox.shrink(),
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
                  value: ThemeMode.light,
                  child: Text('Light'),
                ),
                DropdownMenuItem(
                  value: ThemeMode.dark,
                  child: Text('Dark'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Haptic feedback
          SwitchListTile(
            secondary: const Icon(Icons.vibration_rounded),
            title: const Text('Haptic Feedback'),
            value: _hapticEnabled,
            onChanged: (value) {
              setState(() => _hapticEnabled = value);
              ref
                  .read(profileNotifierProvider.notifier)
                  .updateHaptic(value);
            },
          ),
          const Divider(height: 1),

          // Sound effects
          SwitchListTile(
            secondary: const Icon(Icons.volume_up_rounded),
            title: const Text('Sound Effects'),
            value: _soundEnabled,
            onChanged: (value) {
              setState(() => _soundEnabled = value);
              ref
                  .read(profileNotifierProvider.notifier)
                  .updateSound(value);
            },
          ),
          const Divider(height: 1),

          // Colorblind mode
          ListTile(
            leading: const Icon(Icons.accessibility_new_rounded),
            title: const Text('Colorblind Mode'),
            subtitle: Text(_colorblindModeLabel(_colorblindMode)),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _showColorblindSelector(context),
          ),
          const Divider(height: 1),

          // Notification toggle
          SwitchListTile(
            secondary: const Icon(Icons.notifications_rounded),
            title: const Text('Notifications'),
            value: _notificationEnabled,
            onChanged: (value) {
              setState(() => _notificationEnabled = value);
              ref
                  .read(profileNotifierProvider.notifier)
                  .updateNotification(value);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAppCard(BuildContext context) {
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.info_outline_rounded),
            title: const Text('About'),
            subtitle: const Text('Version 1.0.0 (1)'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _showAboutDialog(context),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Privacy Policy'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              // TODO: Open privacy policy URL
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('Terms of Service'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              // TODO: Open terms of service URL
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(
              Icons.delete_forever_rounded,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(
              'Delete Account',
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
            trailing: Icon(
              Icons.chevron_right_rounded,
              color: Theme.of(context).colorScheme.error,
            ),
            onTap: () => _showDeleteAccountDialog(context),
          ),
        ],
      ),
    );
  }

  String _getInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  String _colorblindModeLabel(String mode) {
    return switch (mode) {
      'deuteranopia' => 'Deuteranopia',
      'protanopia' => 'Protanopia',
      'tritanopia' => 'Tritanopia',
      _ => 'None',
    };
  }

  Future<void> _editDisplayName(
    BuildContext context,
    String currentName,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => EditNameDialog(currentName: currentName),
    );

    if (result == true) {
      // Profile was updated by the dialog, refresh UI
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
      // Refresh local state after bottom sheet closes
      final profile = ref.read(profileNotifierProvider).valueOrNull;
      if (profile != null) {
        setState(() {
          _colorblindMode = profile.colorblindMode;
        });
      }
    });
  }

  void _showAboutDialog(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'Icos',
      applicationVersion: '1.0.0',
      applicationLegalese: 'Copyright 2024 Icos. All rights reserved.',
      applicationIcon: Icon(
        Icons.route_rounded,
        size: 48,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
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
          'You can sign back in within this period to cancel the deletion.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete Account'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final result = await ref
        .read(profileNotifierProvider.notifier)
        .deleteAccount();

    if (!mounted) return;

    switch (result) {
      case Success():
        await ref.read(authNotifierProvider.notifier).signOut();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Account scheduled for deletion. '
                'Sign in within 30 days to cancel.',
              ),
            ),
          );
          context.go('/auth');
        }
      case Failure(error: final error):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.userMessage)),
        );
    }
  }

  Future<void> _signOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
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

    await ref.read(authNotifierProvider.notifier).signOut();
    if (mounted) {
      context.go('/auth');
    }
  }
}
