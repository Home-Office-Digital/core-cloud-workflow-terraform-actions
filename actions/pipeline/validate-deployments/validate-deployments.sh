#!/usr/bin/env bash
# Validate deployments.json as a whole: valid JSON, every entry complete, and
# entries matched 1:1 to tfvars files. An old state_lock_table_name gets a notice.
# Usage: validate-deployments.sh <deployments-file> <components-dir>
set -euo pipefail

# Fields every entry must have, non-empty.
REQUIRED_FIELDS=(
  account_id
  plan_role_name
  apply_role_name
  state_bucket_name
)

DEPLOYMENTS_FILE="${1:?deployments-file required}"
COMPONENTS_DIR="${2:?components-dir required}"

problems=()

# 1. The file is a JSON object.
if ! jq -e 'type == "object"' "${DEPLOYMENTS_FILE}" >/dev/null 2>&1; then
  echo "::error::${DEPLOYMENTS_FILE} is not valid JSON, or not a JSON object."
  exit 1
fi

# 2. Every entry is an object with every required field set.
required_json="$(jq -n '$ARGS.positional' --args "${REQUIRED_FIELDS[@]}")"
field_problems="$(
  jq -r --argjson required "${required_json}" '
    to_entries[]
    | .key as $k | .value as $v
    | if ($v | type) != "object"
      then "\($k): entry is not an object"
      else $required[] | select(($v[.] // "") == "") | "\($k): missing or empty field \(.)"
      end
  ' "${DEPLOYMENTS_FILE}"
)"
while IFS= read -r line; do
  [[ -n "${line}" ]] && problems+=("${line}")
done <<< "${field_problems}"

# 3. Entries and tfvars files match 1:1. Key <component>/<env>/<deployment>
#    maps to <components-dir>/<component>/environments/<env>/<deployment>.tfvars.
#    Only files at exactly that depth count, so tfvars elsewhere (tests/) are ignored.
entry_keys="$(jq -r 'keys[]' "${DEPLOYMENTS_FILE}")"
tfvars_keys="$(
  find "${COMPONENTS_DIR}" -mindepth 4 -maxdepth 4 -type f -path '*/environments/*/*.tfvars' 2>/dev/null \
    | sed -E "s#^${COMPONENTS_DIR}/([^/]+)/environments/([^/]+)/(.+)\.tfvars\$#\1/\2/\3#"
)"

# Turn each newline-separated key list into a JSON array (drops blank lines).
entries_json="$(jq -Rn '[inputs | select(length > 0)]' <<< "${entry_keys}")"
tfvars_json="$(jq -Rn '[inputs | select(length > 0)]' <<< "${tfvars_keys}")"

# Set-difference each way: entries with no tfvars, and tfvars with no entry.
while IFS= read -r line; do
  [[ -n "${line}" ]] && problems+=("${line}")
done < <(
  jq -rn --argjson entries "${entries_json}" --argjson tfvars "${tfvars_json}" '
    ($entries - $tfvars | map("entry \(.) has no matching tfvars file"))
    + ($tfvars - $entries | map("tfvars \(.).tfvars has no deployments.json entry"))
    | .[]
  '
)

# 4. state_lock_table_name is unused with S3 locking: notice only.
while IFS= read -r k; do
  [[ -n "${k}" ]] && echo "::notice::${k}: state_lock_table_name is ignored because state locking uses S3 (use_lockfile); it can be removed."
done < <(jq -r 'to_entries[] | select((.value | type) == "object" and (.value | has("state_lock_table_name"))) | .key' "${DEPLOYMENTS_FILE}")

if [[ "${#problems[@]}" -gt 0 ]]; then
  echo "::error::deployments.json is invalid:"
  for p in "${problems[@]}"; do echo "::error::  ${p}"; done
  exit 1
fi
echo "deployments.json is valid: all entries complete and matched to tfvars."
