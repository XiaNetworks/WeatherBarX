#!/usr/bin/env bash

set -euo pipefail

VERSION="${1:-}"

if [ -z "${VERSION}" ]; then
  echo "usage: $0 <version>" >&2
  exit 1
fi

APP_NAME="WeatherBarX"
PROJECT="WeatherBarX.xcodeproj"
SCHEME="WeatherBarX"
CONFIGURATION="Release"
DERIVED_DATA="${RUNNER_TEMP:-/tmp}/${APP_NAME}ReleaseDerivedData"
APP_PATH="${DERIVED_DATA}/Build/Products/${CONFIGURATION}/${APP_NAME}.app"
DIST_DIR="dist"
ZIP_PATH="${DIST_DIR}/${APP_NAME}.zip"

rm -rf "${DERIVED_DATA}" "${DIST_DIR}"
mkdir -p "${DIST_DIR}"

xcodebuild \
  -project "${PROJECT}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -derivedDataPath "${DERIVED_DATA}" \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  MARKETING_VERSION="${VERSION}" \
  build

ditto -c -k --sequesterRsrc --keepParent "${APP_PATH}" "${ZIP_PATH}"
shasum -a 256 "${ZIP_PATH}" | awk '{print $1}' > "${ZIP_PATH}.sha256"
