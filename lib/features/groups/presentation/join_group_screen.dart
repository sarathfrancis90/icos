import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../providers/groups_provider.dart';

class JoinGroupScreen extends ConsumerStatefulWidget {
  const JoinGroupScreen({required this.inviteCode, super.key});

  final String inviteCode;

  @override
  ConsumerState<JoinGroupScreen> createState() => _JoinGroupScreenState();
}

class _JoinGroupScreenState extends ConsumerState<JoinGroupScreen> {
  bool _isJoining = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _joinGroup();
  }

  Future<void> _joinGroup() async {
    final group = await ref
        .read(myGroupsProvider.notifier)
        .joinGroup(widget.inviteCode);

    if (!mounted) return;

    if (group != null) {
      setState(() {
        _isJoining = false;
      });
      // Navigate to the group detail screen after a brief delay
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) {
          context.go('/groups/${group.id}');
        }
      });
    } else {
      setState(() {
        _isJoining = false;
        _errorMessage = 'Could not join group. The invite code may be invalid or the group may be full.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Join Group'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsetsDirectional.all(AppSizes.lg),
          child: _isJoining
              ? const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: AppSizes.lg),
                    Text('Joining group...'),
                  ],
                )
              : _errorMessage != null
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          size: 64,
                          color: AppColors.coralOrange,
                        ),
                        const SizedBox(height: AppSizes.md),
                        Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                        const SizedBox(height: AppSizes.lg),
                        ElevatedButton(
                          onPressed: () => context.go('/groups'),
                          child: const Text('Go to Groups'),
                        ),
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.check_circle_rounded,
                          size: 64,
                          color: AppColors.success,
                        ),
                        const SizedBox(height: AppSizes.md),
                        Text(
                          'Successfully joined group!',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: AppSizes.md),
                        const Text('Redirecting...'),
                      ],
                    ),
        ),
      ),
    );
  }
}
