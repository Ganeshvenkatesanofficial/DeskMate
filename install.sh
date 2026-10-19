#!/usr/bin/env bash
# ==============================================================================
# DeskMate 1-Line Universal Installer (macOS & Linux)
# Installs DeskMate natively without requiring sudo or root access.
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
echo -e "${BOLD}DeskMate Universal Auto-Installer${NC}"
echo "--------------------------------------------------------"

OS="$(uname -s)"
ARCH="$(uname -m)"
echo -e "Detected OS: ${BOLD}${OS}${NC} (${ARCH})"

REPO="Ganeshvenkatesanofficial/DeskMate"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
TMP_DIR="$(mktemp -d /tmp/deskmate_install_XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

# ==============================================================================
# LINUX INSTALLATION
# ==============================================================================
if [ "$OS" = "Linux" ]; then
  INSTALL_DIR="$HOME/.local/share/DeskMate"
  BIN_DIR="$HOME/.local/bin"
  DESKTOP_DIR="$HOME/.local/share/applications"
  ICON_DIR="$HOME/.local/share/icons/hicolor/512x512/apps"

  mkdir -p "$INSTALL_DIR"
  mkdir -p "$BIN_DIR"
  mkdir -p "$DESKTOP_DIR"
  mkdir -p "$ICON_DIR"

  echo -e "Installation Destination: ${BOLD}${INSTALL_DIR}${NC}"

  # Terminate any running instances
  pkill -9 -f "deskmate_backend" 2>/dev/null || true
  killall -9 DeskMate 2>/dev/null || true

  LOCAL_BUNDLE="${SCRIPT_DIR}/deskmate_app/build/linux/x64/release/bundle"
  LOCAL_TAR="${SCRIPT_DIR}/dist/DeskMate-Linux-x64.tar.gz"

  if [ -d "$LOCAL_BUNDLE" ] && [ -f "$LOCAL_BUNDLE/DeskMate" ]; then
    echo -e "${YELLOW}Found local Flutter Linux release build in repository.${NC}"
    echo "Installing from local bundle..."
    rm -rf "$INSTALL_DIR"/*
    cp -r "$LOCAL_BUNDLE"/* "$INSTALL_DIR/"
  elif [ -f "$LOCAL_TAR" ]; then
    echo -e "${YELLOW}Found local package archive: $LOCAL_TAR${NC}"
    tar -xzf "$LOCAL_TAR" -C "$TMP_DIR/"
    rm -rf "$INSTALL_DIR"/*
    cp -r "$TMP_DIR/DeskMate"/* "$INSTALL_DIR/"
  else
    echo "Checking for latest Linux release package from GitHub..."
    DOWNLOADED_FILE=""

    RELEASE_URLS=(
      "https://github.com/${REPO}/releases/download/continuous/DeskMate-Linux-x64.tar.gz"
      "https://github.com/${REPO}/releases/latest/download/DeskMate-Linux-x64.tar.gz"
      "https://github.com/${REPO}/releases/download/v1.0.0/DeskMate-Linux-x64.tar.gz"
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

    # Fallback to Downloads folder
    if [ -z "$DOWNLOADED_FILE" ]; then
      TAR_CANDIDATE="$(find "$HOME/Downloads" -maxdepth 2 -name "DeskMate*Linux*.tar.gz" 2>/dev/null | head -n 1)"
      if [ -n "$TAR_CANDIDATE" ] && [ -f "$TAR_CANDIDATE" ]; then
        echo "Found package in Downloads: $TAR_CANDIDATE"
        DOWNLOADED_FILE="$TAR_CANDIDATE"
      fi
    fi

    if [ -n "$DOWNLOADED_FILE" ] && [ -f "$DOWNLOADED_FILE" ]; then
      echo "Extracting package..."
      tar -xzf "$DOWNLOADED_FILE" -C "$TMP_DIR/"
      rm -rf "$INSTALL_DIR"/*
      if [ -d "$TMP_DIR/DeskMate" ]; then
        cp -r "$TMP_DIR/DeskMate"/* "$INSTALL_DIR/"
      else
        cp -r "$TMP_DIR"/* "$INSTALL_DIR/"
      fi
    fi
  fi

  if [ ! -f "$INSTALL_DIR/DeskMate" ]; then
    echo -e "${RED}Error: DeskMate binary not found in installation destination.${NC}"
    echo "Please ensure DeskMate-Linux-x64.tar.gz has been built or downloaded."
    exit 1
  fi

  # Copy runner script if missing
  if [ ! -f "$INSTALL_DIR/run.sh" ]; then
    cat > "$INSTALL_DIR/run.sh" << 'RUN_EOF'
#!/usr/bin/env bash
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$( cd "$( dirname "$SCRIPT_PATH" )" && pwd )"
chmod +x "$SCRIPT_DIR/DeskMate" 2>/dev/null || true
if [ -f "$SCRIPT_DIR/data/flutter_assets/assets/backend/deskmate_backend" ]; then
  chmod +x "$SCRIPT_DIR/data/flutter_assets/assets/backend/deskmate_backend" 2>/dev/null || true
fi
export GDK_BACKEND=x11,wayland,*
exec "$SCRIPT_DIR/DeskMate" "$@"
RUN_EOF
  fi

  # Set permissions
  chmod +x "$INSTALL_DIR/DeskMate"
  chmod +x "$INSTALL_DIR/run.sh"
  if [ -f "$INSTALL_DIR/data/flutter_assets/assets/backend/deskmate_backend" ]; then
    chmod +x "$INSTALL_DIR/data/flutter_assets/assets/backend/deskmate_backend"
  fi

  # Symlink to ~/.local/bin/deskmate
  ln -sf "$INSTALL_DIR/run.sh" "$BIN_DIR/deskmate"
  chmod +x "$BIN_DIR/deskmate"

  # Icon & Desktop file
  if [ -f "$INSTALL_DIR/deskmate.png" ]; then
    cp "$INSTALL_DIR/deskmate.png" "$ICON_DIR/deskmate.png"
  elif [ -f "${SCRIPT_DIR}/deskmate_app/assets/app_icon.png" ]; then
    cp "${SCRIPT_DIR}/deskmate_app/assets/app_icon.png" "$ICON_DIR/deskmate.png"
  fi

  cat > "$DESKTOP_DIR/deskmate.desktop" << EOF
[Desktop Entry]
Name=DeskMate
Comment=Open-Source AI Desktop Copilot & Personal Assistant
Exec=$INSTALL_DIR/run.sh %u
Icon=$ICON_DIR/deskmate.png
Terminal=false
Type=Application
Categories=Utility;Development;
StartupWMClass=deskmate_app
EOF
  chmod +x "$DESKTOP_DIR/deskmate.desktop"

  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true
  fi

  echo -e "${GREEN}${BOLD}✔ DeskMate installed successfully to ${INSTALL_DIR}!${NC}"
  echo ""
  echo "You can launch DeskMate:"
  echo -e " 1. Via terminal: ${BOLD}deskmate${NC} (or $INSTALL_DIR/run.sh)"
  echo -e " 2. Via application search menu: 'DeskMate'"
  echo ""
  echo "Launching DeskMate..."
  nohup "$INSTALL_DIR/run.sh" >/dev/null 2>&1 &
  exit 0
fi

# ==============================================================================
# MACOS INSTALLATION
# ==============================================================================
if [ "$OS" != "Darwin" ]; then
  echo -e "${RED}Error: Operating system '$OS' is not supported.${NC}"
  exit 1
fi

# Determine Installation Target Directory
if [ -w "/Applications" ]; then
  APP_DIR="/Applications"
  TARGET_APP="$APP_DIR/DeskMate.app"
else
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

# Terminate running instances
killall -9 DeskMate 2>/dev/null || true

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
  DOWNLOADED_FILE=""

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

# Strip Gatekeeper Quarantine Attributes
echo "Stripping Gatekeeper quarantine lock..."
xattr -cr "$TARGET_APP" 2>/dev/null || true

# Ensure proper binary permissions
echo "Setting executable permissions..."
chmod +x "$TARGET_APP/Contents/MacOS/DeskMate" 2>/dev/null || true
find "$TARGET_APP/Contents" -type f -name "deskmate_backend" -exec chmod +x {} + 2>/dev/null || true

# Apply local ad-hoc signature to satisfy macOS Sequoia dyld
echo "Signing application bundle locally..."
codesign --force --deep --sign - "$TARGET_APP" 2>/dev/null || true

# Launch DeskMate
echo -e "${GREEN}${BOLD}✔ DeskMate installed successfully to ${TARGET_APP}!${NC}"
echo "Launching DeskMate..."
open "$TARGET_APP"

echo "Done! DeskMate is now running."
