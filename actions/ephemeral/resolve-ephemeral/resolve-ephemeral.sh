#!/usr/bin/env bash
# Check an ephemeral deploy's environment and output the branch's open PR.
# Env: ENVIRONMENT, EPHEMERAL_ENVIRONMENT, BRANCH, REPO, GH_TOKEN.
# Writes: pr-number (GITHUB_OUTPUT).
set -euo pipefail

if [[ "${ENVIRONMENT}" != "${EPHEMERAL_ENVIRONMENT}" ]]; then
  echo "::error::ephemeral is allowed only in '${EPHEMERAL_ENVIRONMENT}'; got '${ENVIRONMENT}'."
  exit 1
fi

# The PR number names the workspaces; the first scope=all cleanup after the PR
# closes removes them.
# --head matches the branch in any repository, so fork PRs are dropped.
pr="$(gh pr list --repo "${REPO}" --head "${BRANCH}" --state open \
  --json number,isCrossRepository \
  --jq 'map(select(.isCrossRepository | not)) | .[0].number // ""')"
if [[ -z "${pr}" ]]; then
  echo "::error::no open PR for branch '${BRANCH}'. Open one (a draft is fine) before an ephemeral deploy."
  exit 1
fi

echo "resolved ephemeral PR ${pr} for branch '${BRANCH}'."
echo "pr-number=${pr}" >> "${GITHUB_OUTPUT}"
