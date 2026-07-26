#!/bin/sh
set -eu

app_path=${1:?usage: verify-local-signing.sh /path/to/App.app}

codesign --verify --deep --strict "$app_path"

if codesign -dvv "$app_path" 2>&1 | grep -q '^Authority='; then
  echo "Local signing: certificate-backed app signature verified."
  exit 0
fi

echo "Local signing: ad-hoc app signature verified." >&2
