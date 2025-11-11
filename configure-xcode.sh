#!/bin/bash

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PBXPROJ="$PROJECT_ROOT/VoiceToText.xcodeproj/project.pbxproj"
XCCONFIG_FILE="Whisper.xcconfig"

echo "======================================"
echo "Xcode Project Configuration"
echo "======================================"
echo ""

if [ ! -f "$PBXPROJ" ]; then
    echo "Error: project.pbxproj not found at $PBXPROJ"
    exit 1
fi

if [ ! -f "$PROJECT_ROOT/$XCCONFIG_FILE" ]; then
    echo "Error: $XCCONFIG_FILE not found"
    exit 1
fi

echo "→ Backing up project.pbxproj..."
cp "$PBXPROJ" "$PBXPROJ.backup"

XCCONFIG_UUID="BC000001000000000065341A"

if ! grep -q "$XCCONFIG_FILE" "$PBXPROJ"; then
    echo "→ Adding Whisper.xcconfig file reference..."

    awk -v uuid="$XCCONFIG_UUID" -v filename="$XCCONFIG_FILE" '
    /^\/\* Begin PBXFileReference section \*\/$/ {
        print
        print "\t\t" uuid " /* " filename " */ = {isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = " filename "; sourceTree = \"<group>\"; };"
        next
    }
    { print }
    ' "$PBXPROJ" > "$PBXPROJ.tmp" && mv "$PBXPROJ.tmp" "$PBXPROJ"

    echo "✓ Added file reference"
else
    echo "✓ Whisper.xcconfig file reference already exists"
    XCCONFIG_UUID=$(grep "$XCCONFIG_FILE" "$PBXPROJ" | grep -o '^[[:space:]]*[A-F0-9]*' | tr -d '[:space:]')
fi

echo "→ Configuring Debug and Release to use Whisper.xcconfig..."

awk -v uuid="$XCCONFIG_UUID" '
/^[[:space:]]*BCFDA9A82EC2EDED0065341A \/\* Debug \*\/ = \{$/ {
    print
    getline
    print
    if ($0 !~ /baseConfigurationReference/) {
        print "\t\t\tbaseConfigurationReference = " uuid " /* Whisper.xcconfig */;"
    }
    next
}
/^[[:space:]]*BCFDA9A92EC2EDED0065341A \/\* Release \*\/ = \{$/ {
    print
    getline
    print
    if ($0 !~ /baseConfigurationReference/) {
        print "\t\t\tbaseConfigurationReference = " uuid " /* Whisper.xcconfig */;"
    }
    next
}
/baseConfigurationReference/ && /Whisper\.xcconfig/ {
    next
}
{ print }
' "$PBXPROJ" > "$PBXPROJ.tmp" && mv "$PBXPROJ.tmp" "$PBXPROJ"

if grep -q "baseConfigurationReference.*Whisper.xcconfig" "$PBXPROJ"; then
    echo "✓ Successfully configured Whisper.xcconfig for Debug and Release"
    echo ""
    echo "======================================"
    echo "✓ Configuration Complete!"
    echo "======================================"
    echo ""
    echo "Whisper.xcconfig is now active for both Debug and Release builds."
    echo "You can delete the backup: $PBXPROJ.backup"
    echo ""
else
    echo "⚠ Warning: Configuration may have failed"
    echo "Restoring backup..."
    mv "$PBXPROJ.backup" "$PBXPROJ"
    exit 1
fi
