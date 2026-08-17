# Implementation Plan: Terraform Drift Detection

## Overview

The drift-detect composite action (`actions/drift-detect/action.yaml`) is already complete. The remaining work is creating the reusable workflow (`.github/workflows/drift-detection.yml`) that orchestrates pre-exec, init, drift detection, and Slack notification. Optional tasks cover linting and consumer documentation.

## Tasks

- [ ] 1. Create the drift-detection reusable workflow
  - [ ] 1.1 Create `.github/workflows/drift-detection.yml` with workflow_call and workflow_dispatch triggers
    - Define `on.workflow_call.inputs` matching Requirement 6.1: `aws-region`, `github-environment`, `role-to-assume`, `state-bucket`, `state-dynamodb-table`, `state-key`, `terraform-version`, `working-directory`, `tfvars-file`, `pre-exec-script`
    - Define `on.workflow_call.secrets`: `account_id` (required), `drift_detection_webhook_url` (required), `git_auth_token` (optional)
    - Define `on.workflow_dispatch.inputs` mirroring workflow_call inputs for manual runs
    - Set permissions: `contents: read`, `id-token: write`
    - _Requirements: 1.2, 1.3, 2.3, 6.1, 6.2, 6.3_

  - [ ] 1.2 Implement the pre-exec script step
    - Follow the pattern from `standard-pipeline.yml`: use `eval "$INPUT_PRE_EXEC_SCRIPT"` with `CUSTOM_GITHUB_TOKEN` env var from `secrets.git_auth_token`
    - Set `timeout-minutes: 1` on the step to enforce the 60-second limit
    - Only run when `inputs.pre-exec-script` is non-empty
    - _Requirements: 7.1, 7.2, 7.3, 7.4_

  - [ ] 1.3 Implement the Terraform init step using the existing init action
    - Call `Home-Office-Digital/core-cloud-workflow-terraform-actions/actions/init@main`
    - Pass `account_id` from secrets as an input to the action (matching standard-pipeline pattern)
    - Pass all relevant inputs: `aws-region`, `github-environment`, `role-to-assume`, `state-bucket`, `state-dynamodb-table`, `state-key`, `terraform-version`, `working-directory`
    - Set `use-backend: true`
    - _Requirements: 2.1, 2.2, 3.1, 3.2, 3.3, 3.4_

  - [ ] 1.4 Implement the drift-detect step using the existing drift-detect action
    - Call `Home-Office-Digital/core-cloud-workflow-terraform-actions/actions/drift-detect@main`
    - Pass `working-directory`, `tfvars-file`, `github-environment` inputs
    - Set `timeout-minutes: 10` on the step
    - Set `id: drift-detect` so outputs are accessible in subsequent steps
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 4.7, 8.1, 8.2, 8.3, 8.4_

  - [ ] 1.5 Implement Slack notification steps
    - Add "Notify Slack - Drift Detected" step: condition `steps.drift-detect.outputs.drift-detected == 'true'`, POST Block Kit JSON via `curl` to `secrets.drift_detection_webhook_url`, include repository, environment, working directory, and workflow run link
    - Add "Notify Slack - Plan Error" step: condition `steps.drift-detect.outputs.plan-exit-code == '1'`, POST Block Kit JSON with repository, environment, and workflow run link
    - Both steps use `continue-on-error: true` so Slack failures don't mask drift results
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5_

- [ ] 2. Checkpoint - Validate workflow file
  - Ensure the workflow YAML is syntactically valid and all requirements are covered, ask the user if questions arise.

- [ ]* 3. Optional: Lint and validate workflow
  - [ ]* 3.1 Run `actionlint` on the new workflow file
    - Validate `.github/workflows/drift-detection.yml` against GitHub Actions schema
    - Fix any schema violations or expression errors
    - _Requirements: 6.3_

- [ ]* 4. Optional: Add consumer repository example
  - [ ]* 4.1 Create a usage example in the repo documentation
    - Add an example showing how a consumer repository calls the drift-detection workflow with schedule trigger and `workflow_call`
    - Include all required inputs/secrets and a recommended cron schedule
    - _Requirements: 1.1, 1.3_

## Notes

- Tasks marked with `*` are optional and can be skipped for faster delivery
- The `actions/drift-detect/action.yaml` composite action is already complete — no changes needed
- The only required implementation is the `.github/workflows/drift-detection.yml` reusable workflow
- The workflow follows patterns established in `standard-pipeline.yml` for pre-exec, init, and action invocation
- Property-based testing does not apply (this is GitHub Actions YAML configuration)
- Slack notification uses incoming webhook via `curl` — no bot token or channel ID needed

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1"] },
    { "id": 1, "tasks": ["1.2", "1.3"] },
    { "id": 2, "tasks": ["1.4"] },
    { "id": 3, "tasks": ["1.5"] },
    { "id": 4, "tasks": ["3.1", "4.1"] }
  ]
}
```
