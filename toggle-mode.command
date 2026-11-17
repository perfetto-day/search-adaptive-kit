#!/bin/bash
# Usage: ./toggle-mode.command on|off|status|debug-on|debug-off|updates-on|updates-off|search-on|search-off|round-on|round-off
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
  search-on) defaults write "$DOMAIN" adaptive.chrome.searchTint -bool true; echo 'Search overlay tint ON. Reload pages if needed.' ;;
  search-off) defaults write "$DOMAIN" adaptive.chrome.searchTint -bool false; echo 'Search overlay tint OFF.' ;;
  round-on) defaults write "$DOMAIN" adaptive.chrome.roundedTop -bool true; echo 'Top page rounding ON. Restart Search Adaptive.' ;;
  round-off) defaults write "$DOMAIN" adaptive.chrome.roundedTop -bool false; echo 'Top page rounding OFF. Restart Search Adaptive.' ;;
  status)
    echo -n 'Automatic release checks: '
    defaults read "$DOMAIN" adaptive.chrome.updateChecks 2>/dev/null || echo '1 (default)'
    echo -n 'Adaptive colors: '
    defaults read "$DOMAIN" adaptive.chrome.enabled 2>/dev/null || echo '0 (default)'
    echo -n 'Search overlay tint: '
    defaults read "$DOMAIN" adaptive.chrome.searchTint 2>/dev/null || echo '1 (default)'
    echo -n 'Top page rounding: '
    defaults read "$DOMAIN" adaptive.chrome.roundedTop 2>/dev/null || echo '1 (default)'
    echo -n 'Diagnostics: ' 
    defaults read "$DOMAIN" adaptive.chrome.debug 2>/dev/null || echo '0 (default)' ;;
  *) echo "Usage: $0 on|off|status|debug-on|debug-off|updates-on|updates-off|search-on|search-off|round-on|round-off" >&2; exit 2 ;;
esac