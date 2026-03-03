#!/bin/bash
# Icos Development Environment Setup
# Run this script after installing Flutter SDK

set -e

echo "=== Icos Development Setup ==="

# Check Flutter
if ! command -v flutter &> /dev/null; then
    echo "ERROR: Flutter is not installed or not in PATH"
    echo "Install Flutter: https://docs.flutter.dev/get-started/install"
    echo "Or via Homebrew: brew install --cask flutter"
    exit 1
fi

echo "Flutter version:"
flutter --version

# Create Flutter project if pubspec.yaml doesn't exist
if [ ! -f "pubspec.yaml" ]; then
    echo ""
    echo "=== Creating Flutter Project ==="
    flutter create --org com.icos --project-name icos --platforms ios,android .
    echo "Flutter project created."
fi

# Install dependencies
echo ""
echo "=== Installing Dependencies ==="
flutter pub get

# Run code generation (if build_runner is configured)
if grep -q "build_runner" pubspec.yaml 2>/dev/null; then
    echo ""
    echo "=== Running Code Generation ==="
    dart run build_runner build --delete-conflicting-outputs
fi

# Verify setup
echo ""
echo "=== Verifying Setup ==="
flutter analyze --no-fatal-infos || true

echo ""
echo "=== Setup Complete ==="
echo "Next steps:"
echo "  1. Copy .env.example to .env.development and add your Supabase keys"
echo "  2. Run 'supabase start' for local development"
echo "  3. Run 'flutter run' to launch the app"
echo "  4. Use '/bmad-bmm-create-story' to create your first story"
echo "  5. Use '/bmad-bmm-dev-story' to implement it"
