#!/usr/bin/env bash
# Runs the same checks as CI (.github/workflows/ci.yml).
# Usage: tool/check.sh
set -euo pipefail
cd "$(dirname "$0")/.."

flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib test
flutter analyze --fatal-infos
flutter test --coverage

# Reminder times are local wall-clock times, so scheduling logic must also
# pass in a zone with daylight-saving changes and one without.
TZ=America/New_York flutter test
TZ=Asia/Kolkata flutter test
