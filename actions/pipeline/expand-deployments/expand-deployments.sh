#!/usr/bin/env bash
# Expand component and deployment selectors into the leg matrix.
# Env: COMPONENT_INPUT, DEPLOYMENT_INPUT, ENVIRONMENT, COMPONENTS_DIR,
#      MISSING_ENVIRONMENT.
# Writes: include, skipped (GITHUB_OUTPUT).
set -euo pipefail

# Split comma selector $1 into the array named $2: trimmed, no empties, no
# duplicates, order kept. 'all' is handled by the caller.
parse_selector() {
  local input="$1"
  local -n out="$2"
  out=()
  local -A seen=()
  local IFS=','
  read -ra raw <<< "${input}"
  local item trimmed
  for item in "${raw[@]}"; do
    # Trim surrounding whitespace, so "a, b" works.
    trimmed="${item#"${item%%[![:space:]]*}"}"
    trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
    [[ -z "${trimmed}" ]] && continue
    [[ -n "${seen[${trimmed}]:-}" ]] && continue
    seen[${trimmed}]=1
    out+=("${trimmed}")
  done
}

# Subdirectories of $1.
list_components() {
  find "$1" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort
}

# tfvars basenames in $1.
list_deployments() {
  find "$1" -maxdepth 1 -type f -name '*.tfvars' -printf '%f\n' \
    | sed 's/\.tfvars$//' | sort
}

# Names become state keys and workspace names: lowercase, digits and hyphens.
# $2 is the kind, for the error message.
validate_name() {
  [[ "$1" =~ ^[a-z0-9-]+$ ]] && return 0
  case "$2" in
    component)
      echo "::error::invalid component name '$1' under '${COMPONENTS_DIR}': only deployable components belong in this folder (lowercase letters, digits and hyphens). Put shared Terraform code in source/terraform/modules/ instead."
      ;;
    *)
      echo "::error::invalid $2 name '$1': use lowercase letters, digits, and hyphens only."
      ;;
  esac
  exit 1
}

case "${MISSING_ENVIRONMENT}" in
  fail|skip) ;;
  *)
    echo "::error::invalid missing-environment '${MISSING_ENVIRONMENT}': use 'fail' or 'skip'."
    exit 1
    ;;
esac

if [[ "${COMPONENT_INPUT}" == "all" ]]; then
  mapfile -t components < <(list_components "${COMPONENTS_DIR}")
else
  parse_selector "${COMPONENT_INPUT}" components
fi
# A missing or empty components-dir, or an empty selector.
if [[ "${#components[@]}" -eq 0 ]]; then
  echo "::error::component selector '${COMPONENT_INPUT}' resolved to no components under '${COMPONENTS_DIR}'."
  exit 1
fi

include="[]"
skipped="[]"
for component in "${components[@]}"; do
  validate_name "${component}" component
  env_dir="${COMPONENTS_DIR}/${component}/environments/${ENVIRONMENT}"
  if [[ ! -d "${env_dir}" ]]; then
    if [[ "${MISSING_ENVIRONMENT}" == "skip" ]]; then
      echo "::notice::skipping component '${component}': no environment '${ENVIRONMENT}' (expected ${env_dir})."
      skipped="$(jq -c --arg s "${component}" '. += [$s]' <<< "${skipped}")"
      continue
    fi
    echo "::error::component '${component}' has no environment '${ENVIRONMENT}' (expected ${env_dir})."
    exit 1
  fi

  if [[ "${DEPLOYMENT_INPUT}" == "all" ]]; then
    mapfile -t deployments < <(list_deployments "${env_dir}")
  else
    parse_selector "${DEPLOYMENT_INPUT}" deployments
  fi
  if [[ "${#deployments[@]}" -eq 0 ]]; then
    echo "::error::no deployments (tfvars files) for component '${component}' in '${ENVIRONMENT}'."
    exit 1
  fi

  for dep in "${deployments[@]}"; do
    validate_name "${dep}" deployment
    # Catches a typo in an explicit selector; 'all' names come from real files.
    if [[ ! -f "${env_dir}/${dep}.tfvars" ]]; then
      echo "::error::deployment '${dep}' not found for component '${component}' in '${ENVIRONMENT}' (expected ${env_dir}/${dep}.tfvars)."
      exit 1
    fi
    include="$(jq -c --arg s "${component}" --arg d "${dep}" '. += [{component: $s, deployment: $d}]' <<< "${include}")"
  done
done

if [[ "${include}" == "[]" ]]; then
  echo "::error::no deployments remain for environment '${ENVIRONMENT}' after skipping components without it."
  exit 1
fi
echo "Resolved ${ENVIRONMENT} include-list: ${include}"
echo "include=${include}" >> "${GITHUB_OUTPUT}"
echo "skipped=${skipped}" >> "${GITHUB_OUTPUT}"
