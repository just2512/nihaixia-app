#!/usr/bin/env bash
set -euo pipefail

pub_version="$(sed -nE 's/^version:[[:space:]]*([^[:space:]]+).*/\1/p' pubspec.yaml | head -n 1)"
readme_version="$(sed -nE 's/.*当前仓库版本为 `([^ `]+)`.*/\1/p' README.md | head -n 1)"
policy_version="$(sed -nE 's/^\*\*当前项目版本\*\*：[[:space:]]*`([^`]+)`.*/\1/p' docs/versioning-policy.md | head -n 1)"
legacy_build_baseline="$(sed -nE 's/^\*\*独立版本切换前最高 Android versionCode\*\*：[[:space:]]*`([0-9]+)`.*/\1/p' docs/versioning-policy.md | head -n 1)"

if [[ ! "$pub_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+$ ]]; then
  echo "pubspec.yaml must contain a version in X.Y.Z+N form; got: $pub_version" >&2
  exit 1
fi

if [[ -z "$readme_version" ]]; then
  echo "README.md must declare the current repository version next to the version policy." >&2
  exit 1
fi

if [[ -z "$policy_version" ]]; then
  echo "docs/versioning-policy.md must declare the current project version." >&2
  exit 1
fi

if [[ ! "$legacy_build_baseline" =~ ^[0-9]+$ ]]; then
  echo "docs/versioning-policy.md must declare the previous Android versionCode baseline." >&2
  exit 1
fi

if [[ "$readme_version" != "$pub_version" ]]; then
  echo "README version $readme_version does not match pubspec version $pub_version." >&2
  exit 1
fi

if [[ "$policy_version" != "$pub_version" ]]; then
  echo "Version policy $policy_version does not match pubspec version $pub_version." >&2
  exit 1
fi

build_number="${pub_version##*+}"
if (( build_number <= legacy_build_baseline )); then
  echo "Android versionCode $build_number must be greater than the legacy baseline $legacy_build_baseline." >&2
  exit 1
fi

echo "README, pubspec and independent version policy match: $pub_version (legacy Android versionCode baseline: $legacy_build_baseline)"
