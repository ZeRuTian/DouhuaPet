#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p .build/logic-tests .build/cache/clang
export CLANG_MODULE_CACHE_PATH="$ROOT/.build/cache/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT/.build/cache/clang"

swiftc \
  Sources/DouhuaPet/Logic.swift \
  Sources/DouhuaPet/Settings.swift \
  Tests/LogicHarness/main.swift \
  -o .build/logic-tests/DouhuaPetLogicChecks

.build/logic-tests/DouhuaPetLogicChecks
