#!/usr/bin/env bash
# ==============================================================================
# DeskMate Linux Installer
# Installs DeskMate to ~/.local/share/DeskMate with desktop menu integration
# ==============================================================================

set -e

BOLD='\033[1m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}${BOLD}"
cat << "EOF"
  ____            _    __  __       _       
 |  _ \  ___  ___| | _|  \/  | __ _| |_ ___ 
 | | | |/ _ \/ __| |/ / |\/| |/ _` | __/ _ \
 | |_| |  __/\__ \   <| |  | | (_| | ||  __/
 |____/ \___||___/_|\_\_|  |_|\__,_|\__\___|
EOF
echo -e "${NC}"
echo -e "${BOLD}DeskMate Linux Installer${NC}"
echo "--------------------------------------------------------"

SOURCE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
INSTALL_DIR="$HOME/.local/share/DeskMate"
BIN_DIR="$HOME/.local/bin"
DESKTOP_DIR="$HOME/.local/share/applications"
ICON_DIR="$HOME/.local/share/icons/hicolor/512x512/apps"

mkdir -p "$INSTALL_DIR"
mkdir -p "$BIN_DIR"
mkdir -p "$DESKTOP_DIR"
mkdir -p "$ICON_DIR"

echo -e "Installing DeskMate to: ${BOLD}${INSTALL_DIR}${NC}"

# Terminate running DeskMate instances
pkill -9 -f "deskmate_backend" 2>/dev/null || true
killall -9 DeskMate 2>/dev/null || true

# Copy files
cp -r "$SOURCE_DIR"/* "$INSTALL_DIR/"

# Permissions
chmod +x "$INSTALL_DIR/DeskMate"
chmod +x "$INSTALL_DIR/run.sh" 2>/dev/null || true
if [ -f "$INSTALL_DIR/data/flutter_assets/assets/backend/deskmate_backend" ]; then
  chmod +x "$INSTALL_DIR/data/flutter_assets/assets/backend/deskmate_backend"
fi

# Symlink to ~/.local/bin/deskmate
ln -sf "$INSTALL_DIR/run.sh" "$BIN_DIR/deskmate"
chmod +x "$BIN_DIR/deskmate"

# Install Icon
if [ -f "$INSTALL_DIR/deskmate.png" ]; then
  cp "$INSTALL_DIR/deskmate.png" "$ICON_DIR/deskmate.png"
fi

# Install Desktop Entry
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

# Update desktop database if available
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true
fi

echo -e "${GREEN}${BOLD}DeskMate installed successfully!${NC}"
echo ""
echo "You can launch DeskMate in any of the following ways:"
echo -e " 1. Type ${BOLD}deskmate${NC} in your terminal (make sure ~/.local/bin is in your PATH)"
echo -e " 2. Launch from your desktop application launcher / search menu"
echo -e " 3. Directly run: ${BOLD}$INSTALL_DIR/run.sh${NC}"
echo ""
