#!/bin/bash
# Search Adaptive v0.8: explicit pin-to-SHA update builder / staged installer.
# This script is copied into ~/Library/Application Support/SearchAdaptive/Tools
# by the initial trusted install. No automatic remote scripts are launched.
set -euo pipefail
ROOT="$HOME/Library/Application Support/SearchAdaptive"
REMOTE='https://github.com/perfetto-day/search-adaptive-kit.git'
KIT="$ROOT/Kit-source"
mode="${1:-}"
if [[ "$mode" == 'build' ]]; then
  kind="${2:-}" name="${3:-}" sha="${4:-}"
  if [[ "$kind" != 'branch' && "$kind" != 'tag' ]]; then echo 'Invalid ref type' >&2; exit 2; fi
  if [[ ! "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ ]] || [[ "$name" == *'..'* || "$name" == *'//'* || "$name" == *'@{'* ]]; then
    echo 'Unsafe Git ref' >&2; exit 2
  fi
  if [[ ! "$sha" =~ ^[a-fA-F0-9]{40}$ ]]; then echo 'Invalid expected commit SHA' >&2; exit 2; fi
  mkdir -p "$ROOT"
  if [[ ! -d "$KIT/.git" ]]; then
    if [[ -e "$KIT" ]]; then echo 'Refusing to overwrite unmanaged kit folder' >&2; exit 1; fi
    git clone --no-checkout "$REMOTE" "$KIT"
    touch "$ROOT/managed-kit-source"
  fi
  if [[ ! -f "$ROOT/managed-kit-source" ]] || [[ "$(git -C "$KIT" remote get-url origin)" != "$REMOTE" ]]; then
    echo 'Unmanaged checkout or wrong origin; aborting' >&2; exit 1
  fi
  ref="refs/heads/$name"
  if [[ "$kind" == 'tag' ]]; then ref="refs/tags/$name"; fi
  rm -rf "$ROOT/Pending.app"
  rm -f "$ROOT/pending-mod.txt"
  git -C "$KIT" fetch --depth 1 origin "$ref"
  actual="$(git -C "$KIT" rev-parse 'FETCH_HEAD^{commit}')"
  if [[ "$actual" != "$sha" ]]; then echo "Ref moved; expected $sha, found $actual. Recheck GitHub." >&2; exit 1; fi
  git -C "$KIT" checkout --force --detach "$actual"
  "$KIT/update-and-build.sh" --stage
  printf '%s\n' "$actual" > "$ROOT/pending-mod.txt"
  printf 'Staged pinned commit %s. Install only after reviewing this build.\n' "$actual"
elif [[ "$mode" == 'install' ]]; then
  pid="${2:-}"
  if [[ ! "$pid" =~ ^[0-9]+$ ]]; then echo 'Invalid PID' >&2; exit 2; fi
  # Wait for the old app to fully exit; no root privileges or profile changes.
  for ((i=0;i<200;i++)); do
    if ! kill -0 "$pid" 2>/dev/null; then break; fi
    sleep 0.25
  done
  if kill -0 "$pid" 2>/dev/null; then echo 'Browser still running; install cancelled.' >&2; exit 1; fi
  PENDING="$ROOT/Pending.app"
  [[ -d "$PENDING" && -f "$ROOT/pending-mod.txt" ]] || { echo 'No built app staged' >&2; exit 1; }
  DEST="$HOME/Applications/Search Adaptive.app"
  BACKUP="$HOME/Applications/.Search-Adaptive-mod-backup.app"
  [[ ! -e "$BACKUP" ]] || { echo "Backup already exists at $BACKUP" >&2; exit 1; }
  mkdir -p "$HOME/Applications"
  if [[ -e "$DEST" ]]; then mv "$DEST" "$BACKUP"; fi
  if mv "$PENDING" "$DEST"; then
    cp "$ROOT/pending-mod.txt" "$ROOT/installed-mod.txt"
    rm -f "$ROOT/pending-mod.txt"
    [[ ! -e "$BACKUP" ]] || rm -rf "$BACKUP"
    open "$DEST"
  else
    [[ ! -e "$BACKUP" ]] || mv "$BACKUP" "$DEST"
    echo 'Install failed; original app restored' >&2; exit 1
  fi
else
  echo 'Usage: mod-update.command build branch|tag NAME SHA | install PID' >&2
  exit 2
fi