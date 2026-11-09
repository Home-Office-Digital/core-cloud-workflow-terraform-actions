#!/usr/bin/env bash
# Assume a deployment leg's AWS account role via GitHub OIDC and print the
# session credentials as three tab-separated fields:
#   <access-key-id>\t<secret-access-key>\t<session-token>
#
# Shared by the ephemeral discover and destroy actions, which each loop over
# legs that may live in different accounts. A composite `uses:` step can't run
# inside a bash loop, so per-leg auth calls this from the loop instead of using
# aws-actions/configure-aws-credentials. It mints a fresh OIDC token per call
# (assume-role-with-web-identity), since the token is short-lived (~10 min) and
# a scan can run longer.
#
# Usage:  assume-leg-role.sh <account-id> <role-name> [session-name]
# Needs:  ACTIONS_ID_TOKEN_REQUEST_URL and ACTIONS_ID_TOKEN_REQUEST_TOKEN in the
#         environment (present when the job has `id-token: write`).
set -euo pipefail

account="${1:?account id required}"
role="${2:?role name required}"
session="${3:-leg}"

if [[ -z "${ACTIONS_ID_TOKEN_REQUEST_URL:-}" || -z "${ACTIONS_ID_TOKEN_REQUEST_TOKEN:-}" ]]; then
  echo "::error::OIDC token request vars missing; the job needs 'id-token: write'." >&2
  exit 1
fi

oidc_token="$(curl -sS \
  -H "Authorization: bearer ${ACTIONS_ID_TOKEN_REQUEST_TOKEN}" \
  "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=sts.amazonaws.com" \
  | jq -r '.value')"

aws sts assume-role-with-web-identity \
  --role-arn "arn:aws:iam::${account}:role/${role}" \
  --role-session-name "${session}" \
  --web-identity-token "${oidc_token}" \
  --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' --output text
