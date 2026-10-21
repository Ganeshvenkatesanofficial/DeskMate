#!/usr/bin/env bash
# ==============================================================================
# DeskMate macOS 1-Line Installer (Open-Source Edition)
# Installs directly into /Applications with macOS Gatekeeper bypass.
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

# 2. Terminate any currently running DeskMate instances
echo "Checking for running instances..."
killall -9 DeskMate 2>/dev/null || true

# 3. Check for existing local build or download from GitHub
REPO="Ganeshvenkatesanofficial/DeskMate"
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

SOURCE_APP=""

if [ -n "$LOCAL_APP_CANDIDATE" ]; then
  echo -e "${YELLOW}Found local build in repository: ${LOCAL_APP_CANDIDATE}${NC}"
  SOURCE_APP="$LOCAL_APP_CANDIDATE"
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

  # Extract / Mount source app
  if [ -n "$DOWNLOADED_FILE" ] && [ -f "$DOWNLOADED_FILE" ]; then
    if [[ "$DOWNLOADED_FILE" == *.dmg ]]; then
      echo "Mounting disk image: $DOWNLOADED_FILE ..."
      MOUNT_DIR=$(hdiutil attach "$DOWNLOADED_FILE" -nobrowse -readonly | grep "/Volumes" | awk -F'\t' '{print $NF}' | head -n 1)
      if [ -d "$MOUNT_DIR/DeskMate.app" ]; then
        cp -R "$MOUNT_DIR/DeskMate.app" "$TMP_DIR/DeskMate.app"
        SOURCE_APP="$TMP_DIR/DeskMate.app"
      fi
      hdiutil detach "$MOUNT_DIR" -force 2>/dev/null || true
    elif [[ "$DOWNLOADED_FILE" == *.zip ]]; then
      echo "Extracting application bundle..."
      unzip -q -o "$DOWNLOADED_FILE" -d "$TMP_DIR/"

      NESTED_APP="$(find "$TMP_DIR" -maxdepth 3 -name "DeskMate*.app" -type d 2>/dev/null | head -n 1)"
      NESTED_DMG="$(find "$TMP_DIR" -maxdepth 3 -name "DeskMate*.dmg" -type f 2>/dev/null | head -n 1)"

      if [ -n "$NESTED_APP" ] && [ -d "$NESTED_APP" ]; then
        SOURCE_APP="$NESTED_APP"
      elif [ -n "$NESTED_DMG" ] && [ -f "$NESTED_DMG" ]; then
        MOUNT_DIR=$(hdiutil attach "$NESTED_DMG" -nobrowse -readonly | grep "/Volumes" | awk -F'\t' '{print $NF}' | head -n 1)
        if [ -d "$MOUNT_DIR/DeskMate.app" ]; then
          cp -R "$MOUNT_DIR/DeskMate.app" "$TMP_DIR/DeskMate.app"
          SOURCE_APP="$TMP_DIR/DeskMate.app"
        fi
        hdiutil detach "$MOUNT_DIR" -force 2>/dev/null || true
      fi
    fi
  fi
fi

if [ -z "$SOURCE_APP" ] || [ ! -d "$SOURCE_APP" ]; then
  echo -e "${RED}Error: Could not locate DeskMate.app to install.${NC}"
  echo "Please ensure the GitHub Actions build has completed or download DeskMate-macOS.dmg into ~/Downloads."
  exit 1
fi

# 4. Copy to /Applications
TARGET_APP="/Applications/DeskMate.app"
echo "Installing DeskMate directly to ${BOLD}${TARGET_APP}${NC}..."

INSTALLED=0

# Step A: Check if directly writable
if touch /Applications/.test_dm_write 2>/dev/null; then
  rm -f /Applications/.test_dm_write
  rm -rf "$TARGET_APP"
  cp -R "$SOURCE_APP" /Applications/
  INSTALLED=1
fi

# Step B: Check if member of admin group
if [ "$INSTALLED" -ne 1 ] && id -Gn 2>/dev/null | grep -qw "admin"; then
  newgrp admin << EOF 2>/dev/null
rm -rf /Applications/DeskMate.app
cp -R "$SOURCE_APP" /Applications/
EOF
  if [ -d "$TARGET_APP" ]; then
    INSTALLED=1
  fi
fi

# Step C: Elevate with standard macOS authorization dialog if needed
if [ "$INSTALLED" -ne 1 ]; then
  echo -e "${YELLOW}Administrator authorization requested to place DeskMate in /Applications...${NC}"
  if command -v osascript >/dev/null 2>&1; then
    if osascript -e "do shell script \"rm -rf /Applications/DeskMate.app && cp -R '$SOURCE_APP' /Applications/ && chmod -R u+rwX,go+rX /Applications/DeskMate.app\" with prompt \"DeskMate Installer needs administrator privileges to copy DeskMate to your Applications folder:\" with administrator privileges" 2>/dev/null; then
      INSTALLED=1
    fi
  fi
fi

# Fallback to ~/Applications if all above failed
if [ "$INSTALLED" -ne 1 ] || [ ! -d "$TARGET_APP" ]; then
  echo -e "${YELLOW}Could not write to /Applications. Installing to ~/Applications instead...${NC}"
  mkdir -p "$HOME/Applications"
  TARGET_APP="$HOME/Applications/DeskMate.app"
  rm -rf "$TARGET_APP"
  cp -R "$SOURCE_APP" "$HOME/Applications/"
fi

# 5. Strip Gatekeeper Quarantine Attributes
echo "Stripping Gatekeeper quarantine lock..."
xattr -cr "$TARGET_APP" 2>/dev/null || true

# 6. Ensure proper binary permissions
echo "Setting executable permissions..."
chmod -R u+rwX,go+rX "$TARGET_APP" 2>/dev/null || true
chmod +x "$TARGET_APP/Contents/MacOS/DeskMate" 2>/dev/null || true
find "$TARGET_APP/Contents" -type f -name "deskmate_backend" -exec chmod +x {} + 2>/dev/null || true
find "$TARGET_APP/Contents" -type f -name "macos_audio_capture" -exec chmod +x {} + 2>/dev/null || true

# 7. Apply local ad-hoc signature to satisfy macOS Sequoia dyld
echo "Signing application bundle locally..."
codesign --force --deep --sign - "$TARGET_APP" 2>/dev/null || true

# 8. Refresh Finder view
killall Finder 2>/dev/null || true

# 9. Launch DeskMate
echo -e "${GREEN}${BOLD}✔ DeskMate installed successfully to ${TARGET_APP}!${NC}"
echo "Launching DeskMate..."
open "$TARGET_APP"

echo "Done! DeskMate is now running."
