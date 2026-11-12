#!/usr/bin/env bash
# ==============================================================================
# DeskMate Linux Portable Launcher
# ==============================================================================

set -e

# Resolve physical directory even if invoked through symlink
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$( cd "$( dirname "$SCRIPT_PATH" )" && pwd )"

# Ensure execution permissions on binary & bundled backend
chmod +x "$SCRIPT_DIR/DeskMate" 2>/dev/null || true
if [ -f "$SCRIPT_DIR/data/flutter_assets/assets/backend/deskmate_backend" ]; then
  chmod +x "$SCRIPT_DIR/data/flutter_assets/assets/backend/deskmate_backend" 2>/dev/null || true
fi

# Ensure GTK / Wayland / X11 compatibility
export GDK_BACKEND=x11,wayland,*

# Launch DeskMate with harmless Gdk clipboard spam filtered out
exec "$SCRIPT_DIR/DeskMate" "$@" 2> >(grep -v -E "Gdk-WARNING \*\*:.*(Error converting selection|UTF8_STRING)" >&2)

