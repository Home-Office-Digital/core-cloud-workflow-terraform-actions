#!/usr/bin/env bash
# Destroy and delete each listed pr-* workspace.
# Env: WORKSPACES, DEPLOYMENTS_FILE, ENVIRONMENT, COMPONENTS_DIR, AWS_REGION,
#      STATE_PREFIX.
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -f "${DEPLOYMENTS_FILE}" ]]; then
  echo "::error::deployments file not found at '${DEPLOYMENTS_FILE}'."
  exit 1
fi

while read -r component deployment workspace; do
  [[ -z "${component}" ]] && continue
  echo "::group::destroy ${component}/${deployment}/${workspace}"
  dir="${COMPONENTS_DIR}/${component}"

  # validate-deployments has checked the file; this guards a direct call.
  key="${component}/${ENVIRONMENT}/${deployment}"
  entry="$(jq -c --arg k "${key}" '.[$k] // empty' "${DEPLOYMENTS_FILE}")"
  if [[ -z "${entry}" || -z "$(jq -r '.account_id // ""' <<< "${entry}")" ]]; then
    echo "::error::deployments.json has no usable entry for ${key}. Run validate-deployments to see why."
    exit 1
  fi
  account="$(jq -r '.account_id' <<< "${entry}")"
  apply_role_name="$(jq -r '.apply_role_name' <<< "${entry}")"
  state_bucket_name="$(jq -r '.state_bucket_name' <<< "${entry}")"

  # Each leg can be in a different account. Clear the previous leg's credentials.
  # Captured first, so a failed assume-role stops the script instead of leaving
  # the credentials empty.
  unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
  creds="$("${script_dir}/../assume-leg-role.sh" "${account}" "${apply_role_name}" cleanup)"
  IFS=$'\t' read -r AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN <<< "${creds}"
  export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN

  # Same state key, workspace prefix and locking as the deploy workflow.
  lock_table="$(jq -r '.state_lock_table_name // ""' <<< "${entry}")"
  backend_config=(
    -backend-config="bucket=${state_bucket_name}"
    -backend-config="key=${STATE_PREFIX}/${component}/${ENVIRONMENT}/${deployment}/terraform.tfstate"
    -backend-config="region=${AWS_REGION}"
    -backend-config="workspace_key_prefix=env:${GITHUB_REPOSITORY##*/}"
    -backend-config="encrypt=true"
  )
  if [[ -n "${lock_table}" ]]; then
    backend_config+=(-backend-config="dynamodb_table=${lock_table}" -backend-config="use_lockfile=false")
  else
    backend_config+=(-backend-config="use_lockfile=true")
  fi
  terraform -chdir="${dir}" init -input=false "${backend_config[@]}" -reconfigure

  terraform -chdir="${dir}" workspace select "${workspace}"
  terraform -chdir="${dir}" destroy -auto-approve -input=false \
    -var-file="environments/${ENVIRONMENT}/${deployment}.tfvars"

  # Terraform can't delete the selected workspace.
  terraform -chdir="${dir}" workspace select default
  terraform -chdir="${dir}" workspace delete "${workspace}"
  echo "::endgroup::"
done <<< "${WORKSPACES}"
