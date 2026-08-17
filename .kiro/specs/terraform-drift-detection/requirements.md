# Requirements Document

## Introduction

This feature adds a reusable GitHub Actions workflow for detecting Terraform infrastructure drift. Engineers sometimes make manual changes to cloud resources outside of Terraform, causing the actual infrastructure state to diverge from what is declared in code. This workflow runs on a daily schedule, executes `terraform plan -detailed-exitcode` to detect drift, and sends a Slack notification when drift is found, giving teams visibility into unauthorised or accidental changes.

## Glossary

- **Drift_Detection_Workflow**: The reusable GitHub Actions workflow (`workflow_call`) that orchestrates scheduled Terraform drift detection and Slack alerting.
- **Drift**: A state where the actual cloud infrastructure differs from the Terraform-declared configuration, detected when `terraform plan -detailed-exitcode` returns exit code 2.
- **Consumer_Repository**: A repository that calls the Drift_Detection_Workflow via `workflow_call` and provides its own schedule trigger and configuration inputs.
- **Slack_Notifier**: The component within the Drift_Detection_Workflow responsible for posting a JSON payload to an incoming webhook URL when Drift is detected.
- **Init_Action**: The existing composite action (`actions/init`) that handles AWS OIDC authentication, S3 state bucket bootstrapping, and `terraform init`.
- **Plan_Exit_Code**: The exit code returned by `terraform plan -detailed-exitcode` — 0 means no changes, 1 means error, 2 means Drift detected.

## Requirements

### Requirement 1: Scheduled Execution

**User Story:** As a platform engineer, I want the drift detection workflow to run on a daily schedule, so that I am alerted to infrastructure drift within 24 hours of it occurring.

#### Acceptance Criteria

1. THE Consumer_Repository SHALL trigger the Drift_Detection_Workflow using a `schedule` cron event configured to run once per day at a defined UTC time.
2. THE Drift_Detection_Workflow SHALL support a `workflow_dispatch` trigger that accepts the same inputs defined in Requirement 6 so that engineers can run drift detection on demand with custom configuration.
3. THE Drift_Detection_Workflow SHALL accept a `workflow_call` trigger with the inputs and secrets defined in Requirement 6 so that Consumer_Repositories can invoke it as a reusable workflow.

### Requirement 2: AWS Authentication

**User Story:** As a platform engineer, I want the drift detection workflow to authenticate to AWS using OIDC, so that drift can be detected against the live infrastructure state without long-lived credentials.

#### Acceptance Criteria

1. THE Drift_Detection_Workflow SHALL authenticate to AWS by delegating to the Init_Action, which uses `aws-actions/configure-aws-credentials@v4` with an IAM role ARN constructed as `arn:aws:iam::<account_id>:role/<role-to-assume>`.
2. THE Drift_Detection_Workflow SHALL accept an `account_id` secret and `aws-region` input, and pass them along with the `role-to-assume` input to the Init_Action for OIDC authentication.
3. THE Drift_Detection_Workflow SHALL require `id-token: write` permission at the workflow level to enable OIDC token exchange with AWS.
4. IF OIDC authentication fails, THEN THE Drift_Detection_Workflow SHALL fail the workflow run and report the authentication error in the GitHub Actions step summary.

### Requirement 3: Terraform Initialisation

**User Story:** As a platform engineer, I want the drift detection workflow to initialise Terraform with the remote backend, so that it can compare the declared state against actual infrastructure.

#### Acceptance Criteria

1. THE Drift_Detection_Workflow SHALL reuse the Init_Action to perform Terraform initialisation with the remote S3 backend, passing `state-bucket`, `state-key`, `state-dynamodb-table`, `aws-region`, `working-directory`, `github-environment`, `role-to-assume`, `account_id`, and `terraform-version` inputs.
2. THE Drift_Detection_Workflow SHALL accept a `terraform-version` input with a default value of `~1.7.0`.
3. IF the Init_Action fails, THEN THE Drift_Detection_Workflow SHALL terminate the workflow run and report the initialisation failure in the GitHub Actions step summary.
4. THE Drift_Detection_Workflow SHALL set the Init_Action `use-backend` input to `true` to ensure the remote S3 state backend is configured.

### Requirement 4: Drift Detection via Plan

**User Story:** As a platform engineer, I want the workflow to run `terraform plan -detailed-exitcode`, so that infrastructure drift is detected programmatically.

#### Acceptance Criteria

1. THE Drift_Detection_Workflow SHALL execute `terraform plan -detailed-exitcode -input=false` in the directory specified by the `working-directory` input parameter.
2. WHEN `terraform plan -detailed-exitcode` returns exit code 2, THE Drift_Detection_Workflow SHALL set an output variable `drift-detected` to `true` and mark the workflow step as successful.
3. WHEN `terraform plan -detailed-exitcode` returns exit code 1, THE Drift_Detection_Workflow SHALL mark the workflow step as failed and expose the plan error output in the workflow logs.
4. WHEN `terraform plan -detailed-exitcode` returns exit code 0, THE Drift_Detection_Workflow SHALL set an output variable `drift-detected` to `false` and skip Slack notification.
5. THE Drift_Detection_Workflow SHALL accept an optional `tfvars-file` input to pass a variable file to the plan command via the `-var-file` flag.
6. IF the `tfvars-file` input is provided and the specified file does not exist at the resolved path, THEN THE Drift_Detection_Workflow SHALL fail the workflow step and report an error indicating the variable file was not found.
7. IF `terraform plan` does not complete within 10 minutes, THEN THE Drift_Detection_Workflow SHALL terminate the plan process and mark the workflow step as failed.

### Requirement 5: Slack Notification on Drift

**User Story:** As a platform engineer, I want to receive a Slack notification when drift is detected, so that my team can investigate and remediate the divergence promptly.

#### Acceptance Criteria

1. WHEN Drift is detected, THE Slack_Notifier SHALL send a notification by posting a JSON payload to the incoming webhook URL provided by the `drift_detection_webhook_url` secret.
2. WHEN Drift is detected, THE Slack_Notifier SHALL include in the message: the repository name, the GitHub environment name, the working directory, and a link to the workflow run.
3. WHEN `terraform plan -detailed-exitcode` returns exit code 0, THE Slack_Notifier SHALL NOT send a notification.
4. WHEN `terraform plan -detailed-exitcode` returns exit code 1, THE Slack_Notifier SHALL send an error notification by posting a JSON payload to the incoming webhook URL, indicating the plan failed, including the repository name, the GitHub environment name, and a link to the workflow run.
5. IF Slack message delivery fails, THEN THE Drift_Detection_Workflow SHALL report the delivery failure in the workflow logs but SHALL NOT fail the overall workflow run.

### Requirement 6: Workflow Inputs and Configuration

**User Story:** As a platform engineer, I want the drift detection workflow to accept the same configuration inputs as the standard pipeline, so that I can reuse existing environment configuration without duplication.

#### Acceptance Criteria

1. THE Drift_Detection_Workflow SHALL accept the following inputs with their default values: `aws-region` (default: `eu-west-2`), `github-environment` (default: `placeholder`), `role-to-assume` (required, no default), `state-bucket` (required, no default), `state-dynamodb-table` (default: empty string), `state-key` (default: `terraform.tfstate`), `terraform-version` (default: `~1.7.0`), `working-directory` (default: `.`), `tfvars-file` (default: empty string), `pre-exec-script` (default: empty string).
2. THE Drift_Detection_Workflow SHALL accept the following secrets: `account_id` (required), `drift_detection_webhook_url` (required), `git_auth_token` (optional).
3. THE Drift_Detection_Workflow SHALL validate that all required inputs (`role-to-assume`, `state-bucket`) and required secrets (`account_id`, `drift_detection_webhook_url`) are provided before executing any Terraform commands.

### Requirement 7: Pre-Execution Script Support

**User Story:** As a platform engineer, I want the drift detection workflow to support an optional pre-execution script, so that I can perform setup tasks (such as configuring git credentials for private modules) before Terraform runs.

#### Acceptance Criteria

1. WHERE a `pre-exec-script` input is provided, THE Drift_Detection_Workflow SHALL execute the specified script before running Terraform initialisation, with a maximum execution time of 60 seconds.
2. WHERE a `pre-exec-script` input is provided, THE Drift_Detection_Workflow SHALL make the `git_auth_token` secret available as an environment variable during pre-execution script execution.
3. IF the pre-execution script exits with a non-zero exit code, THEN THE Drift_Detection_Workflow SHALL terminate the workflow run and report a failure indicating the pre-execution script failed.
4. IF the pre-execution script exceeds the 60-second execution time limit, THEN THE Drift_Detection_Workflow SHALL terminate the script and report a failure indicating a timeout occurred.

### Requirement 8: GitHub Actions Summary

**User Story:** As a platform engineer, I want the drift detection workflow to produce a GitHub Actions summary, so that I can review drift detection results directly from the Actions UI.

#### Acceptance Criteria

1. WHEN Drift is detected, THE Drift_Detection_Workflow SHALL write a summary to the GitHub Actions step summary that includes the repository name, the `github-environment` input value, and the working directory, indicating that drift was found.
2. WHEN no Drift is detected, THE Drift_Detection_Workflow SHALL write a summary to the GitHub Actions step summary that includes the repository name and the `github-environment` input value, confirming that no drift was found.
3. WHEN a plan error occurs, THE Drift_Detection_Workflow SHALL write a summary to the GitHub Actions step summary that includes the repository name, the `github-environment` input value, and the working directory, indicating that the plan failed.
4. THE Drift_Detection_Workflow SHALL write exactly one summary to the GitHub Actions step summary per workflow run, corresponding to the Plan_Exit_Code outcome.
