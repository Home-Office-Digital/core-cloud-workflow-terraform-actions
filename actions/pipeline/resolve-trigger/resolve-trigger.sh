#!/usr/bin/env bash
# Map the triggering event to a mode, environment, version and ephemeral flag,
# or to a skip.
# Env: EVENT_NAME, EVENT_PATH (default GITHUB_EVENT_PATH), INPUT_ENVIRONMENT,
#      INPUT_VERSION, INPUT_EPHEMERAL, DEVELOPMENT_ENVIRONMENT,
#      PRE_RELEASE_ENVIRONMENT, RELEASE_ENVIRONMENT.
# Writes: mode, skip, environment, version, ephemeral (GITHUB_OUTPUT).
#
# Event values are untrusted: never evaluated, and rejected if they contain a
# line break.
set -euo pipefail

event_name="${EVENT_NAME:-}"
event_path="${EVENT_PATH:-}"
if [[ -z "${event_path}" ]]; then
  event_path="${GITHUB_EVENT_PATH:-}"
fi

mode=""
skip="true"
environment=""
version=""
ephemeral=""

fail() {
  printf 'resolve-trigger: %s\n' "$1" >&2
  exit 1
}

# Fail when a value contains a newline or carriage return.
reject_newlines() {
  local name="$1" value="$2"
  case "${value}" in
    *$'\n'* | *$'\r'*) fail "value for '${name}' contains a line break" ;;
  esac
}

# Read one field from the payload as a raw string; null and missing become "".
payload_field() {
  local filter="$1"
  [[ -n "${event_path}" && -r "${event_path}" ]] || fail "event payload not readable: '${event_path}'"
  jq -r "${filter} // empty | tostring" "${event_path}"
}

case "${event_name}" in
  workflow_dispatch)
    mode="dispatch"
    skip="false"
    environment="${INPUT_ENVIRONMENT:-}"
    version="${INPUT_VERSION:-}"
    ephemeral="${INPUT_EPHEMERAL:-}"
    if [[ -z "${ephemeral}" ]]; then
      ephemeral="false"
    fi
    ;;

  push)
    mode="push"
    ref="$(payload_field '.ref')"
    after="$(payload_field '.after')"
    deleted="$(payload_field '.deleted')"
    default_branch="$(payload_field '.repository.default_branch')"
    reject_newlines "ref" "${ref}"
    reject_newlines "after" "${after}"
    reject_newlines "default_branch" "${default_branch}"
    if [[ -n "${default_branch}" \
      && "${ref}" == "refs/heads/${default_branch}" \
      && "${deleted}" != "true" \
      && -n "${after}" \
      && -n "${DEVELOPMENT_ENVIRONMENT:-}" ]]; then
      skip="false"
      environment="${DEVELOPMENT_ENVIRONMENT}"
      version="${after}"
      ephemeral="false"
    fi
    ;;

  release)
    mode="release"
    action="$(payload_field '.action')"
    prerelease="$(payload_field '.release.prerelease')"
    tag_name="$(payload_field '.release.tag_name')"
    reject_newlines "action" "${action}"
    reject_newlines "tag_name" "${tag_name}"
    target=""
    if [[ "${action}" == "published" && "${prerelease}" == "true" ]]; then
      target="${PRE_RELEASE_ENVIRONMENT:-}"
    elif [[ "${action}" == "released" ]]; then
      target="${RELEASE_ENVIRONMENT:-}"
    fi
    if [[ -n "${target}" && -n "${tag_name}" ]]; then
      skip="false"
      environment="${target}"
      version="${tag_name}"
      ephemeral="false"
    fi
    ;;

  *)
    mode=""
    skip="true"
    ;;
esac

reject_newlines "environment" "${environment}"
reject_newlines "version" "${version}"
reject_newlines "ephemeral" "${ephemeral}"

if [[ "${skip}" == "false" && ! "${environment}" =~ ^[a-z0-9-]+$ ]]; then
  fail "invalid environment name '${environment}': use lowercase letters, digits and hyphens (it is used in folder names, state keys and the GitHub Environment name)."
fi

[[ -n "${GITHUB_OUTPUT:-}" ]] || fail "GITHUB_OUTPUT is not set"

{
  printf '%s=%s\n' mode "${mode}"
  printf '%s=%s\n' skip "${skip}"
  printf '%s=%s\n' environment "${environment}"
  printf '%s=%s\n' version "${version}"
  printf '%s=%s\n' ephemeral "${ephemeral}"
} >> "${GITHUB_OUTPUT}"
