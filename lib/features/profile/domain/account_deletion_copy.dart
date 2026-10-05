import '../../../core/constants/app_sizes.dart';
import '../../../core/utils/app_error.dart';

/// Wording for the delete-account flow. A guest has no login to come back
/// with, so the "sign back in to cancel" promise only applies to members.
abstract final class AccountDeletionCopy {
  static String dialogBody({required bool isGuest}) => isGuest
      ? 'Are you sure you want to delete this guest profile? Your progress '
            'and streak will be removed and cannot be recovered. To keep them, '
            'create an account first.'
      : 'Are you sure you want to delete your account? '
            'Your account will be scheduled for deletion and permanently '
            'removed after ${AppSizes.accountDeletionGraceDays} days. '
            'Sign back in within this period to cancel the deletion.';

  static String doneMessage({required bool isGuest}) => isGuest
      ? 'Guest profile deleted.'
      : 'Account scheduled for deletion. '
            'Sign in within ${AppSizes.accountDeletionGraceDays} days to cancel.';

  static const offlineCancelFailed =
      "You're offline. Try again when you're connected.";
  static const cancelFailed = 'Could not cancel the deletion. Please try again.';

  /// Message for a failed "Cancel deletion" request.
  static String cancelFailureMessage(AppError error) =>
      error is NetworkError ? offlineCancelFailed : cancelFailed;

  static const pendingBanner = 'This account is scheduled for deletion.';
  static const cancelDeletion = 'Cancel deletion';
  static const deletionCancelled = 'Deletion cancelled.';
}
