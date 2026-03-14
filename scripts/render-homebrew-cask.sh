#!/usr/bin/env bash

set -euo pipefail

VERSION="${1:-}"
SHA256="${2:-}"
URL="${3:-}"

if [ -z "${VERSION}" ] || [ -z "${SHA256}" ] || [ -z "${URL}" ]; then
  echo "usage: $0 <version> <sha256> <url>" >&2
  exit 1
fi

cat <<EOF
cask "weatherbarx" do
  version "${VERSION}"
  sha256 "${SHA256}"

  url "${URL}"
  name "WeatherBarX"
  desc "Menu bar weather app for macOS"
  homepage "https://github.com/XiaNetworks/WeatherBarX"

  app "WeatherBarX.app"
end
EOF
