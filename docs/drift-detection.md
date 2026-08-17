# Terraform Drift Detection

Scheduled drift detection for Terraform-managed infrastructure. Runs `terraform plan` against your live state and notifies your team via Slack when drift is found, the check fails, or everything is clean.

## How it works

1. Your repo calls the reusable workflow on a cron schedule
2. The workflow runs `terraform init` then `terraform plan -detailed-exitcode -lock=false`
3. Based on the plan exit code:
   - **Exit 0** — No drift, Slack gets a "no drift" confirmation
   - **Exit 2** — Drift detected, Slack gets a warning with a link to the run
   - **Exit 1** — Plan failed (auth issue, config error, etc.), Slack gets an error notification
4. A step summary is written to the GitHub Actions UI for anyone who clicks through

The plan uses `-lock=false` so drift checks never block real deploys.

## Prerequisites

### 1. Create a Slack App with Incoming Webhook

1. Go to https://api.slack.com/apps
2. Click **Create New App** → **From scratch**
3. Name it (e.g. `Terraform Drift Alerts`), select your workspace
4. Left sidebar → **Incoming Webhooks** → Toggle on
5. Click **Add New Webhook to Workspace**
6. Select the channel to post to (e.g. `#terraform-drift`)
7. Copy the webhook URL

### 2. Add GitHub Repository Secrets

In your team's repo: Settings → Secrets and variables → Actions → New repository secret

| Secret | Value |
|--------|-------|
| `ACCOUNT_ID` | Your AWS account ID |
| `SLACK_WEBHOOK_URL` | The webhook URL from step 1 |

## Usage

Create a workflow file in your repo at `.github/workflows/drift-check.yml`:

```yaml
name: Drift Check

on:
  schedule:
    - cron: '0 8 * * 1-5'  # Weekdays at 8am UTC
  workflow_dispatch:         # Allow manual trigger

jobs:
  drift:
    uses: Home-Office-Digital/core-cloud-workflow-terraform-actions/.github/workflows/drift-detection.yml@main
    with:
      role-to-assume: my-terraform-role
      state-bucket: my-team-tf-state
      working-directory: infra/
    secrets:
      account_id: ${{ secrets.ACCOUNT_ID }}
      slack_webhook_url: ${{ secrets.SLACK_WEBHOOK_URL }}
```

### All available inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `aws-region` | No | `eu-west-2` | AWS region for state bucket and resources |
| `github-environment` | No | `placeholder` | GitHub environment name |
| `role-to-assume` | Yes | — | AWS IAM role name for OIDC |
| `state-bucket` | Yes | — | S3 bucket for Terraform state |
| `state-dynamodb-table` | No | `""` | DynamoDB table for state locking |
| `state-key` | No | `terraform.tfstate` | State file key path |
| `terraform-version` | No | `~1.7.0` | Terraform version |
| `tfvars-file` | No | `""` | Path to a `.tfvars` file |
| `working-directory` | No | `.` | Directory containing `main.tf` |
| `pre-exec-script` | No | `""` | Shell script to run before Terraform steps |

### Required secrets

| Secret | Required | Description |
|--------|----------|-------------|
| `account_id` | Yes | AWS account ID |
| `slack_webhook_url` | Yes | Slack incoming webhook URL |
| `git_auth_token` | No | GitHub token for private module access |
| `github_app_client_id` | No | GitHub App client ID |
| `github_app_private_key` | No | GitHub App private key |

## Slack notifications

The action sends a single-line Slack message for every run:

- **Drift detected:** `⚠️ Drift detected — View Run`
- **No drift:** `✅ No drift — View Run`
- **Check failed:** `❌ Check failed — View Run`

Click "View Run" to see the full step summary with environment and repository details.

## Recommended schedules

| Schedule | Cron | Use case |
|----------|------|----------|
| Weekdays at 8am | `0 8 * * 1-5` | Most teams — catch overnight drift before standup |
| Every 6 hours | `0 */6 * * *` | High-sensitivity environments |
| Daily at midnight | `0 0 * * *` | Low-churn infrastructure |

## Troubleshooting

### "Check failed" notification

Common causes:
- **AWS credentials:** Role doesn't exist or OIDC trust policy is misconfigured
- **State bucket:** Bucket doesn't exist or IAM role lacks access
- **Terraform version mismatch:** State written with a newer version than configured
- **tfvars file not found:** Path is wrong relative to `working-directory`

Check the workflow run logs for the specific error.

### No Slack notification received

- Verify `SLACK_WEBHOOK_URL` secret is set correctly in your repo
- Check the webhook is still active in your Slack app settings
- Check the target channel still exists

### Drift check blocks a deploy

This shouldn't happen — the drift check uses `-lock=false` so it never acquires the state lock. If you're seeing lock contention, check whether another `terraform plan` or `apply` is running without `-lock=false`.
