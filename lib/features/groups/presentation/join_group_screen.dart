import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/utils/app_error.dart';
import '../../../core/utils/result.dart';
import '../domain/invite_code.dart';
import '../providers/groups_provider.dart';
import 'widgets/account_required_card.dart';
import 'widgets/group_ui.dart';

/// Deep-link target for `/join/:code` (and `https://icos.sarathfrancis.work/join/CODE`).
///
/// Anonymous users see the account gate; signed-in users are joined
/// automatically and forwarded to the group.
class JoinGroupScreen extends ConsumerStatefulWidget {
  const JoinGroupScreen({required this.inviteCode, super.key});

  final String inviteCode;

  @override
  ConsumerState<JoinGroupScreen> createState() => _JoinGroupScreenState();
}

enum _JoinPhase { idle, joining, joined, failed }

class _JoinGroupScreenState extends ConsumerState<JoinGroupScreen> {
  _JoinPhase _phase = _JoinPhase.idle;
  String? _errorMessage;
  bool _attempted = false;

  String get _code => InviteCode.normalize(widget.inviteCode);

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(groupsSessionProvider);

    // Auto-join once the user has an account (also fires when they return
    // from /auth after upgrading a guest session).
    if (session.canUseGroups && !_attempted) {
      _attempted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _join());
    }

    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.joinGroup)),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsetsDirectional.all(AppSizes.lg),
            child: !session.canUseGroups
                ? AccountRequiredCard(
                    message: 'You were invited to a group with code $_code. '
                        'Create a free account to join it — your streak and '
                        'stats come with you.',
                  )
                : switch (_phase) {
                    _JoinPhase.idle || _JoinPhase.joining => _Status(
                        icon: const SizedBox(
                          width: 48,
                          height: 48,
                          child: CircularProgressIndicator(),
                        ),
                        title: 'Joining group…',
                        subtitle: 'Invite code $_code',
                      ),
                    _JoinPhase.joined => const _Status(
                        icon: Icon(
                          Icons.check_circle_rounded,
                          size: 64,
                          color: AppColors.success,
                        ),
                        title: 'You\'re in!',
                        subtitle: 'Taking you to the group…',
                      ),
                    _JoinPhase.failed => _Status(
                        icon: Icon(
                          Icons.error_outline_rounded,
                          size: 64,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        title: 'Could not join group',
                        subtitle: _errorMessage ?? AppStrings.errorGeneric,
                        actions: [
                          FilledButton(
                            key: const Key('join_retry'),
                            onPressed: () {
                              setState(() => _phase = _JoinPhase.idle);
                              _join();
                            },
                            child: const Text('Try again'),
                          ),
                          const SizedBox(height: AppSizes.sm),
                          OutlinedButton(
                            onPressed: () => context.go('/groups'),
                            child: const Text('Go to Groups'),
                          ),
                        ],
                      ),
                  },
          ),
        ),
      ),
    );
  }

  Future<void> _join() async {
    if (_phase == _JoinPhase.joining) return;
    setState(() {
      _phase = _JoinPhase.joining;
      _errorMessage = null;
    });

    final result = await ref.read(myGroupsProvider.notifier).joinGroup(_code);
    if (!mounted) return;

    switch (result) {
      case Success(data: final group):
        setState(() => _phase = _JoinPhase.joined);
        await Future<void>.delayed(const Duration(milliseconds: 600));
        if (mounted) context.go('/groups/${group.id}');
      case Failure(error: final error):
        setState(() {
          _phase = _JoinPhase.failed;
          _errorMessage = error.userMessage;
        });
    }
  }
}

class _Status extends StatelessWidget {
  const _Status({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actions = const [],
  });

  final Widget icon;
  final String title;
  final String subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          const SizedBox(height: AppSizes.md),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: AppSizes.sm),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: secondaryTextColor(context),
            ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: AppSizes.lg),
            ...actions,
          ],
        ],
      ),
    );
  }
}
