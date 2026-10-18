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
else
  APP_DIR="$HOME/Applications"
  mkdir -p "$APP_DIR"
fi
TARGET_APP="$APP_DIR/DeskMate.app"

echo -e "Installation Destination: ${BOLD}${TARGET_APP}${NC}"

# 3. Terminate any currently running DeskMate instances
killall -9 DeskMate 2>/dev/null || true

# 4. Check for existing local build or download from GitHub
REPO="Ganeshvenkatesanofficial/DeskMate"
DOWNLOAD_URL="https://github.com/${REPO}/releases/latest/download/DeskMate-macOS.zip"

TMP_DIR="$(mktemp -d /tmp/deskmate_install_XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LOCAL_APP_PATH="${SCRIPT_DIR}/deskmate_app/build/macos/Build/Products/Release/DeskMate.app"
LOCAL_DEBUG_PATH="${SCRIPT_DIR}/deskmate_app/build/macos/Build/Products/Debug/DeskMate.app"

if [ -d "$LOCAL_APP_PATH" ]; then
  echo -e "${YELLOW}Found local Release build in repository.${NC}"
  echo "Installing from local Release build..."
  rm -rf "$TARGET_APP"
  cp -R "$LOCAL_APP_PATH" "$APP_DIR/"
elif [ -d "$LOCAL_DEBUG_PATH" ]; then
  echo -e "${YELLOW}Found local Debug build in repository.${NC}"
  echo "Installing from local Debug build..."
  rm -rf "$TARGET_APP"
  cp -R "$LOCAL_DEBUG_PATH" "$APP_DIR/"
else
  echo -e "Checking for latest release package from GitHub..."
  ZIP_PATH="$TMP_DIR/DeskMate-macOS.zip"

  # URLs to check in order of preference
  RELEASE_URLS=(
    "https://github.com/${REPO}/releases/download/continuous/DeskMate-macOS.zip"
    "https://github.com/${REPO}/releases/latest/download/DeskMate-macOS.zip"
    "https://github.com/${REPO}/releases/download/v1.0.0/DeskMate-macOS.zip"
  )

  for URL in "${RELEASE_URLS[@]}"; do
    echo "Attempting download from: $URL ..."
    if curl -fsSL -o "$ZIP_PATH" "$URL" 2>/dev/null && [ -s "$ZIP_PATH" ]; then
      echo -e "${GREEN}Successfully downloaded DeskMate package from release.${NC}"
      break
    fi
    rm -f "$ZIP_PATH"
  done

  # Fallback to local Downloads directory if online release is not yet drafted/published
  if [ ! -f "$ZIP_PATH" ] || [ ! -s "$ZIP_PATH" ]; then
    echo -e "${YELLOW}Notice: Online release archive not published or accessible yet.${NC}"
    echo "Searching ~/Downloads for downloaded GitHub Actions artifacts or DMGs..."

    ZIP_CANDIDATE="$(find "$HOME/Downloads" -maxdepth 2 -name "DeskMate*.zip" 2>/dev/null | head -n 1)"
    DMG_CANDIDATE="$(find "$HOME/Downloads" -maxdepth 2 -name "DeskMate*.dmg" 2>/dev/null | head -n 1)"

    if [ -n "$ZIP_CANDIDATE" ] && [ -f "$ZIP_CANDIDATE" ]; then
      echo "Found artifact ZIP in Downloads: $ZIP_CANDIDATE"
      cp "$ZIP_CANDIDATE" "$ZIP_PATH"
    elif [ -n "$DMG_CANDIDATE" ] && [ -f "$DMG_CANDIDATE" ]; then
      echo "Found DMG in Downloads: $DMG_CANDIDATE"
      MOUNT_DIR=$(hdiutil attach "$DMG_CANDIDATE" -nobrowse -readonly | grep "/Volumes" | awk -F'\t' '{print $NF}' | head -n 1)
      if [ -d "$MOUNT_DIR/DeskMate.app" ]; then
        rm -rf "$TARGET_APP"
        cp -R "$MOUNT_DIR/DeskMate.app" "$APP_DIR/"
      fi
      hdiutil detach "$MOUNT_DIR" -force 2>/dev/null || true
    fi
  fi

  # Extract ZIP if available
  if [ -f "$ZIP_PATH" ] && [ -s "$ZIP_PATH" ]; then
    echo "Extracting application bundle..."
    unzip -q -o "$ZIP_PATH" -d "$TMP_DIR/"

    NESTED_APP="$(find "$TMP_DIR" -maxdepth 3 -name "DeskMate*.app" -type d 2>/dev/null | head -n 1)"
    NESTED_DMG="$(find "$TMP_DIR" -maxdepth 3 -name "DeskMate*.dmg" -type f 2>/dev/null | head -n 1)"

    if [ -n "$NESTED_APP" ] && [ -d "$NESTED_APP" ]; then
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

  if [ ! -d "$TARGET_APP" ]; then
    echo -e "${RED}Error: Could not install DeskMate.${NC}"
    echo "Please ensure the GitHub Actions build on 'dev' has completed or download DeskMate-macOS.dmg into ~/Downloads."
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

# 7. Launch DeskMate
echo -e "${GREEN}${BOLD}✔ DeskMate installed successfully to ${TARGET_APP}!${NC}"
echo "Launching DeskMate..."
open "$TARGET_APP"

echo "Done! DeskMate is now running."
