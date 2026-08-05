#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${DOUHUA_APP_OUTPUT:-$HOME/Applications/DouhuaPet.app}"

if pgrep -x DouhuaPet >/dev/null 2>&1; then
    pkill -TERM -x DouhuaPet
    for _ in {1..50}; do
        pgrep -x DouhuaPet >/dev/null 2>&1 || break
        sleep 0.1
    done
    if pgrep -x DouhuaPet >/dev/null 2>&1; then
        echo "DouhuaPet did not exit; use the menu-bar Exit command and retry." >&2
        exit 1
    fi
fi

"$ROOT/Scripts/build-app.sh"
open -n "$APP"
