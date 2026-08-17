#!/bin/sh
set -eu

app_path=${1:?usage: create-dmg.sh /path/to/App.app /path/to/output.dmg}
dmg_path=${2:?usage: create-dmg.sh /path/to/App.app /path/to/output.dmg}
staging_dir=$(mktemp -d)

cleanup() {
  rm -r "$staging_dir"
}
trap cleanup EXIT

ditto "$app_path" "$staging_dir/Just Speak.app"
ln -s /Applications "$staging_dir/Applications"
mkdir -p "$(dirname "$dmg_path")"
hdiutil create \
  -quiet \
  -volname "Just Speak" \
  -srcfolder "$staging_dir" \
  -format UDZO \
  -ov \
  "$dmg_path"
