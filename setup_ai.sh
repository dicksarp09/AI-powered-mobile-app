#!/bin/bash
# setup_ai.sh - Setup and test real AI integration

echo "🤖 AI Setup Script"
echo "=================="
echo ""

# Check if we're in the right directory
if [ ! -f "pubspec.yaml" ]; then
    echo "❌ Error: Not in project root directory"
    echo "Please run this script from: C:\Users\USER\Desktop\Workspace\AI-powered app"
    exit 1
fi

echo "✅ Found project root"

# Check if .env exists
if [ ! -f ".env" ]; then
    echo ""
    echo "❌ .env file not found!"
    echo ""
    echo "Creating .env file..."
    echo "GOOGLE_API_KEY=your_api_key_here" > .env
    echo ""
    echo "✅ Created .env file"
    echo ""
    echo "📝 NEXT STEPS:"
    echo "1. Get your API key from: https://makersuite.google.com/app/apikey"
    echo "2. Edit .env file and replace 'your_api_key_here' with your real key"
    echo "3. Run this script again"
    echo ""
    exit 1
fi

echo "✅ Found .env file"

# Check if API key is set
if grep -q "your_api_key_here\|YOUR_API_KEY\|=$" .env; then
    echo ""
    echo "❌ API key not configured!"
    echo ""
    echo "Please edit .env file and add your real API key:"
    echo "  GOOGLE_API_KEY=AIzaSy..."
    echo ""
    echo "Get your key from: https://makersuite.google.com/app/apikey"
    exit 1
fi

echo "✅ API key configured"
echo ""

# Test the AI service
echo "🧪 Testing AI service..."
echo ""

if command -v dart &> /dev/null; then
    dart test_real_ai.dart
elif command -v flutter &> /dev/null; then
    flutter dart test_real_ai.dart
else
    echo "❌ Dart/Flutter not found"
    exit 1
fi
