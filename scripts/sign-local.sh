#!/bin/sh
set -eu

# macOS permission grants are more stable across rebuilds when the app keeps a
# certificate-backed code identity. Resolve an available Apple signing identity
# at build time so contributors never need to put account details in the repo.

find_local_signing_identity() {
  security find-identity -v -p codesigning 2>/dev/null |
    awk '
      index($0, "\"Developer ID Application: ") &&
      length($2) == 40 &&
      $2 ~ /^[[:xdigit:]]+$/ {
        found = 1
        print $2
        exit
      }
      index($0, "\"Apple Development: ") &&
      length($2) == 40 &&
      $2 ~ /^[[:xdigit:]]+$/ && !development {
        development = $2
      }
      END { if (!found && development) print development }
    '
}

app_path=${1:?usage: sign-local.sh /path/to/App.app}
identity=$(find_local_signing_identity)

if [ -z "$identity" ]; then
  echo "Local signing: no Apple certificate found; keeping the ad-hoc signature." >&2
  echo "Microphone and Accessibility permissions may be requested again after rebuilds." >&2
  exit 0
fi

echo "Local signing: using an Apple certificate (identity redacted)."
codesign --force \
  --deep \
  --sign "$identity" \
  --preserve-metadata=identifier,entitlements,flags \
  --timestamp=none \
  "$app_path"
