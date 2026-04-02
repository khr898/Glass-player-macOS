#!/bin/bash
#
# install-mpv-no-vapoursynth.sh
#
# Replaces stock Homebrew mpv with a custom build that excludes vapoursynth.
# This removes the Python 3.14 dependency for Glass Player users.
#
# Usage:
#   ./install-mpv-no-vapoursynth.sh
#
# What this does:
#   1. Uninstalls stock mpv
#   2. Installs mpv from the custom formula (mpv-no-vapoursynth.rb)
#   3. Verifies the installation has no vapoursynth dependency
#
# To revert to stock mpv:
#   brew uninstall mpv
#   brew install mpv
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FORMULA_FILE="$SCRIPT_DIR/mpv-no-vapoursynth.rb"

echo "=== Installing mpv without vapoursynth ==="
echo ""

# Check if formula exists
if [ ! -f "$FORMULA_FILE" ]; then
    echo "ERROR: Formula not found: $FORMULA_FILE"
    echo "Make sure you're running this from the Homebrew directory."
    exit 1
fi

# Uninstall stock mpv if present
if brew list mpv &>/dev/null; then
    echo "Uninstalling stock mpv..."
    brew uninstall mpv --ignore-dependencies
fi

# Uninstall custom formula if present (for reinstall)
if brew list mpv-no-vapoursynth &>/dev/null; then
    echo "Removing existing custom mpv..."
    brew uninstall mpv-no-vapoursynth --ignore-dependencies
fi

# Install custom formula
echo "Installing mpv without vapoursynth..."
brew install "$FORMULA_FILE"

# Verify installation
echo ""
echo "=== Verifying installation ==="

if otool -L /opt/homebrew/lib/libmpv*.dylib 2>/dev/null | grep -q vapoursynth; then
    echo "WARNING: vapoursynth dependency still detected!"
    echo "This may indicate the build did not complete correctly."
    exit 1
else
    echo "SUCCESS: mpv installed without vapoursynth dependency"
fi

echo ""
echo "=== Installation complete ==="
echo ""
echo "You can now build Glass Player:"
echo "  cd ../GlassPlayer"
echo "  bash build.sh"
echo ""
echo "To verify mpv is working:"
echo "  mpv --version"
echo ""
