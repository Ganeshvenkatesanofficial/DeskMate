#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
TARGET_APP="/Applications/DeskMate.app"

echo "Installing DeskMate to /Applications..."

# Test if /Applications is directly writable
CAN_WRITE=0
if touch /Applications/.test_dm_write 2>/dev/null; then
  rm -f /Applications/.test_dm_write
  CAN_WRITE=1
fi

INSTALLED=0
if [ "$CAN_WRITE" -eq 1 ]; then
  rm -rf "$TARGET_APP"
  cp -R "$DIR/DeskMate.app" /Applications/
  INSTALLED=1
else
  if command -v osascript >/dev/null 2>&1; then
    if osascript -e "do shell script \"rm -rf /Applications/DeskMate.app && cp -R '$DIR/DeskMate.app' /Applications/ && chmod -R u+rwX,go+rX /Applications/DeskMate.app\" with prompt \"DeskMate needs administrator privileges to copy to your Applications folder:\" with administrator privileges" 2>/dev/null; then
      INSTALLED=1
    fi
  fi
fi

if [ "$INSTALLED" -ne 1 ] || [ ! -d "$TARGET_APP" ]; then
  echo "Notice: Installing to ~/Applications..."
  mkdir -p "$HOME/Applications"
  TARGET_APP="$HOME/Applications/DeskMate.app"
  rm -rf "$TARGET_APP"
  cp -R "$DIR/DeskMate.app" "$HOME/Applications/"
fi

xattr -cr "$TARGET_APP" 2>/dev/null || true
chmod +x "$TARGET_APP/Contents/MacOS/DeskMate" 2>/dev/null || true
find "$TARGET_APP/Contents" -type f -name "deskmate_backend" -exec chmod +x {} + 2>/dev/null || true
find "$TARGET_APP/Contents" -type f -name "macos_audio_capture" -exec chmod +x {} + 2>/dev/null || true
codesign --force --deep --sign - "$TARGET_APP" 2>/dev/null || true

killall Finder 2>/dev/null || true
echo "Launching DeskMate..."
open "$TARGET_APP"
exit 0
