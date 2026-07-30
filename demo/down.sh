#!/usr/bin/env bash
# Stop the demo daemons. Config and Claude logins under ~/.herald-demo are kept
# so the next run doesn't re-login; delete that dir by hand for a full reset.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
teardown
echo "demo daemons stopped (state kept under $DEMO_HOME)"
