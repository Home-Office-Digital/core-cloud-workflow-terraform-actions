#!/usr/bin/env bash
# Append a readable deploy-run summary to GITHUB_STEP_SUMMARY.
#
# Inputs (environment variables, all optional):
#   MODE, SKIP, ENVIRONMENT, VERSION, EPHEMERAL, PR_NUMBER, PLAN_ONLY, INCLUDE
#   (JSON), SKIPPED (JSON), JOB_STATUS, EVENT_NAME, EVENT_ACTION, PRERELEASE,
#   REF_NAME, ACTOR, SERVER_URL, REPOSITORY
#
# Free-text values are untrusted. They are never evaluated; line breaks become
# spaces, '|' is escaped and backticks become apostrophes so a value cannot
# break out of a table cell or code span.
set -euo pipefail
summary="${GITHUB_STEP_SUMMARY:?GITHUB_STEP_SUMMARY is not set}"

# Make a value safe for a Markdown table cell or code span.
clean() {
  printf '%s' "${1:-}" | tr '\r\n`' "  '" | sed 's/|/\\|/g'
}

mode="$(clean "${MODE:-}")"
environment="$(clean "${ENVIRONMENT:-}")"
version="$(clean "${VERSION:-}")"
pr_number="$(clean "${PR_NUMBER:-}")"
event_name="$(clean "${EVENT_NAME:-}")"
event_action="$(clean "${EVENT_ACTION:-}")"
ref_name="$(clean "${REF_NAME:-}")"
actor="$(clean "${ACTOR:-}")"
server_url="$(clean "${SERVER_URL:-}")"
repository="$(clean "${REPOSITORY:-}")"
skip="${SKIP:-}"
job_status="${JOB_STATUS:-}"

# Skipped run: the event does not deploy.
if [[ "${skip}" == "true" ]]; then
  what="\`${event_name:-event}\`"
  if [[ "${event_name}" == "push" ]]; then
    what="Push to \`${ref_name}\`"
  else
    detail=""
    if [[ -n "${event_action}" ]]; then
      detail="\`${event_action}\`"
    fi
    if [[ "${event_name}" == "release" ]]; then
      kind="stable release"
      if [[ "${PRERELEASE:-}" == "true" ]]; then
        kind="pre-release"
      fi
      detail="${detail:+${detail}, }${kind}"
    fi
    if [[ -n "${detail}" ]]; then
      what="${what} (${detail})"
    fi
  fi
  {
    echo "### Deploy run: skipped"
    echo
    echo "${what} doesn't deploy. Nothing was checked out, planned or applied."
  } >> "${summary}"
  exit 0
fi

{
  if [[ "${job_status}" != "success" ]]; then
    echo "### Deploy run: stopped"
    echo
    echo "Preflight failed before planning. Check the failed step in the **preflight** job."
  else
    echo "### Deploy run"
  fi
  echo
  echo "| Item | Value |"
  echo "| --- | --- |"

  trigger="\`${event_name:-unknown}\`"
  if [[ -n "${event_action}" ]]; then
    trigger="${trigger} / \`${event_action}\`"
  fi
  if [[ -n "${actor}" ]]; then
    trigger="${trigger} by @${actor}"
  fi
  echo "| Trigger | ${trigger} |"

  if [[ -n "${environment}" ]]; then
    echo "| Environment | \`${environment}\` |"
  fi

  if [[ -n "${version}" ]]; then
    if [[ "${mode}" == "push" ]]; then
      short="${version:0:12}"
      if [[ -n "${server_url}" && -n "${repository}" ]]; then
        echo "| Version | [\`${short}\`](${server_url}/${repository}/commit/${version}) |"
      else
        echo "| Version | \`${short}\` |"
      fi
    else
      echo "| Version | \`${version}\` |"
    fi
  fi

  if [[ -n "${environment}" ]]; then
    if [[ "${PLAN_ONLY:-}" == "true" ]]; then
      echo "| Mode | plan only, no apply |"
    else
      echo "| Mode | plan and apply (approval required in \`${environment}\`) |"
    fi
  fi

  if [[ "${EPHEMERAL:-}" == "true" ]]; then
    if [[ "${pr_number}" =~ ^[0-9]+$ && -n "${server_url}" && -n "${repository}" ]]; then
      pr="[#${pr_number}](${server_url}/${repository}/pull/${pr_number})"
    elif [[ -n "${pr_number}" ]]; then
      pr="#${pr_number}"
    else
      pr="unknown"
    fi
    echo "| Ephemeral | yes, PR ${pr}, workspaces \`pr-${pr_number}-<deployment>\` |"
  elif [[ -n "${environment}" ]]; then
    echo "| Ephemeral | no |"
  fi

  # Deployments: include is a JSON array of {component, deployment}.
  include="${INCLUDE:-}"
  count=0
  if [[ -n "${include}" ]] && jq -e 'type == "array"' <<< "${include}" > /dev/null 2>&1; then
    count="$(jq 'length' <<< "${include}")"
  fi
  echo
  if [[ "${count}" -gt 0 ]]; then
    echo "#### Deployments (${count})"
    echo
    echo "| Component | Deployment |"
    echo "| --- | --- |"
    jq -r '.[] | "| `\(.component | tostring | gsub("[`|\n\r]"; ""))` | `\(.deployment | tostring | gsub("[`|\n\r]"; ""))` |"' <<< "${include}"
  else
    echo "#### Deployments (0)"
    echo
    echo "No deployments listed."
  fi

  # Components dropped for lacking this environment.
  skipped="${SKIPPED:-}"
  if [[ -n "${skipped}" ]] && jq -e 'type == "array" and length > 0' <<< "${skipped}" > /dev/null 2>&1; then
    names="$(jq -r 'map("`" + (tostring | gsub("[`|\n\r]"; "")) + "`") | join(", ")' <<< "${skipped}")"
    echo
    echo "Skipped (no \`${environment}\` environment): ${names}"
  fi
} >> "${summary}"
