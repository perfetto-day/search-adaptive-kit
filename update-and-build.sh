#!/bin/bash
# Search Adaptive v0.8: update only the dedicated checkout, patch, build, install.
set -euo pipefail
KIT="$(cd "$(dirname "$0")" && pwd)"
MODE="${1:-install}"
if [[ "$MODE" != "install" && "$MODE" != "--stage" ]]; then echo "Usage: $0 [--stage]" >&2; exit 2; fi
ROOT="$HOME/Library/Application Support/SearchAdaptive"
SOURCE="$ROOT/Search-source"
mkdir -p "$ROOT"

# The CommandLineTools SwiftUI compiler may lack SwiftUIMacros. Use the full
# Xcode toolchain for this invocation without changing the system xcode-select.
if [[ -z "${DEVELOPER_DIR:-}" ]]; then
  selected="$(xcode-select -p 2>/dev/null || true)"
  if [[ -d "$selected/Platforms/MacOSX.platform" ]]; then
    export DEVELOPER_DIR="$selected"
  else
    for candidate in /Applications/Xcode.app/Contents/Developer /Applications/Xcode*.app/Contents/Developer; do
      if [[ -d "$candidate/Platforms/MacOSX.platform" ]]; then
        export DEVELOPER_DIR="$candidate"
        break
      fi
    done
  fi
fi
if [[ -z "${DEVELOPER_DIR:-}" || ! -d "$DEVELOPER_DIR/Platforms/MacOSX.platform" ]]; then
  echo "Full Xcode is required. Install Xcode from the App Store, open it once, and run this script again." >&2
  echo "Command Line Tools alone may fail with SwiftUIMacros.StateMacro not found." >&2
  exit 1
fi
echo "Using Xcode at: $DEVELOPER_DIR"

if [[ ! -d "$SOURCE/.git" ]]; then
  if [[ -e "$SOURCE" ]]; then
    echo "Refusing to replace unknown folder: $SOURCE" >&2
    exit 1
  fi
  git clone https://github.com/driceroland/Search.git "$SOURCE"
  touch "$ROOT/managed-by-search-adaptive"
fi
if [[ ! -f "$ROOT/managed-by-search-adaptive" ]]; then
  echo "Refusing to reset a repository not created by Search Adaptive: $SOURCE" >&2
  exit 1
fi
cd "$SOURCE"
if [[ "$(git remote get-url origin)" != "https://github.com/driceroland/Search.git" ]]; then
  echo "Unexpected Git remote; stopping." >&2
  exit 1
fi

git fetch origin main
git reset --hard HEAD
git checkout -B adaptive-chrome origin/main
git reset --hard origin/main
python3 "$KIT/apply_mod.py" "$SOURCE"

echo "Compiling Search Adaptive v0.8 (log: $ROOT/last-build.log)"
if ! ./build.sh release app 2>&1 | tee "$ROOT/last-build.log"; then
  echo "Build failed. Last log: $ROOT/last-build.log" >&2
  echo "Look for the FIRST compiler error, not follow-up messages." >&2
  exit 1
fi

if [[ "$MODE" == "--stage" ]]; then
  PENDING="$ROOT/Pending.app"
  if [[ -e "$PENDING" ]]; then rm -rf "$PENDING"; fi
  cp -R build/Search.app "$PENDING"
  echo "Staged new Search Adaptive build: $PENDING"
  exit 0
fi

DEST="$HOME/Applications/Search Adaptive.app"
mkdir -p "$HOME/Applications"
if pgrep -x Search >/dev/null 2>&1; then
  echo "Close every Search window and rerun to install the modified app." >&2
  echo "The freshly built copy is at $SOURCE/build/Search.app" >&2
  exit 1
fi
STAGING="$HOME/Applications/.Search-Adaptive-staging.app"
BACKUP="$HOME/Applications/.Search-Adaptive-backup.app"
if [[ -e "$STAGING" || -e "$BACKUP" ]]; then
  echo "An old staging/backup folder exists. Inspect it before retrying:" >&2
  echo "$STAGING" >&2; echo "$BACKUP" >&2
  exit 1
fi
cp -R build/Search.app "$STAGING"
if [[ -e "$DEST" ]]; then mv "$DEST" "$BACKUP"; fi
if mv "$STAGING" "$DEST"; then
  if [[ -e "$BACKUP" ]]; then rm -rf "$BACKUP"; fi
else
  echo "Install failed; preserving the previous application." >&2
  if [[ -e "$BACKUP" ]]; then mv "$BACKUP" "$DEST"; fi
  exit 1
fi
# Make a trusted copy of the updater helper available to the running app.
mkdir -p "$ROOT/Tools"
cp "$KIT/mod-update.command" "$ROOT/Tools/mod-update.command"
chmod +x "$ROOT/Tools/mod-update.command"
if [[ -d "$KIT/.git" ]]; then git -C "$KIT" rev-parse HEAD > "$ROOT/installed-mod.txt"; fi
printf '\nInstalled: %s\n' "$DEST"
echo "Search Adaptive checks for official Search releases by default, but never replaces its patched binary."
echo "Disable official release checks: $KIT/toggle-mode.command updates-off"
echo "To install an upstream update, rerun this build script."
echo "Enable: $KIT/toggle-mode.command on"
echo "Debug overlay: $KIT/toggle-mode.command debug-on"
echo "Launch: open \"$DEST\""