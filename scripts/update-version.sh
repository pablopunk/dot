#!/bin/bash

set -e # exit on error

function green() {
  echo -e "\033[32m$1\033[0m"
}

function red() {
  echo -e "\033[31m$1\033[0m"
}

# check $1 if it's a valid version number
if ! [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  red "Invalid version number"
  echo "Usage: $0 <version>"
  echo "Example: $0 2.0.0"
  exit 1
fi

# Check if we're on main
if [ "$(git rev-parse --abbrev-ref HEAD)" != "main" ]; then
  red "Not on main branch"
  exit 1
fi

# Check if git status is clean
if git status --porcelain | grep -q '^[MADRCU]'; then
  red "Git status is not clean"
  exit 1
fi

APP_VERSION="$1"

# replace version in dot.lua
sed -i '' "s/version = \".*\"/version = \"$APP_VERSION\"/g" dot.lua

version=$(./dot.lua --version)
if [ "$version" != "dot version $APP_VERSION" ]; then
  red "Version in dot.lua does not match $APP_VERSION"
  exit 1
fi

set -x

git add dot.lua
git commit -m "bump version to $APP_VERSION"
git tag "$APP_VERSION"
git push
git push --tags

set +x

green
green "Successfully updated version to $APP_VERSION"
green "The new release should be automatically created on GitHub:"
green "https://github.com/pablopunk/dot/releases"
green
