#!/bin/bash

set -e # exit on error

# check $1 if it's a valid version number
if ! [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Invalid version number"
  echo "Usage: $0 <version>"
  echo "Example: $0 2.0.0"
  exit 1
fi

# Check if we're on main
if [ "$(git rev-parse --abbrev-ref HEAD)" != "main" ]; then
  echo "Not on main branch"
  exit 1
fi

# Check if git status is clean
if git status --porcelain | grep -q '^[MADRCU]'; then
  echo "Git status is not clean"
  exit 1
fi

APP_VERSION="$1"

# replace version in dot.lua
sed -i '' "s/version = \".*\"/version = \"$APP_VERSION\"/g" dot.lua

version=$(./dot.lua --version)
if [ "$version" != "dot version $APP_VERSION" ]; then
  echo "Version in dot.lua does not match $APP_VERSION"
  exit 1
fi

set -x

git add dot.lua
git commit -m "bump version to $APP_VERSION"
git tag "$APP_VERSION"
git push
git push --tags

set +x

echo
echo "Successfully updated version to $APP_VERSION"
echo "The new release should be automatically created on GitHub:"
echo "https://github.com/pablopunk/dot/releases"
echo