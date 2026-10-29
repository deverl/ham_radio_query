#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if ! xcodebuild -scheme HamRadioQuery -configuration Release -derivedDataPath build build; then
    echo "Build failed. HamRadioQuery.app was not replaced." >&2
    exit 1
fi

built="build/Build/Products/Release/HamRadioQuery.app"
if [[ ! -d "$built" ]]; then
    echo "Build finished without producing $built. HamRadioQuery.app was not replaced." >&2
    exit 1
fi

rm -rf HamRadioQuery.app
ditto "$built" HamRadioQuery.app


