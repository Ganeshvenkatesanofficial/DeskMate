#!/usr/bin/env bash
# ==============================================================================
# DeskMate Linux Build & Package Script (Creates DeskMate-Linux-x64.tar.gz)
# ==============================================================================

set -e

BOLD='\033[1m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

ROOT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
BUILD_OUTPUT_DIR="$ROOT_DIR/dist"
STAGE_DIR="$ROOT_DIR/build_stage/DeskMate"
ARCHIVE_NAME="DeskMate-Linux-x64.tar.gz"

echo -e "${BLUE}${BOLD}Building DeskMate for Linux (x64)...${NC}"

# 1. Build Backend
echo -e "${YELLOW}Step 1: Building Python backend executable with PyInstaller...${NC}"
cd "$ROOT_DIR/terminal-ai-agent"
if [ ! -d ".venv" ]; then
  python3 -m venv .venv
fi
source .venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
pip install pyinstaller
pyinstaller deskmate_backend.spec --clean
deactivate

# 2. Copy backend executable to Flutter assets
echo -e "${YELLOW}Step 2: Bundling backend into Flutter assets...${NC}"
mkdir -p "$ROOT_DIR/deskmate_app/assets/backend"
cp "$ROOT_DIR/terminal-ai-agent/dist/deskmate_backend" "$ROOT_DIR/deskmate_app/assets/backend/deskmate_backend"
chmod +x "$ROOT_DIR/deskmate_app/assets/backend/deskmate_backend"

# 3. Build Flutter Desktop Application
echo -e "${YELLOW}Step 3: Building Flutter Linux release bundle...${NC}"
cd "$ROOT_DIR/deskmate_app"
flutter pub get
flutter build linux --release

# 4. Package Release Archive
echo -e "${YELLOW}Step 4: Assembling portable tar.gz package...${NC}"
rm -rf "$ROOT_DIR/build_stage"
mkdir -p "$STAGE_DIR"
mkdir -p "$BUILD_OUTPUT_DIR"

# Copy Flutter release bundle
cp -r "$ROOT_DIR/deskmate_app/build/linux/x64/release/bundle/"* "$STAGE_DIR/"

# Copy scripts and metadata
cp "$ROOT_DIR/scripts/run_linux.sh" "$STAGE_DIR/run.sh"
chmod +x "$STAGE_DIR/run.sh"
chmod +x "$STAGE_DIR/DeskMate"
cp "$ROOT_DIR/scripts/install_linux.sh" "$STAGE_DIR/install_linux.sh"
chmod +x "$STAGE_DIR/install_linux.sh"
cp "$ROOT_DIR/scripts/deskmate.desktop" "$STAGE_DIR/deskmate.desktop"
cp "$ROOT_DIR/deskmate_app/assets/app_icon.png" "$STAGE_DIR/deskmate.png"

# Create tar.gz
cd "$ROOT_DIR/build_stage"
tar -czf "$BUILD_OUTPUT_DIR/$ARCHIVE_NAME" DeskMate
rm -rf "$ROOT_DIR/build_stage"

echo -e "${GREEN}${BOLD}DeskMate Linux tar.gz successfully created at: ${BUILD_OUTPUT_DIR}/${ARCHIVE_NAME}${NC}"
