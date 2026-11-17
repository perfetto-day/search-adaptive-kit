#!/bin/bash
# Usage: ./toggle-mode.command on|off|status|debug-on|debug-off
set -euo pipefail
DOMAIN='com.officecommun.search'
case "${1:-status}" in
  on)
    defaults write "$DOMAIN" adaptive.chrome.enabled -bool true
    echo 'Adaptive colors ON. Restart Search Adaptive.' ;;
  off)
    defaults write "$DOMAIN" adaptive.chrome.enabled -bool false
    echo 'Adaptive colors OFF. Restart Search Adaptive.' ;;
  debug-on)
    defaults write "$DOMAIN" adaptive.chrome.debug -bool true
    echo 'Color diagnostics ON (small source/hex label). Restart Search Adaptive.' ;;
  debug-off)
    defaults write "$DOMAIN" adaptive.chrome.debug -bool false
    echo 'Color diagnostics OFF. Restart Search Adaptive.' ;;
  status)
    echo -n 'Adaptive colors: '
    defaults read "$DOMAIN" adaptive.chrome.enabled 2>/dev/null || echo '0 (default)'
    echo -n 'Diagnostics: '
    defaults read "$DOMAIN" adaptive.chrome.debug 2>/dev/null || echo '0 (default)' ;;
  *) echo "Usage: $0 on|off|status|debug-on|debug-off" >&2; exit 2 ;;
esac