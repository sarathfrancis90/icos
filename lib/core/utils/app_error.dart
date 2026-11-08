import 'package:freezed_annotation/freezed_annotation.dart';

import '../constants/app_strings.dart';

part 'app_error.freezed.dart';

@freezed
sealed class AppError with _$AppError {
  const factory AppError.network(String message) = NetworkError;
  const factory AppError.database(String message) = DatabaseError;
  const factory AppError.auth(String message) = AuthError;
  const factory AppError.validation(String message) = ValidationError;
  const factory AppError.notFound(String message) = NotFoundError;
  const factory AppError.rateLimit(String message) = RateLimitError;

  /// The email / provider identity already belongs to another account.
  const factory AppError.conflict(String message) = ConflictError;

  /// The user dismissed a sign-in sheet or browser flow.
  const factory AppError.cancelled() = CancelledError;
  const factory AppError.unknown(String message) = UnknownError;
}

extension AppErrorX on AppError {
  String get userMessage => switch (this) {
        NetworkError() => 'No internet connection. Please try again.',
        DatabaseError() => 'Something went wrong. Please try again.',
        AuthError(:final message) => message,
        ValidationError(:final message) => message,
        NotFoundError(:final message) => message,
        RateLimitError() => 'Too many requests. Please wait a moment.',
        ConflictError(:final message) => message,
        CancelledError() => AppStrings.backendSignInCancelled,
        UnknownError() => 'Something went wrong. Please try again.',
      };
}
