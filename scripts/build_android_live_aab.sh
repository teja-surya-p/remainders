#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KEY_FILE="$ROOT_DIR/revenuecat.keys.local.json"

if [[ ! -f "$KEY_FILE" ]]; then
  echo "Missing $KEY_FILE"
  echo "Copy revenuecat.keys.local.json.example to revenuecat.keys.local.json and fill live keys."
  exit 1
fi

cd "$ROOT_DIR"
flutter build appbundle --release --dart-define-from-file="$KEY_FILE"
