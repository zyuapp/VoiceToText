#!/bin/bash

set -e

echo "======================================"
echo "Whisper.cpp Setup Script"
echo "======================================"
echo ""

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WHISPER_DIR="$PROJECT_ROOT/whisper.cpp"

if [ -d "$WHISPER_DIR" ]; then
    echo "✓ whisper.cpp directory already exists"
    read -p "Do you want to rebuild? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Skipping rebuild. Exiting."
        exit 0
    fi
    echo "Cleaning existing build..."
    cd "$WHISPER_DIR"
    rm -rf build
else
    echo "→ Cloning whisper.cpp..."
    git clone https://github.com/ggerganov/whisper.cpp.git "$WHISPER_DIR"
    cd "$WHISPER_DIR"
fi

echo ""
echo "→ Configuring whisper.cpp with Metal backend (static libraries)..."
echo "  (This may take a few minutes)"
echo ""

cmake -B build \
  -DGGML_METAL=ON \
  -DWHISPER_METAL=ON \
  -DBUILD_SHARED_LIBS=OFF \
  -DCMAKE_BUILD_TYPE=Release \
  -DGGML_METAL_EMBED_LIBRARY=ON

echo ""
echo "→ Building whisper.cpp..."
echo ""

cmake --build build -j --config Release

if [ $? -eq 0 ]; then
    echo ""
    echo "======================================"
    echo "✓ Build successful!"
    echo "======================================"
    echo ""
    echo "Static library locations:"
    echo "  - whisper-cli: $WHISPER_DIR/build/bin/whisper-cli"
    echo "  - libwhisper.a: $WHISPER_DIR/build/src/libwhisper.a"
    echo "  - libggml.a: $WHISPER_DIR/build/ggml/src/libggml.a"
    echo ""

    if [ -f "$WHISPER_DIR/build/bin/whisper-cli" ]; then
        echo "✓ Verified: whisper-cli binary exists"
    else
        echo "⚠ Warning: whisper-cli binary not found"
    fi

    if [ -f "$WHISPER_DIR/build/src/libwhisper.a" ]; then
        echo "✓ Verified: libwhisper.a exists"
    else
        echo "⚠ Warning: libwhisper.a not found"
    fi

    if [ -f "$WHISPER_DIR/build/ggml/src/libggml.a" ]; then
        echo "✓ Verified: libggml.a static library exists"
    else
        echo "⚠ Warning: libggml.a not found"
    fi

    echo ""
    echo "======================================"
    echo "✓ Build Complete!"
    echo "======================================"
    echo ""

    if [ -f "$PROJECT_ROOT/configure-xcode.sh" ]; then
        echo "→ Configuring Xcode project..."
        echo ""
        "$PROJECT_ROOT/configure-xcode.sh"
        echo ""
    fi

    echo "Next steps:"
    echo ""
    echo "  1. Download Whisper model (happens automatically on first run)"
    echo ""
    echo "  2. Build and run the app in Xcode (Cmd+R)"
    echo ""
else
    echo ""
    echo "======================================"
    echo "✗ Build failed"
    echo "======================================"
    echo ""
    echo "Please check the error messages above."
    exit 1
fi
