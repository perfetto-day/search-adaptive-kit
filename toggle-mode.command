#!/bin/bash
# Usage: ./toggle-mode.command on|off|status|debug-on|debug-off|updates-on|updates-off
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
    echo 'Color diagnostics ON. Restart Search Adaptive.' ;;
  debug-off)
    defaults write "$DOMAIN" adaptive.chrome.debug -bool false
    echo 'Color diagnostics OFF. Restart Search Adaptive.' ;;
  updates-on)
    defaults write "$DOMAIN" adaptive.chrome.updateChecks -bool true
    echo 'Official Search release checks ON (the default). Restart Search Adaptive.' ;;
  updates-off)
    defaults write "$DOMAIN" adaptive.chrome.updateChecks -bool false
    echo 'Official Search release checks OFF. Restart Search Adaptive; manual checks remain available.' ;;
  status)
    echo -n 'Automatic release checks: '
    defaults read "$DOMAIN" adaptive.chrome.updateChecks 2>/dev/null || echo '1 (default)'
    echo -n 'Adaptive colors: '
    defaults read "$DOMAIN" adaptive.chrome.enabled 2>/dev/null || echo '0 (default)'
    echo -n 'Diagnostics: '
    defaults read "$DOMAIN" adaptive.chrome.debug 2>/dev/null || echo '0 (default)' ;;
  *) echo "Usage: $0 on|off|status|debug-on|debug-off|updates-on|updates-off" >&2; exit 2 ;;
esac