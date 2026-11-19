#!/usr/bin/env bash
# Point git at the module token for github.com URLs, for the rest of the job.
# Env: APP_TOKEN, CUSTOM_GITHUB_TOKEN.
# Writes: GIT_CONFIG_* (GITHUB_ENV).
set -euo pipefail
token="${APP_TOKEN:-${CUSTOM_GITHUB_TOKEN}}"
echo "::add-mask::${token}"
base="https://x-access-token:${token}@github.com/"
# Appends after any GIT_CONFIG_* entries already set in the job.
n="${GIT_CONFIG_COUNT:-0}"
{
  for from in "https://github.com/" "ssh://git@github.com/" "git@github.com:"; do
    echo "GIT_CONFIG_KEY_${n}=url.${base}.insteadOf"
    echo "GIT_CONFIG_VALUE_${n}=${from}"
    n=$((n + 1))
  done
  echo "GIT_CONFIG_COUNT=${n}"
} >> "${GITHUB_ENV}"
if [[ -n "${APP_TOKEN}" ]]; then
  echo "git configured for github.com with the GitHub App token."
else
  echo "git configured for github.com with git_auth_token."
fi
