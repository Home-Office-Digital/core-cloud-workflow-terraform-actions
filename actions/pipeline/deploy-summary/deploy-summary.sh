#!/usr/bin/env bash
# Append a short deploy-run summary to GITHUB_STEP_SUMMARY.
# Env (all optional): SKIP, ENVIRONMENT, VERSION, EPHEMERAL, PR_NUMBER, PLAN_ONLY,
#      INCLUDE (JSON), JOB_STATUS, EVENT_NAME, EVENT_ACTION, PRERELEASE.
#
# Values are never evaluated. Backticks are removed and line breaks become
# spaces, so a value can't break out of a code span or list item.
set -euo pipefail
summary="${GITHUB_STEP_SUMMARY:?GITHUB_STEP_SUMMARY is not set}"

clean() {
  printf '%s' "${1:-}" | tr -d '`\r' | tr '\n' ' '
}

environment="$(clean "${ENVIRONMENT:-}")"
version="$(clean "${VERSION:-}")"
event="$(clean "${EVENT_NAME:-}")"
action="$(clean "${EVENT_ACTION:-}")"

{
  if [[ "${SKIP:-}" == "true" ]]; then
    echo "### Deploy: skipped"
    if [[ "${event}" == "release" && "${action}" == "published" && "${PRERELEASE:-}" != "true" ]]; then
      echo "A stable release fires \`published\` and \`released\`; only \`released\` deploys."
    elif [[ -n "${event}" ]]; then
      echo "\`${event}\` doesn't deploy."
    else
      echo "This event doesn't deploy."
    fi
  else
    if [[ "${JOB_STATUS:-}" == "success" ]]; then
      echo "### Deploy: ${environment}"
    else
      echo "### Deploy: stopped in preflight"
      echo "See the failed step in the preflight job."
    fi

    if [[ -n "${version}" ]]; then
      # Shorten a full commit SHA.
      [[ "${version}" =~ ^[0-9a-f]{40}$ ]] && version="${version:0:12}"
      echo "- **Version:** \`${version}\`${event:+ (${event})}"
    fi

    # Mode only when preflight passed; a stopped run plans and applies nothing.
    if [[ -n "${environment}" && "${JOB_STATUS:-}" == "success" ]]; then
      if [[ "${PLAN_ONLY:-}" == "true" ]]; then
        mode="plan only, no apply"
      else
        mode="plan and apply, approval in \`${environment}\`"
      fi
      if [[ "${EPHEMERAL:-}" == "true" ]]; then
        pr="$(clean "${PR_NUMBER:-}")"
        [[ "${pr}" =~ ^[0-9]+$ ]] || pr="?"
        mode="ephemeral, PR #${pr}, workspaces \`pr-${pr}-<deployment>\`; ${mode}"
      fi
      echo "- **Mode:** ${mode}"
    fi

    # INCLUDE is [{component, deployment}, ...]; no line when it's empty.
    if jq -e 'type == "array" and length > 0' <<< "${INCLUDE:-[]}" > /dev/null 2>&1; then
      count="$(jq 'length' <<< "${INCLUDE}")"
      legs="$(jq -r 'map("`" + ("\(.component)/\(.deployment)" | gsub("[`\r\n]"; "")) + "`") | join(", ")' <<< "${INCLUDE}")"
      echo "- **Legs (${count}):** ${legs}"
    fi
  fi
} >> "${summary}"
