#!/usr/bin/env bash
# ==============================================================================
# DeskMate macOS 1-Line Installer (Open-Source Edition)
# Bypasses macOS Gatekeeper quarantine without requiring sudo or root access.
# ==============================================================================

set -e

# Terminal colors
BOLD='\033[1m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}${BOLD}"
cat << "EOF"
  ____            _    __  __       _       
 |  _ \  ___  ___| | _|  \/  | __ _| |_ ___ 
 | | | |/ _ \/ __| |/ / |\/| |/ _` | __/ _ \
 | |_| |  __/\__ \   <| |  | | (_| | ||  __/
 |____/ \___||___/_|\_\_|  |_|\__,_|\__\___|
EOF
echo -e "${NC}"
echo -e "${BOLD}DeskMate macOS Auto-Installer${NC}"
echo "--------------------------------------------------------"

# 1. Verify macOS
OS="$(uname -s)"
if [ "$OS" != "Darwin" ]; then
  echo -e "${RED}Error: DeskMate auto-installer is only supported on macOS.${NC}"
  exit 1
fi

ARCH="$(uname -m)"
echo -e "Detected Architecture: ${BOLD}${ARCH}${NC}"

# 2. Determine Installation Target Directory
if [ -w "/Applications" ]; then
  APP_DIR="/Applications"
  TARGET_APP="$APP_DIR/DeskMate.app"
else
  # On macOS Sequoia, ~/Applications can inherit com.apple.provenance which blocks dyld.
  # If provenance exists on ~/Applications, install directly to $HOME/DeskMate.app.
  if xattr -l "$HOME/Applications" 2>/dev/null | grep -q "com.apple.provenance"; then
    APP_DIR="$HOME"
    TARGET_APP="$HOME/DeskMate.app"
  else
    APP_DIR="$HOME/Applications"
    mkdir -p "$APP_DIR"
    TARGET_APP="$APP_DIR/DeskMate.app"
  fi
fi

echo -e "Installation Destination: ${BOLD}${TARGET_APP}${NC}"

# 3. Terminate any currently running DeskMate instances
killall -9 DeskMate 2>/dev/null || true

# 4. Check for existing local build or download from GitHub
REPO="Ganeshvenkatesanofficial/DeskMate"
DOWNLOAD_URL="https://github.com/${REPO}/releases/latest/download/DeskMate-macOS.zip"

TMP_DIR="$(mktemp -d /tmp/deskmate_install_XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" 2>/dev/null && pwd || pwd )"

LOCAL_APP_CANDIDATE=""
for CANDIDATE in \
  "${SCRIPT_DIR}/../../deskmate_app/build/macos/Build/Products/Release/DeskMate.app" \
  "$PWD/deskmate_app/build/macos/Build/Products/Release/DeskMate.app" \
  "$HOME/DeskMate/deskmate_app/build/macos/Build/Products/Release/DeskMate.app" \
  "${SCRIPT_DIR}/../../deskmate_app/build/macos/Build/Products/Debug/DeskMate.app" \
  "$PWD/deskmate_app/build/macos/Build/Products/Debug/DeskMate.app" \
  "$HOME/DeskMate/deskmate_app/build/macos/Build/Products/Debug/DeskMate.app"; do
  if [ -d "$CANDIDATE" ]; then
    LOCAL_APP_CANDIDATE="$CANDIDATE"
    break
  fi
done

if [ -n "$LOCAL_APP_CANDIDATE" ]; then
  echo -e "${YELLOW}Found local build in repository: ${LOCAL_APP_CANDIDATE}${NC}"
  echo "Installing from local build..."
  rm -rf "$TARGET_APP"
  cp -R "$LOCAL_APP_CANDIDATE" "$APP_DIR/"
else
  echo -e "Checking for latest release package from GitHub..."
  DOWNLOADED_FILE=""

  # URLs to check in order of preference (DMG first, then ZIP)
  RELEASE_URLS=(
    "https://github.com/${REPO}/releases/download/continuous/DeskMate-macOS.dmg"
    "https://github.com/${REPO}/releases/download/continuous/DeskMate-macOS.zip"
    "https://github.com/${REPO}/releases/latest/download/DeskMate-macOS.dmg"
    "https://github.com/${REPO}/releases/latest/download/DeskMate-macOS.zip"
    "https://github.com/${REPO}/releases/download/v1.0.0/DeskMate-macOS.dmg"
    "https://github.com/${REPO}/releases/download/v1.0.0/DeskMate-macOS.zip"
  )

  for URL in "${RELEASE_URLS[@]}"; do
    echo "Attempting download from: $URL ..."
    FILENAME="$(basename "$URL")"
    TARGET_FILE_PATH="$TMP_DIR/$FILENAME"
    if curl -fsSL -o "$TARGET_FILE_PATH" "$URL" 2>/dev/null && [ -s "$TARGET_FILE_PATH" ]; then
      echo -e "${GREEN}Successfully downloaded $FILENAME from release.${NC}"
      DOWNLOADED_FILE="$TARGET_FILE_PATH"
      break
    fi
    rm -f "$TARGET_FILE_PATH"
  done

  # Fallback to local Downloads directory if online release is not yet drafted/published
  if [ -z "$DOWNLOADED_FILE" ]; then
    echo -e "${YELLOW}Notice: Online release archive not published or accessible yet.${NC}"
    echo "Searching ~/Downloads for downloaded GitHub Actions artifacts or DMGs..."

    DMG_CANDIDATE="$(find "$HOME/Downloads" -maxdepth 2 -name "DeskMate*.dmg" 2>/dev/null | head -n 1)"
    ZIP_CANDIDATE="$(find "$HOME/Downloads" -maxdepth 2 -name "DeskMate*.zip" 2>/dev/null | head -n 1)"

    if [ -n "$DMG_CANDIDATE" ] && [ -f "$DMG_CANDIDATE" ]; then
      echo "Found DMG in Downloads: $DMG_CANDIDATE"
      DOWNLOADED_FILE="$DMG_CANDIDATE"
    elif [ -n "$ZIP_CANDIDATE" ] && [ -f "$ZIP_CANDIDATE" ]; then
      echo "Found artifact ZIP in Downloads: $ZIP_CANDIDATE"
      DOWNLOADED_FILE="$ZIP_CANDIDATE"
    fi
  fi

  # Install from downloaded file
  if [ -n "$DOWNLOADED_FILE" ] && [ -f "$DOWNLOADED_FILE" ]; then
    if [[ "$DOWNLOADED_FILE" == *.dmg ]]; then
      echo "Mounting disk image: $DOWNLOADED_FILE ..."
      MOUNT_DIR=$(hdiutil attach "$DOWNLOADED_FILE" -nobrowse -readonly | grep "/Volumes" | awk -F'\t' '{print $NF}' | head -n 1)
      if [ -d "$MOUNT_DIR/DeskMate.app" ]; then
        echo "Copying DeskMate.app to $APP_DIR..."
        rm -rf "$TARGET_APP"
        cp -R "$MOUNT_DIR/DeskMate.app" "$APP_DIR/"
      fi
      hdiutil detach "$MOUNT_DIR" -force 2>/dev/null || true
    elif [[ "$DOWNLOADED_FILE" == *.zip ]]; then
      echo "Extracting application bundle..."
      unzip -q -o "$DOWNLOADED_FILE" -d "$TMP_DIR/"

      NESTED_APP="$(find "$TMP_DIR" -maxdepth 3 -name "DeskMate*.app" -type d 2>/dev/null | head -n 1)"
      NESTED_DMG="$(find "$TMP_DIR" -maxdepth 3 -name "DeskMate*.dmg" -type f 2>/dev/null | head -n 1)"

      if [ -n "$NESTED_APP" ] && [ -d "$NESTED_APP" ]; then
        echo "Copying DeskMate.app to $TARGET_APP..."
        rm -rf "$TARGET_APP"
        cp -R "$NESTED_APP" "$TARGET_APP"
      elif [ -n "$NESTED_DMG" ] && [ -f "$NESTED_DMG" ]; then
        MOUNT_DIR=$(hdiutil attach "$NESTED_DMG" -nobrowse -readonly | grep "/Volumes" | awk -F'\t' '{print $NF}' | head -n 1)
        if [ -d "$MOUNT_DIR/DeskMate.app" ]; then
          rm -rf "$TARGET_APP"
          cp -R "$MOUNT_DIR/DeskMate.app" "$APP_DIR/"
        fi
        hdiutil detach "$MOUNT_DIR" -force 2>/dev/null || true
      fi
    fi
  fi

  if [ ! -d "$TARGET_APP" ]; then
    echo -e "${RED}Error: Could not install DeskMate.${NC}"
    echo "Please ensure the GitHub Actions build on 'main' has completed or download DeskMate-macOS.dmg into ~/Downloads."
    exit 1
  fi
fi

# 5. Strip Gatekeeper Quarantine Attributes
echo "Stripping Gatekeeper quarantine lock..."
xattr -cr "$TARGET_APP" 2>/dev/null || true

# 6. Ensure proper binary permissions
echo "Setting executable permissions..."
chmod +x "$TARGET_APP/Contents/MacOS/DeskMate" 2>/dev/null || true
find "$TARGET_APP/Contents" -type f -name "deskmate_backend" -exec chmod +x {} + 2>/dev/null || true

# 7. Apply local ad-hoc signature to satisfy macOS Sequoia dyld
echo "Signing application bundle locally..."
codesign --force --deep --sign - "$TARGET_APP" 2>/dev/null || true

# 8. Launch DeskMate
echo -e "${GREEN}${BOLD}✔ DeskMate installed successfully to ${TARGET_APP}!${NC}"
echo "Launching DeskMate..."
open "$TARGET_APP"

echo "Done! DeskMate is now running."
