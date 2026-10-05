import '../../../core/constants/app_strings.dart';

/// Minimum password length, shared by sign-up and password reset.
const int kMinPasswordLength = 6;

/// Validation for a new password (sign-up and "set a new password").
String? validateNewPassword(String? value) {
  if (value == null || value.isEmpty) return AppStrings.passwordRequired;
  if (value.length < kMinPasswordLength) return AppStrings.passwordTooShort;
  return null;
}

/// Validation for the confirmation field.
String? validatePasswordConfirmation(String? value, String password) =>
    value == password ? null : AppStrings.passwordsDoNotMatch;
