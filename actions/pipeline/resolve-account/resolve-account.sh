#!/usr/bin/env bash
# Look up one leg's account, roles and state bucket, and build its state key.
# Env: DEPLOYMENTS_FILE, COMPONENT, ENVIRONMENT, DEPLOYMENT, TERRAFORM_DIR.
# Writes: account-id, plan-role-name, apply-role-name, state-bucket-name,
#         state-key (GITHUB_OUTPUT).
set -euo pipefail

key="${COMPONENT}/${ENVIRONMENT}/${DEPLOYMENT}"

# validate-deployments has checked the file; this guards a direct call.
entry="$(jq -c --arg k "${key}" '.[$k] // empty' "${DEPLOYMENTS_FILE}")"
if [[ -z "${entry}" || -z "$(jq -r '.account_id // ""' <<< "${entry}")" ]]; then
  echo "::error::deployments.json has no usable entry for '${key}'. Run validate-deployments to see why."
  exit 1
fi

account_id="$(jq -r '.account_id' <<< "${entry}")"
plan_role_name="$(jq -r '.plan_role_name' <<< "${entry}")"
apply_role_name="$(jq -r '.apply_role_name' <<< "${entry}")"
state_bucket_name="$(jq -r '.state_bucket_name' <<< "${entry}")"

# Prefixed with the repo name, so repos sharing a bucket can't collide. A
# non-default folder is added too, so folders in one repo can't collide.
prefix="${GITHUB_REPOSITORY##*/}"
if [[ "${TERRAFORM_DIR:-source/terraform}" != "source/terraform" ]]; then
  prefix="${prefix}/${TERRAFORM_DIR}"
fi
state_key="${prefix}/${key}/terraform.tfstate"

# Role and bucket names aren't secret; the account id is masked.
echo "::add-mask::${account_id}"
{
  echo "account-id=${account_id}"
  echo "plan-role-name=${plan_role_name}"
  echo "apply-role-name=${apply_role_name}"
  echo "state-bucket-name=${state_bucket_name}"
  echo "state-key=${state_key}"
} >> "${GITHUB_OUTPUT}"
