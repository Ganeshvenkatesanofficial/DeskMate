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
  echo -e "Downloading latest release package from GitHub..."
  ZIP_PATH="$TMP_DIR/DeskMate-macOS.zip"
  
  HTTP_STATUS=$(curl -fsSL -w "%{http_code}" -o "$ZIP_PATH" "$DOWNLOAD_URL" || true)
  if [ ! -f "$ZIP_PATH" ] || [ ! -s "$ZIP_PATH" ]; then
    # Fallback to dev release asset or raw build if latest release tag is not yet drafted
    FALLBACK_URL="https://github.com/${REPO}/releases/download/v1.0.0/DeskMate-macOS.zip"
    echo -e "${YELLOW}Attempting fallback release URL...${NC}"
    curl -fsSL -o "$ZIP_PATH" "$FALLBACK_URL" || true
  fi

  if [ -f "$ZIP_PATH" ] && [ -s "$ZIP_PATH" ]; then
    echo "Extracting application bundle..."
    unzip -q -o "$ZIP_PATH" -d "$TMP_DIR/"
    rm -rf "$TARGET_APP"
    cp -R "$TMP_DIR"/DeskMate*.app "$TARGET_APP"
  else
    echo -e "${YELLOW}Notice: Remote release archive not found online yet.${NC}"
    # Check if a DMG or existing bundle is in Downloads
    DMG_CANDIDATE="$(find "$HOME/Downloads" -maxdepth 2 -name "DeskMate*.dmg" 2>/dev/null | head -n 1)"
    if [ -n "$DMG_CANDIDATE" ] && [ -f "$DMG_CANDIDATE" ]; then
      echo "Mounting disk image from Downloads: $DMG_CANDIDATE"
      MOUNT_DIR=$(hdiutil attach "$DMG_CANDIDATE" -nobrowse -readonly | grep "/Volumes" | awk -F'\t' '{print $NF}' | head -n 1)
      if [ -d "$MOUNT_DIR/DeskMate.app" ]; then
        rm -rf "$TARGET_APP"
        cp -R "$MOUNT_DIR/DeskMate.app" "$APP_DIR/"
      fi
      hdiutil detach "$MOUNT_DIR" -force 2>/dev/null || true
    else
      echo -e "${RED}Error: Could not locate a release artifact. Please run in your repo or download the release.${NC}"
      exit 1
    fi
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
