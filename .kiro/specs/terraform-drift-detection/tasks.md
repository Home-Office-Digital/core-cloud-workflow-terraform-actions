# Implementation Plan: Terraform Drift Detection

## Overview

Implement a reusable GitHub Actions workflow and supporting composite action for detecting Terraform infrastructure drift. The drift-detect composite action (`actions/drift-detect/action.yaml`) already exists with plan execution and summary logic. The remaining work is to create the reusable workflow (`drift-detection.yml`) that orchestrates pre-execution scripts, Terraform initialisation, drift detection, and Slack notification via incoming webhook.

## Tasks

- [ ] 1. Verify and update the drift-detect composite action
  - [ ] 1.1 Add timeout to the Terraform Plan step in `actions/drift-detect/action.yaml`
    - Add `timeout-minutes: 10` to the "Terraform Plan (Drift Detection)" step to satisfy the 10-minute timeout requirement
    - Verify the existing inputs, outputs, tfvars validation, exit code handling, and step summary logic match the design
    - _Requirements: 4.7, 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 8.1, 8.2, 8.3, 8.4_

- [ ] 2. Create the drift-detection reusable workflow
  - [ ] 2.1 Create `.github/workflows/drift-detection.yml` with workflow triggers, inputs, and secrets
    - Define `workflow_call` trigger with all inputs from the Data Models section: `aws-region`, `github-environment`, `role-to-assume`, `state-bucket`, `state-dynamodb-table`, `state-key`, `terraform-version`, `working-directory`, `tfvars-file`, `pre-exec-script`
    - Define `workflow_dispatch` trigger with the same inputs for on-demand execution
    - Define secrets: `account_id` (required), `drift_detection_webhook_url` (required), `git_auth_token` (optional)
    - Mark `role-to-assume` and `state-bucket` as `required: true`
    - Set `permissions: id-token: write, contents: read`
    - _Requirements: 1.2, 1.3, 6.1, 6.2, 6.3, 2.3_

  - [ ] 2.2 Implement the pre-execution script step
    - Add a conditional step that runs only when `pre-exec-script` input is provided
    - Set `timeout-minutes: 1` to enforce the 60-second limit
    - Expose `git_auth_token` secret as an environment variable (`GITHUB_TOKEN` or `CUSTOM_GITHUB_TOKEN`) during script execution
    - Follow the pattern from `standard-pipeline.yml` pre-exec step
    - _Requirements: 7.1, 7.2, 7.3, 7.4_

  - [ ] 2.3 Integrate the Init Action step
    - Add a step that calls `Home-Office-Digital/core-cloud-workflow-terraform-actions/actions/init@main`
    - Pass all required inputs: `account_id`, `aws-region`, `github-environment`, `role-to-assume`, `state-bucket`, `state-dynamodb-table`, `state-key`, `terraform-version`, `working-directory`
    - Set `use-backend: true` to ensure remote S3 state backend is configured
    - _Requirements: 2.1, 2.2, 3.1, 3.2, 3.3, 3.4_

  - [ ] 2.4 Integrate the Drift Detect Action step
    - Add a step that calls `Home-Office-Digital/core-cloud-workflow-terraform-actions/actions/drift-detect@main`
    - Pass `working-directory`, `tfvars-file`, and `github-environment` inputs
    - Assign step id `drift-detect` so outputs can be referenced by notification steps
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 4.6_

  - [ ] 2.5 Implement Slack notification steps using incoming webhook
    - Add "Notify Slack - Drift Detected" step: conditional on `steps.drift-detect.outputs.drift-detected == 'true'`, uses `curl -X POST` to send Block Kit JSON payload to `drift_detection_webhook_url` secret, includes repository name, environment, working directory, and workflow run link
    - Add "Notify Slack - Plan Error" step: conditional on `steps.drift-detect.outputs.plan-exit-code == '1'`, uses `curl -X POST` to send Block Kit JSON payload with repository name, environment, and workflow run link
    - Both steps must use `continue-on-error: true` so Slack delivery failure does not fail the workflow
    - Use `--fail-with-body` flag on curl to log HTTP errors
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5_

- [ ] 3. Checkpoint - Verify workflow and action configuration
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 4. Add static analysis and testing
  - [ ] 4.1 Validate workflow files with `actionlint`
    - Run `actionlint` against `actions/drift-detect/action.yaml` and `.github/workflows/drift-detection.yml` to verify schema compliance
    - Fix any reported issues
    - _Requirements: 6.1, 6.2, 6.3_

  - [ ]* 4.2 Write shell tests for drift-detect action using `bats-core`
    - Create test file to verify exit code handling: mock `terraform plan` returning exit codes 0, 1, and 2
    - Verify outputs `drift-detected` and `plan-exit-code` are set correctly for each scenario
    - Test tfvars-file validation (missing file produces error, existing file passes `-var-file` flag)
    - Test step summary content for each exit code scenario
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 8.1, 8.2, 8.3_

- [ ] 5. Create consumer repository example
  - [ ] 5.1 Add a usage example for consumer repositories
    - Create an example workflow snippet (in README or docs) showing how a consumer repository calls the reusable workflow with `schedule` cron trigger and `workflow_dispatch`
    - Include example with all inputs and secrets populated
    - _Requirements: 1.1, 1.3_

- [ ] 6. Final checkpoint - Ensure all configuration is complete
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- The `actions/drift-detect/action.yaml` already exists with most of the required logic; task 1.1 only adds the missing timeout
- This feature is Infrastructure as Code (GitHub Actions YAML) — no property-based tests apply
- Slack notification uses `curl` to POST to an incoming webhook URL (`drift_detection_webhook_url` secret) — no bot token, no channel ID input needed
- The workflow follows patterns established by `standard-pipeline.yml` for pre-exec and init steps
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1", "2.1"] },
    { "id": 1, "tasks": ["2.2", "2.3"] },
    { "id": 2, "tasks": ["2.4"] },
    { "id": 3, "tasks": ["2.5"] },
    { "id": 4, "tasks": ["4.1", "4.2"] },
    { "id": 5, "tasks": ["5.1"] }
  ]
}
```
