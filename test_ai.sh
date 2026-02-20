#!/bin/bash
# test_ai.sh - Run AI tests in terminal

echo "🤖 AI Model Tester"
echo "=================="
echo ""

# Check if dart is available
if command -v dart &> /dev/null; then
    echo "✅ Dart found"
    echo ""
    
    # Run the test script
    dart test_ai.dart
    
elif command -v flutter &> /dev/null; then
    echo "✅ Flutter found (using Flutter's Dart)"
    echo ""
    
    # Run with Flutter's dart
    flutter dart test_ai.dart
    
else
    echo "❌ Neither Dart nor Flutter found in PATH"
    echo ""
    echo "Please install Flutter:"
    echo "  https://flutter.dev/docs/get-started/install"
    echo ""
    echo "Or run the Flutter tests instead:"
    echo "  flutter test"
    exit 1
fi
