#!/usr/bin/env bash
# Check terraform-dir is a plain relative path, then derive the names built from it.
# Env: TERRAFORM_DIR, DEPLOYMENTS_FILE (optional), GITHUB_REPOSITORY.
# Writes: slug, state-prefix, deployments-file (GITHUB_OUTPUT).
set -euo pipefail
# A segment can't start with -, or cd and other tools read the path as an option.
segment='\.?[A-Za-z0-9_][A-Za-z0-9._-]*'
re="^${segment}(/${segment})*\$"
if [[ ! "${TERRAFORM_DIR}" =~ ${re} ]]; then
  echo "::error::invalid terraform-dir '${TERRAFORM_DIR}': use letters, digits and . _ - in segments separated by /, with no leading or trailing /, no . or .. segment and no segment starting with -."
  exit 1
fi
# Prefixed with the repo name, so repos sharing a bucket can't collide. A
# non-default folder is added too, so folders in one repo can't collide.
prefix="${GITHUB_REPOSITORY##*/}"
slug=""
if [[ "${TERRAFORM_DIR}" != "source/terraform" ]]; then
  slug="_${TERRAFORM_DIR//\//-}"
  prefix="${prefix}/${TERRAFORM_DIR}"
fi
{
  echo "slug=${slug}"
  echo "state-prefix=${prefix}"
  echo "deployments-file=${DEPLOYMENTS_FILE:-${TERRAFORM_DIR}/deployments.json}"
} >> "${GITHUB_OUTPUT}"
