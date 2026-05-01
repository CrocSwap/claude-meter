#!/usr/bin/env bash
# Wipe claude-meter's persistent Safe Storage cache so the next launch
# re-runs the full first-install flow.
#
# This deletes ONLY our own keychain item (service "dev.claudemeter").
# It does not touch Claude desktop's "Claude Safe Storage" item.
#
# To also re-trigger Claude desktop's ACL prompts (the "Claude Meter wants
# to use your confidential information..." dialogs), open Keychain Access,
# find "Claude Safe Storage", Get Info → Access Control, and remove
# Claude Meter from the trusted apps list. Without that step, claude-meter
# is still on the ACL from your previous "Always Allow" choice and won't
# re-prompt even if its own cache is empty.
#
# Quit claude-meter first so the in-memory cache is also gone — otherwise
# the running process will repopulate the persistent cache from memory on
# its next poll.
set -euo pipefail

SERVICE="dev.claudemeter"
ACCOUNT="claude-safe-storage"

if security delete-generic-password -s "$SERVICE" -a "$ACCOUNT" >/dev/null 2>&1; then
  echo "Deleted $SERVICE / $ACCOUNT from the login keychain."
else
  echo "No item found for $SERVICE / $ACCOUNT — nothing to delete."
fi
