#!/usr/bin/env bash
# List component and module directories that contain Terraform tests.
# Env: COMPONENTS_DIR, MODULES_DIR, COMPONENTS_FILTER, INCLUDE_MODULES.
# Writes: targets (GITHUB_OUTPUT).
set -euo pipefail
shopt -s nullglob
: "${COMPONENTS_DIR:?}" "${MODULES_DIR:?}" "${INCLUDE_MODULES:?}"

has_tests() {
  local files=("${1}"/*.tftest.hcl "${1}"/tests/*.tftest.hcl)
  [[ "${#files[@]}" -gt 0 ]]
}

targets='[]'
add_target() {
  targets="$(jq -c --arg name "${1}" --arg dir "${2}" '. + [{name: $name, dir: $dir}]' <<< "${targets}")"
}

# Component names to keep; null means all.
allowed='null'
if [[ -n "${COMPONENTS_FILTER// /}" ]]; then
  allowed="$(jq -c 'map(if type == "object" then .component else . end) | unique' <<< "${COMPONENTS_FILTER}")"
fi

components_dir="${COMPONENTS_DIR%/}"
if [[ -d "${components_dir}" ]]; then
  for d in "${components_dir}"/*/; do
    name="$(basename "${d}")"
    if [[ "${allowed}" != "null" ]] && ! jq -e --arg n "${name}" 'index($n) != null' <<< "${allowed}" > /dev/null; then
      continue
    fi
    if has_tests "${d%/}"; then
      add_target "${name}" "${d%/}"
    fi
  done
fi

modules_dir="${MODULES_DIR%/}"
if [[ "${INCLUDE_MODULES}" == "true" && -d "${modules_dir}" ]]; then
  for d in "${modules_dir}"/*/; do
    if has_tests "${d%/}"; then
      add_target "modules/$(basename "${d}")" "${d%/}"
    fi
  done
fi

targets="$(jq -c 'sort_by(.name)' <<< "${targets}")"
echo "Test targets: ${targets}"
echo "targets=${targets}" >> "${GITHUB_OUTPUT}"
