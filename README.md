# core-cloud-workflow-terraform-actions

Reusable GitHub Actions workflows that lint, test, plan and apply Terraform across GitHub Environments, plus the composite actions they are built from. Each leg of a deploy is one component and deployment pair, resolved from a committed `deployments.json`.

## Reusable workflows

- [`deploy.yml`](.github/workflows/deploy.yml): lints, tests, plans and applies the components and deployments of one environment, with an approval gate before apply.
- [`pr-validation.yml`](.github/workflows/pr-validation.yml): lints, tests, validates and plans every component on a pull request. It never applies.
- [`cleanup-ephemeral.yml`](.github/workflows/cleanup-ephemeral.yml): destroys the per-PR workspaces that ephemeral deploys create.

```text
deploy:         preflight -> lint | test | plan (parallel) -> approval gate -> apply
pr-validation:  expand    -> lint | test | validate (parallel)
```

`preflight` decides what runs: it resolves the trigger to an environment and version, checks preconditions, validates `deployments.json` and expands the selectors into a leg matrix. A skipped trigger stops the run there. `lint` runs `terraform fmt` and TFLint once over `source/terraform`. `test` runs `terraform test` once per component, and per module in PR validation, with `init -backend=false`, so it never touches state or AWS. `plan` and `apply` (`validate` in PR validation) run once per leg. Each plan uses the read-only plan role and uploads its plan file, and apply uses the apply role to apply that file. `apply` needs `lint`, `test` and `plan` to succeed; `test` may be skipped when no component has tests. `pr-validation.yml` has no apply job and no gate. `deploy.yml` with `plan-only: true` plans every leg and stops, with no gate, for change-control evidence against any environment.

## Triggers

| Event | Environment (input, default) | Version deployed |
| --- | --- | --- |
| Push to the default branch | `development-environment`, `dev` | Commit SHA |
| Pre-release published | `pre-release-environment`, `test` | Release tag |
| Release released (promoted or stable) | `release-environment`, `prod` | Release tag |
| `workflow_dispatch` | Chosen environment | Chosen ref |

Dispatch can narrow a run with `component` and `deployment` (a name, a comma list or `all`). Setting `ephemeral: true` deploys into a throwaway `pr-<n>-<deployment>` workspace in the development environment; the branch must have an open PR. Event-driven runs always deploy everything. Publishing a stable release also fires `published`, which skips. Outside the development environment, the version must be `main`, `master` or a semver tag.

## Repository layout and config

```text
source/terraform/
  deployments.json
  components/<component>/
    *.tf
    tests/                              # optional, terraform test
    environments/<env>/<deployment>.tfvars
  modules/<module>/                     # optional, tested on PRs
```

A deployment is a tfvars file. `deployments.json` has one entry per tfvars file, keyed `<component>/<env>/<deployment>`. All four fields are required:

```json
{
  "component-a/dev/dev": {
    "account_id": "123456789012",
    "plan_role_name": "github-oidc-terraform-plan-role-example",
    "apply_role_name": "github-oidc-terraform-apply-role-example",
    "state_bucket_name": "example-tfstate-dev"
  }
}
```

The file is validated on every PR and at the start of every deploy. It fails on invalid JSON, a missing or empty field, an entry with no tfvars file, or a tfvars file with no entry. State is stored in `state_bucket_name` at `<repository>/<component>/<env>/<deployment>/terraform.tfstate`.

## Requirements

- Terraform 1.10 or later. State locking is S3-native (`use_lockfile`) with encryption on, so no DynamoDB table is used. `state_lock_table_name` is ignored and can be removed from `deployments.json`.
- The plan and apply roles can read, write and delete the `.tflock` object in the state bucket.
- One GitHub Environment per environment name, each with a `required_reviewers` protection rule. A non-plan-only deploy fails in `preflight` if the rule is missing. One approval releases every leg of that environment in the run.
- Caller job permissions: `id-token: write`, `contents: read`, `actions: read` and `pull-requests: read`.
- Pass `ephemeral` and `plan-only` as `${{ inputs.x || false }}`, because the inputs are empty on events other than dispatch.
- Pass only the inputs and secrets a workflow declares. GitHub rejects undeclared ones.

## Optional inputs and secrets

| Name | Used by | Default | Purpose |
| --- | --- | --- | --- |
| `development-environment`, `pre-release-environment`, `release-environment` | deploy (`development-environment` also cleanup) | `dev`, `test`, `prod` | The environment each trigger deploys to. `development-environment` also hosts ephemeral workspaces and skips the version check. An empty value disables that trigger. |
| `github_app_client_id`, `github_app_private_key`, `git_auth_token` | all | none | Credentials for private module sources. With both App secrets set, the workflow mints an App token; otherwise it uses `git_auth_token`. It then points git at the token for `github.com` (HTTPS and SSH URLs) for the rest of the job. Setting only one App secret fails the run. There is no `pre-exec-script`: a `standard-pipeline` caller passes the same secrets and drops its `insteadOf` script. |
| `tf-aws-tag-policy-compliance` | deploy, pr-validation | none | `warning` or `error`, exported as `TF_AWS_TAG_POLICY_COMPLIANCE`. |
| `DYNATRACE_ENVIRONMENT_ID`, `DYNATRACE_PLATFORM_TOKEN` | all | none | Dynatrace provider credentials. |
| `runner` | all | `ubuntu-latest` | Runner for the jobs that run Terraform against real providers. |
| `plan` | pr-validation | `true` | Set `false` for a module-only repository: only `lint` and `test` run, with no `deployments.json`, AWS access or state, GitHub checks every job's permissions before the run starts, so the caller still grants `contents: read` and `id-token: write`; no token is requested. |
| `terraform-version` | all | deploy `1.17.2`, others `>= 1.10.0` | Terraform version. Pass an exact version to deploy: plan and apply resolve a range separately, so a release landing while apply waits at the gate makes Terraform refuse the saved plan. |
| `aws-region` | all | `eu-west-2` | Region for the state backend. |
| `deployments-file` | all | `source/terraform/deployments.json` | Path to `deployments.json`. |

SonarQube runs in the repository's own scan workflow. `pr-validation.yml` still accepts `sonar_host_url` and `sonar_token` so existing callers keep working, and ignores them.

## Example caller

Pin to a release tag in place of `<tag>`.

```yaml
name: Terraform Deploy

on:
  release:
    types: [published, released]
  push:
    branches: [main]
    paths:
      - "source/terraform/**"
  workflow_dispatch:
    inputs:
      environment:
        description: "Target environment"
        required: true
        type: choice
        options: [dev, test, prod]
      version:
        description: "Git ref to deploy. If blank, falls back to the branch selected above"
        required: false
        type: string
        default: ""
      component:
        description: "'all', one name, or a comma list"
        required: false
        type: string
        default: all
      deployment:
        description: "'all', one name, or a comma list"
        required: false
        type: string
        default: all
      ephemeral:
        description: "throwaway per-PR workspace (dev only, needs an open PR)"
        required: false
        type: boolean
        default: false
      plan-only:
        description: "plan only, no apply or gate"
        required: false
        type: boolean
        default: false

run-name: >-
  Terraform Deploy (${{ github.event_name }}:
  ${{ github.event_name == 'release' && github.event.release.tag_name || github.ref_name }})

permissions:
  contents: read

jobs:
  deploy:
    permissions:
      id-token: write
      contents: read
      actions: read
      pull-requests: read
    uses: Home-Office-Digital/core-cloud-workflow-terraform-actions/.github/workflows/deploy.yml@<tag>
    with:
      component: ${{ inputs.component }}
      deployment: ${{ inputs.deployment }}
      environment: ${{ inputs.environment }}
      version: ${{ inputs.version != '' && inputs.version || github.ref_name }}
      ephemeral: ${{ inputs.ephemeral || false }}
      plan-only: ${{ inputs.plan-only || false }}
      terraform-version: "1.17.2"
```

The PR validation and cleanup callers have the same shape and call `pr-validation.yml` and `cleanup-ephemeral.yml`. PR validation triggers on `pull_request` for `source/terraform/**` and passes `environment: dev`. Cleanup runs weekly on a schedule and on dispatch with a `scope` input (`all` for closed or merged PRs, or `pr-<n>` for one PR in any state). It passes `scope: ${{ inputs.scope || 'all' }}` and `environment: dev`, which must equal `development-environment`. Cleanup is ungated and only ever touches `pr-*` workspaces in that environment.

## Composite actions

Composite actions for individual Terraform command fragments, which you can use on their own:

- `terraform init`
- `terraform fmt`
- `terraform validate`
- `terraform test` (with optional SonarQube test and coverage report conversion/scan support)
- `terraform plan`
- `terraform apply`

NOTE: As `terraform lint` is not part of the official Terraform CLI, its composite action can be found [here](https://github.com/Home-Office-Digital/core-cloud-workflow-tflint-scan/blob/main/action.yaml) but is included in [`standard-pipeline.yml`](.github/workflows/standard-pipeline.yml).

- If absent, the `terraform init` fragment will bootstrap your defined state bucket and DynamoDB table.
- Optional `use-backend` input allows `terraform init` to run with `-backend=false` for local state workflows and will not run plan/apply.
- Optional `workspace` and `workspace-key-prefix` inputs select a Terraform workspace; unset, `init` behaves as before.

See the reusable workflows above and [`standard-pipeline.yml`](.github/workflows/standard-pipeline.yml) for examples of using the composite actions.

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

## Legacy: standard-pipeline.yml

[`standard-pipeline.yml`](.github/workflows/standard-pipeline.yml) is the earlier single-environment pipeline. It is still supported, but new repositories should use the reusable workflows above.

### Pre-requisites

1. Create a Github Environment.
2. Create a Github Environment secret called ACCOUNT_ID and add the AWS Account ID to it.

### Features

- A customised Github Actions summary page that provides at-a-glance debugging features and current configuration used without needing to delve into the steps or files.
<img width="1387" height="1977" alt="Screenshot 2026-01-09 at 12 16 55" src="https://github.com/user-attachments/assets/6fe24d46-eef5-4002-aba9-8e9e46ba5f4b" />
- By design, restricts `terraform apply` fragments to the `main` branch.

### Usage

Create a workflow file in your `.github/workflows` directory and populate with the following, changing inputs and config as needed.

```yaml
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
```
