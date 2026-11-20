#!/usr/bin/env bash
# Fail unless the GitHub Environment exists with a required-reviewers rule.
# Env: ENVIRONMENT, REPO, GH_TOKEN.
set -euo pipefail
err="$(mktemp)"
trap 'rm -f "${err}"' EXIT

# Slashes in an environment name must be encoded in the API path.
enc="${ENVIRONMENT//\//%2F}"
if ! body="$(gh api "repos/${REPO}/environments/${enc}" 2> "${err}")"; then
  if grep -qi 'Not Found' "${err}"; then
    echo "::error::environment '${ENVIRONMENT}' is not configured in ${REPO}. GitHub would auto-create it ungated, so the apply approval gate would not apply. Create it with a required-reviewers rule before deploying."
    exit 1
  fi
  echo "::error::could not read environment '${ENVIRONMENT}': $(cat "${err}")"
  exit 1
fi
if [[ "$(jq '[.protection_rules[]? | select(.type == "required_reviewers")] | length' <<< "${body}")" -eq 0 ]]; then
  echo "::error::environment '${ENVIRONMENT}' has no required-reviewers protection rule, so the apply would run ungated. Add required reviewers to the environment before deploying."
  exit 1
fi
echo "environment '${ENVIRONMENT}' has a required-reviewers gate."
