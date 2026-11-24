#!/usr/bin/env bash
# Look up one leg's account, roles and state bucket, and build its state key.
# Env: DEPLOYMENTS_FILE, COMPONENT, ENVIRONMENT, DEPLOYMENT, STATE_PREFIX.
# Writes: account-id, plan-role-name, apply-role-name, state-bucket-name,
#         state-key, state-lock-table-name, state-use-lockfile (GITHUB_OUTPUT).
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

state_key="${STATE_PREFIX}/${key}/terraform.tfstate"
# S3-native locking unless the entry names a DynamoDB lock table, which is a
# fallback because Terraform has deprecated it. With a table, the lockfile is
# turned off, so each run takes one lock, not two.
state_lock_table_name="$(jq -r '.state_lock_table_name // ""' <<< "${entry}")"
state_use_lockfile="true"
if [[ -n "${state_lock_table_name}" ]]; then
  state_use_lockfile="false"
fi

# Role and bucket names aren't secret; the account id is masked.
echo "::add-mask::${account_id}"
{
  echo "account-id=${account_id}"
  echo "plan-role-name=${plan_role_name}"
  echo "apply-role-name=${apply_role_name}"
  echo "state-bucket-name=${state_bucket_name}"
  echo "state-key=${state_key}"
  echo "state-lock-table-name=${state_lock_table_name}"
  echo "state-use-lockfile=${state_use_lockfile}"
} >> "${GITHUB_OUTPUT}"
