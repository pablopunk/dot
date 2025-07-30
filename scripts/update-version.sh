#!/bin/bash

set -e # exit on error

# check $1 if it's a valid version number
if ! [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Invalid version number"
  echo "Usage: $0 <version>"
  echo "Example: $0 2.0.0"
  exit 1
fi

APP_VERSION="$1"

git checkout -b "$APP_VERSION"

git commit -m "bump version to $APP_VERSION"

git tag "$APP_VERSION"

git push origin "$APP_VERSION"

git push origin --tags

echo "Successfully updated version to $APP_VERSION"
echo "The new release should be automatically created on GitHub:"
echo "https://github.com/pablopunk/dot/releases"