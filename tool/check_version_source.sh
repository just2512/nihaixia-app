#!/usr/bin/env bash
set -euo pipefail

pub_version="$(sed -nE 's/^version:[[:space:]]*([^[:space:]]+).*/\1/p' pubspec.yaml | head -n 1)"
readme_version="$(sed -nE 's/.*当前仓库版本为 `([^`]+)`.*/\\1/p' README.md | head -n 1)"

if [[ ! "$pub_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+$ ]]; then
  echo "pubspec.yaml must contain a version in X.Y.Z+N form; got: $pub_version" >&2
  exit 1
fi

if [[ -z "$readme_version" ]]; then
  echo "README.md must declare the current repository version next to the pubspec version policy." >&2
  exit 1
fi

if [[ "$readme_version" != "$pub_version" ]]; then
  echo "README version $readme_version does not match pubspec version $pub_version." >&2
  exit 1
fi

echo "README and pubspec version source match: $pub_version"
