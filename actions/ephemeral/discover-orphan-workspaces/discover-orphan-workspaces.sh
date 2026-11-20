#!/usr/bin/env bash
# List the pr-* workspaces to destroy for a scope.
# Env: SCOPE, ENVIRONMENT, COMPONENTS_DIR, DEPLOYMENTS_FILE, STATE_REGION, REPO,
#      GH_TOKEN.
# Writes: workspaces, one '<component> <deployment> <workspace>' per line
#         (GITHUB_OUTPUT).
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -f "${DEPLOYMENTS_FILE}" ]]; then
  echo "::error::deployments file not found at '${DEPLOYMENTS_FILE}'."
  exit 1
fi

if [[ "${SCOPE}" != "all" && ! "${SCOPE}" =~ ^pr-[0-9]+$ ]]; then
  echo "::error::scope must be 'all' or 'pr-<number>'; got '${SCOPE}'."
  exit 1
fi

# Destroy decision per PR number, so gh is called once per PR.
declare -A pr_destroy=()

# True when a workspace belonging to PR $1 should be destroyed.
in_scope() {
  local pr="$1"
  if [[ "${SCOPE}" == pr-* ]]; then
    [[ "pr-${pr}" == "${SCOPE}" ]]
    return
  fi
  # scope=all: closed or merged PRs only. Keep the workspaces if the PR can't be read.
  if [[ -z "${pr_destroy[$pr]:-}" ]]; then
    local state
    pr_destroy[$pr]=no
    if state="$(gh pr view "${pr}" --repo "${REPO}" --json state --jq '.state' 2>/dev/null)"; then
      if [[ "${state}" == "CLOSED" || "${state}" == "MERGED" ]]; then
        pr_destroy[$pr]=yes
      fi
    else
      echo "::warning::could not read PR ${pr}; keeping its workspaces."
    fi
  fi
  [[ "${pr_destroy[$pr]}" == "yes" ]]
}

out=""
for dir in "${COMPONENTS_DIR}"/*/; do
  [[ -d "${dir}" ]] || continue
  component="$(basename "${dir}")"
  env_dir="${dir}environments/${ENVIRONMENT}"
  [[ -d "${env_dir}" ]] || continue

  # Workspaces are listed per state key, so init each deployment's key.
  for tfvars in "${env_dir}"/*.tfvars; do
    [[ -e "${tfvars}" ]] || continue
    deployment="$(basename "${tfvars}" .tfvars)"

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
    creds="$("${script_dir}/../assume-leg-role.sh" "${account}" "${apply_role_name}" discover)"
    IFS=$'\t' read -r AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN <<< "${creds}"
    export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN

    # Same state key and workspace prefix as the deploy workflow.
    terraform -chdir="${dir}" init -input=false \
      -backend-config="bucket=${state_bucket_name}" \
      -backend-config="key=${GITHUB_REPOSITORY##*/}/${component}/${ENVIRONMENT}/${deployment}/terraform.tfstate" \
      -backend-config="region=${STATE_REGION}" \
      -backend-config="workspace_key_prefix=env:${GITHUB_REPOSITORY##*/}" \
      -backend-config="use_lockfile=true" \
      -backend-config="encrypt=true" \
      -reconfigure >/dev/null

    # Captured first, so a failed list aborts instead of reading as empty.
    # sed strips the "* " marker on the selected workspace.
    ws_list="$(terraform -chdir="${dir}" workspace list | sed 's/^[* ]*//')"

    while IFS= read -r ws; do
      [[ "${ws}" =~ ^pr-([0-9]+)-${deployment}$ ]] || continue
      in_scope "${BASH_REMATCH[1]}" || continue
      out+="${component} ${deployment} ${ws}"$'\n'
    done <<< "${ws_list}"
  done
done

out="${out%$'\n'}"
echo "Workspaces to destroy (${SCOPE}):"
echo "${out:-  (none)}"
{
  echo "workspaces<<EOF"
  echo "${out}"
  echo "EOF"
} >> "${GITHUB_OUTPUT}"
