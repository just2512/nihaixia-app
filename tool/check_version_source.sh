#!/usr/bin/env bash
set -euo pipefail

pub_version="$(sed -nE 's/^version:[[:space:]]*([^[:space:]]+).*/\\1/p' pubspec.yaml | head -n 1)"
readme_version="$(grep -m1 '当前仓库版本为' README.md | grep -oE '[0-9]+\\.[0-9]+\\.[0-9]+\\+[0-9]+')"
readme_source_version="$(grep -m1 '当前源码版本：' README.md | grep -oE '[0-9]+\\.[0-9]+\\.[0-9]+\\+[0-9]+')"
policy_version="$(grep -m1 '当前项目版本' docs/versioning-policy.md | grep -oE '[0-9]+\\.[0-9]+\\.[0-9]+\\+[0-9]+')"
legacy_build_baseline="$(grep -m1 '同 applicationId 已知最高 Android versionCode' docs/versioning-policy.md | grep -oE '[0-9]+')"

if [[ ! "$pub_version" =~ ^[0-9]+\\.[0-9]+\\.[0-9]+\\+[0-9]+$ ]]; then
  echo "pubspec.yaml must contain a version in X.Y.Z+N form; got: $pub_version" >&2
  exit 1
fi

if [[ -z "$readme_version" || -z "$readme_source_version" ]]; then
  echo "README.md must declare both the current repository version and current source version." >&2
  exit 1
fi

if [[ -z "$policy_version" ]]; then
  echo "docs/versioning-policy.md must declare the current project version." >&2
  exit 1
fi

if [[ ! "$legacy_build_baseline" =~ ^[0-9]+$ ]]; then
  echo "docs/versioning-policy.md must declare the known maximum Android versionCode for the shared applicationId." >&2
  exit 1
fi

if [[ "$readme_version" != "$pub_version" || "$readme_source_version" != "$pub_version" ]]; then
  echo "README versions ($readme_version / $readme_source_version) do not match pubspec version $pub_version." >&2
  exit 1
fi

if [[ "$policy_version" != "$pub_version" ]]; then
  echo "Version policy $policy_version does not match pubspec version $pub_version." >&2
  exit 1
fi

build_number="${pub_version##*+}"
if (( build_number <= legacy_build_baseline )); then
  echo "Android versionCode $build_number must be greater than the known shared-applicationId maximum $legacy_build_baseline." >&2
  exit 1
fi

echo "README, pubspec and independent version policy match: $pub_version (legacy Android versionCode baseline: $legacy_build_baseline)"
