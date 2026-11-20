#!/usr/bin/env bash
# Assume a leg's AWS role with GitHub OIDC and print the credentials as
# <access-key-id>\t<secret-access-key>\t<session-token>.
# Usage: assume-leg-role.sh <account-id> <role-name> [session-name]
# Env: ACTIONS_ID_TOKEN_REQUEST_URL, ACTIONS_ID_TOKEN_REQUEST_TOKEN (set when the
#      job has id-token: write).
#
# Discover and destroy loop over legs in different accounts, and a `uses:` step
# such as configure-aws-credentials can't run inside a loop. Each call mints a
# fresh OIDC token, because a long loop can outlast one.
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
