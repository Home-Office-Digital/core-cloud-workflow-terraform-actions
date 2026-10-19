# core-cloud-workflow-terraform-actions

## Overview
This repository contains composite actions for individual terraform command fragments that you can use individually
- `terraform init`
- `terraform fmt`
- `terraform validate`
- `terraform test` (with optional SonarQube test and coverage report conversion/scan support)
- `terraform plan`
- `terraform apply`

and a complete [Terraform workflow file](https://github.com/Home-Office-Digital/core-cloud-workflow-terraform-actions/blob/main/.github/workflows/standard-pipeline.yml) when you just want to use a complete Terraform pipeline.

NOTE: - As `terraform lint` is not part of the official Terraform CLI, its composite action can be found [here](https://github.com/Home-Office-Digital/core-cloud-workflow-tflint-scan/blob/main/action.yaml) but is included in the complete workflow file within this repo.

## Pre-requisites
1. Create a Github Environment.
2. Create a Github Environment secret called ACCOUNT_ID and add the AWS Account ID to it.

## Features
- If absent, the `terraform init` fragment will bootstrap your defined state bucket and DynamoDB table.
- Optional `use-backend` input allows `terraform init` to run with `-backend=false` for local state workflows and will not run plan/apply
- A customised Github Actions summary page that provides at-a-glance debugging features and current configuration used without needing to delve into the steps or files.

<img width="1387" height="1977" alt="Screenshot 2026-01-09 at 12 16 55" src="https://github.com/user-attachments/assets/6fe24d46-eef5-4002-aba9-8e9e46ba5f4b" />
  
- By design, restricts `terraform apply` fragments to the `main` branch.

## Usage of complete workflow file
Craete a workflow file in your `.github/workflows` directory and populate with the following, changing inputs and config as needed.

    name: Test Terraform Actions Pipeline
    
    on:
      push:
        branches: [ main ]
    
    jobs:
      <JOB_NAME>:
        permissions:
          id-token: write
          contents: read
          pull-requests: write
        uses: Home-Office-Digital/core-cloud-workflow-terraform-actions/.github/workflows/standard-pipeline.yml@main
        with:
          working-directory: '.'
          github-environment: '<GITHUB_ENVIRONMENT_NAME>'
          use-backend: true
          state-bucket: '<DESIRED_NAME_OF_S3_BUCKET_FOR_STORING_STATE_FILES>'
          state-dynamodb-table: '<DESIRED_DYNAMODB_TABLE_NAME>'
          role-to-assume: '<AWS_ROLE_THAT_HAS_PERMISSIONS_TO_CREATE_AND_DESTROY_RESOURCES>'
        secrets:
          account_id: ${{ secrets.ACCOUNT_ID }}

### Optional Dynatrace Environment secrets

For Terraform workloads using Dynatrace dashboard direct sharing, create these
**Environment secrets** in the **calling repository**, under Settings → Environments
→ the environment selected by `github-environment` (for example, `live-ops-tooling`):

- `DYNATRACE_ENVIRONMENT_ID`: the Dynatrace environment ID used in the sharing API hostname.
- `DYNATRACE_PLATFORM_TOKEN`: a platform token with the permissions required by the sharing API.

The standard workflow exports both from `secrets`, **not `vars`**, into the job's
shell environment, including Terraform plan and apply and their `local-exec`
children. Provider credentials loaded from AWS Secrets Manager or Terraform
configuration do **not** populate these shell variables.

No caller workflow changes or secrets in this shared workflow repository are
needed. The called job selects the caller repository's Environment; its secrets
are available there without `workflow_call.secrets` declarations or explicit
forwarding. Environment secrets take precedence over same-named secrets passed
by the caller (including through `secrets: inherit`).

Both secrets are optional for the generic pipeline; absent secrets resolve to
empty strings. Workloads requiring direct sharing must configure both. To fail
early for those workloads only, optionally use the existing `pre-exec-script`
input under the caller's `with:` block:

```yaml
pre-exec-script: |
  missing=0
  for name in DYNATRACE_ENVIRONMENT_ID DYNATRACE_PLATFORM_TOKEN; do
    if [ -z "${!name}" ]; then
      echo "::error::Missing required secret: ${name}" >&2
      missing=1
    fi
  done
  if [ "$missing" -ne 0 ]; then
    exit 1
  fi
```

This check reports secret names only. Do not print credentials or persist them
in plan artifacts or files. Standalone composite-action callers must supply
their own shell environment; the generic apply action has no Dynatrace requirements.

Missing shell exports are a confirmed workflow wiring gap, but an `HTTP 000`
sharing failure alone does not establish the network root cause: DNS, TLS or
connectivity failures can also produce it.

## Usage of composite actions
Please refer to the [Terraform workflow file](https://github.com/Home-Office-Digital/core-cloud-workflow-terraform-actions/blob/main/.github/workflows/standard-pipeline.yml) for examples of using composite actions.
NOTE: Running `terraform validate` has conditional logic to initialise the terraform code, so you don't need to add the `terraform init` fragment beforehand.

Example: Call the test composite action (remote action usage)

```yaml
- name: Run terraform tests and publish results (remote action branch)
  id: terraform-test
  uses: Home-Office-Digital/core-cloud-workflow-terraform-actions/actions/test@main
  with:
    working-directory: .
    test-directory: tests/plan
    sonar-host-url: ${{ secrets.SONAR_HOST_URL }}
    sonar-token: ${{ secrets.SONAR_TOKEN }}
```