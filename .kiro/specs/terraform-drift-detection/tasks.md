# Implementation Plan: Terraform Drift Detection

## Overview

Implement a reusable GitHub Actions workflow for detecting Terraform infrastructure drift. The drift-detect composite action already exists and handles plan execution, exit code interpretation, and step summary generation. The primary remaining work is creating the reusable workflow that orchestrates pre-exec, init, drift detection, and Slack notification, plus adding tests to validate the shell logic.

## Tasks

- [ ] 1. Create the reusable drift detection workflow
  - [ ] 1.1 Create `.github/workflows/drift-detection.yml` with workflow_call and workflow_dispatch triggers
    - Define `workflow_call` trigger with all inputs from Requirement 6.1 (aws-region, github-environment, role-to-assume, state-bucket, state-dynamodb-table, state-key, terraform-version, working-directory, tfvars-file, slack-channel-id, pre-exec-script)
    - Define `workflow_dispatch` trigger with the same inputs
    - Define secrets: `account_id` (required), `slack_bot_token` (required), `git_auth_token` (optional)
    - Set `permissions: id-token: write` at workflow level
    - Reference `standard-pipeline.yml` for input naming and default value conventions
    - _Requirements: 1.2, 1.3, 2.3, 6.1, 6.2, 6.3_

  - [ ] 1.2 Add the drift-detection job with checkout, pre-exec, init, and drift-detect steps
    - Add `actions/checkout@v4` step
    - Add conditional pre-exec script step with `timeout-minutes: 1` and `GIT_AUTH_TOKEN` env var, gated on `inputs.pre-exec-script != ''`
    - Add Init Action step using `./actions/init` with `use-backend: true` and all relevant inputs passed through
    - Add Drift Detect Action step using `./actions/drift-detect` with `timeout-minutes: 10`, passing working-directory, tfvars-file, and github-environment inputs
    - _Requirements: 2.1, 2.2, 3.1, 3.4, 4.1, 4.5, 4.7, 7.1, 7.2, 7.3, 7.4_

  - [ ] 1.3 Add Slack notification steps for drift and error alerts
    - Add "Notify Slack - Drift Detected" step using `slackapi/slack-github-action@v4` with `chat.postMessage` method, conditioned on `steps.drift-detect.outputs.drift-detected == 'true'`
    - Include Block Kit payload with header, repository, environment, working directory, and workflow run link
    - Add "Notify Slack - Plan Error" step conditioned on `steps.drift-detect.outputs.plan-exit-code == '1'`
    - Include Block Kit payload with header, repository, environment, and workflow run link
    - Set `continue-on-error: true` on both Slack steps to prevent notification failures from failing the workflow
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5, 5.6_

- [ ] 2. Validate and update the drift-detect composite action
  - [ ] 2.1 Review and verify `actions/drift-detect/action.yaml` against design specifications
    - Confirm exit code handling matches Requirements 4.2, 4.3, 4.4
    - Confirm tfvars-file validation matches Requirement 4.6
    - Confirm step summary output matches Requirements 8.1, 8.2, 8.3, 8.4
    - Confirm outputs (`drift-detected`, `plan-exit-code`) are correctly exposed
    - Make any adjustments needed to align with the design document
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 8.1, 8.2, 8.3, 8.4_

- [ ] 3. Checkpoint - Validate workflow structure
  - Ensure all YAML files are syntactically valid, ask the user if questions arise.

- [ ] 4. Add tests for drift-detect shell logic
  - [ ]* 4.1 Set up bats-core test framework for drift-detect action
    - Create `tests/drift-detect/` directory
    - Add a `terraform` mock script that returns configurable exit codes
    - Set up test helper for capturing `$GITHUB_OUTPUT` and `$GITHUB_STEP_SUMMARY` writes
    - _Requirements: 4.1, 4.2, 4.3, 4.4_

  - [ ]* 4.2 Write bats tests for plan exit code handling
    - Test exit code 0: verify `drift-detected=false` and `plan-exit-code=0` in GITHUB_OUTPUT
    - Test exit code 2: verify `drift-detected=true` and `plan-exit-code=2` in GITHUB_OUTPUT
    - Test exit code 1: verify step fails and `plan-exit-code=1` in GITHUB_OUTPUT
    - _Requirements: 4.2, 4.3, 4.4_

  - [ ]* 4.3 Write bats tests for tfvars-file validation
    - Test with non-existent tfvars-file: verify error message and exit 1
    - Test with existing tfvars-file: verify `-var-file` flag is passed to terraform plan
    - Test with empty tfvars-file input: verify plan runs without `-var-file` flag
    - _Requirements: 4.5, 4.6_

  - [ ]* 4.4 Write bats tests for step summary generation
    - Test exit code 0: verify summary contains "No Drift Detected", repository, and environment
    - Test exit code 2: verify summary contains "Drift Detected", repository, environment, and working directory
    - Test exit code 1: verify summary contains "Plan Failed", repository, environment, and working directory
    - _Requirements: 8.1, 8.2, 8.3, 8.4_

- [ ] 5. Add workflow linting
  - [ ]* 5.1 Add actionlint validation for workflow and action YAML files
    - Run `actionlint` against `.github/workflows/drift-detection.yml`
    - Run `actionlint` against `actions/drift-detect/action.yaml`
    - Fix any schema or syntax issues reported
    - _Requirements: 6.1, 6.2, 6.3_

- [ ] 6. Create consumer repository usage example
  - [ ] 6.1 Add usage documentation and example workflow to README or docs
    - Create an example consumer workflow showing schedule + workflow_dispatch triggers
    - Document all required inputs and secrets
    - Document optional inputs with their defaults
    - Show how to configure Slack channel ID and bot token
    - _Requirements: 1.1, 6.1, 6.2_

- [ ] 7. Final checkpoint - Ensure all files are valid
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- The `actions/drift-detect/action.yaml` already exists with the core implementation — task 2.1 is a verification/alignment pass
- The primary implementation effort is in task 1 (creating the reusable workflow)
- Slack notification uses `slackapi/slack-github-action@v4` with `chat.postMessage` method and Block Kit formatting
- The design explicitly states property-based testing is not applicable for this IaC feature
- Shell tests use `bats-core` framework to validate exit code handling in isolation
- `actionlint` provides static analysis for GitHub Actions YAML schema compliance

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1", "2.1"] },
    { "id": 1, "tasks": ["1.2"] },
    { "id": 2, "tasks": ["1.3"] },
    { "id": 3, "tasks": ["4.1", "5.1"] },
    { "id": 4, "tasks": ["4.2", "4.3", "4.4"] },
    { "id": 5, "tasks": ["6.1"] }
  ]
}
```
