#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
if [ -w "/Applications" ]; then
  TARGET="/Applications"
else
  if xattr -l "$HOME/Applications" 2>/dev/null | grep -q "com.apple.provenance"; then
    TARGET="$HOME"
  else
    TARGET="$HOME/Applications"
    mkdir -p "$TARGET"
  fi
fi
echo "Installing DeskMate to $TARGET..."
rm -rf "$TARGET/DeskMate.app"
cp -R "$DIR/DeskMate.app" "$TARGET/"
xattr -cr "$TARGET/DeskMate.app" 2>/dev/null || true
chmod +x "$TARGET/DeskMate.app/Contents/MacOS/DeskMate" 2>/dev/null || true
codesign --force --deep --sign - "$TARGET/DeskMate.app" 2>/dev/null || true
echo "Launching DeskMate..."
open "$TARGET/DeskMate.app"
exit 0
