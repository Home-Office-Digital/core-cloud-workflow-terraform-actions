#!/usr/bin/env bash
# Reject a version other than main, master or a semver tag.
# Env: ENVIRONMENT, VERSION.
set -euo pipefail
pattern='^(main|master|v?[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?)$'
if [[ ! "${VERSION}" =~ ${pattern} ]]; then
  echo "::error::${ENVIRONMENT} deployment rejected: version must be main, master, or a semver tag (v1.2.3, 1.2.3, or with a pre-release suffix such as v1.2.3-rc.1); got '${VERSION}'."
  exit 1
fi
