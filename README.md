# core-cloud-workflow-terraform-actions

Reusable GitHub Actions workflows that lint, test, plan and apply Terraform across GitHub Environments, plus the composite actions they are built from. Each leg of a deploy is one component and deployment pair, resolved from a committed `deployments.json`.

## Reusable workflows

- [`terraform-multi-env-deploy.yml`](.github/workflows/terraform-multi-env-deploy.yml): lints, tests, plans and applies the components and deployments of one environment, with an approval gate before apply.
- [`terraform-pr-validation.yml`](.github/workflows/terraform-pr-validation.yml): lints, tests, validates and plans every component on a pull request. It never applies.
- [`terraform-ephemeral-cleanup.yml`](.github/workflows/terraform-ephemeral-cleanup.yml): destroys the per-PR workspaces that ephemeral deploys create.

```text
deploy:         preflight -> lint | test | plan (parallel) -> approval gate -> apply
pr-validation:  preflight -> lint | test | plan (parallel)
```

- `preflight`: resolves the trigger to an environment and version, checks preconditions, validates `deployments.json` and expands the selectors into a leg matrix. A skipped trigger stops the run here.
- `lint`: runs `terraform fmt` and TFLint once over `terraform-dir`.
- `test`: runs `terraform test` once per component, and per module in PR validation, with `init -backend=false`, so it never touches state or AWS.
- `plan`: runs once per leg with the read-only plan role and uploads its plan file.
- `apply`: runs once per leg with the apply role and applies that plan file. It needs `lint`, `test` and `plan` to succeed; `test` may be skipped when no component has tests.

With `plan-only: true`, `terraform-multi-env-deploy.yml` plans every leg and stops before the gate, which gives change-control evidence for any environment.

## Triggers

| Event | Environment (input, default) | Version deployed |
| --- | --- | --- |
| Push to the default branch | `development-environment`, `development` | Commit SHA |
| Pre-release published | `pre-release-environment`, `pre-release` | Release tag |
| Release released (promoted or stable) | `release-environment`, `release` | Release tag |
| `workflow_dispatch` | Chosen environment | Chosen ref |

Dispatch can narrow a run with `component` and `deployment` (a name, a comma list or `all`). Setting `ephemeral: true` deploys into a throwaway `pr-<n>-<deployment>` workspace in the development environment; the branch must have an open PR. Event-driven runs always deploy everything. Publishing a stable release also fires `published`, which skips. Outside the development environment, the version must be `main`, `master` or a semver tag.

## Repository layout and config

The default `terraform-dir` is `source/terraform`:

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
  "component-a/development/main": {
    "account_id": "123456789012",
    "plan_role_name": "github-oidc-terraform-plan-role-example",
    "apply_role_name": "github-oidc-terraform-apply-role-example",
    "state_bucket_name": "example-tfstate-development"
  }
}
```

The file is validated on every PR and at the start of every deploy. It fails on invalid JSON, a missing or empty field, an entry with no tfvars file, or a tfvars file with no entry.

An entry can also set `state_lock_table_name` to lock its state with that DynamoDB table instead of S3. Use it only where a role can't write the `.tflock` object: Terraform has deprecated DynamoDB locking. The table must already exist, with partition key `LockID` (string), and its name may use only letters, digits and `_ . -`. State is stored in `state_bucket_name` at `<repository>/<component>/<env>/<deployment>/terraform.tfstate`.

### Using a different folder

Set `terraform-dir` and update the caller's `paths` filter. `deployments.json` is read from `<terraform-dir>/deployments.json` unless you set `deployments-file`.

- A non-default folder joins the state key: `<repository>/<terraform-dir>/<component>/<env>/<deployment>/terraform.tfstate`. The default key is unchanged. Moving a folder after its first deploy points at fresh state.
- Use one caller workflow per folder, each with its own cleanup caller passing the same `terraform-dir`.

## Requirements

- Terraform 1.10 or later. State is encrypted, and locked S3-natively (`use_lockfile`) unless the entry sets `state_lock_table_name`.
- With S3-native locking, the plan and apply roles can read, write and delete the `.tflock` object in the state bucket. With a lock table, they can read and write its items instead.
- One GitHub Environment per environment name, each with a `required_reviewers` protection rule. A non-plan-only deploy fails in `preflight` if the rule is missing. One approval releases every leg of that environment in the run.
- Caller job permissions: `id-token: write`, `contents: read`, `actions: read` and `pull-requests: read`.
- Pass `ephemeral` and `plan-only` as `${{ inputs.x || false }}`, because the inputs are empty on events other than dispatch.
- Pass only the inputs and secrets a workflow declares. GitHub rejects undeclared ones.

## Optional inputs and secrets

| Name | Used by | Default | Purpose |
| --- | --- | --- | --- |
| `development-environment`, `pre-release-environment`, `release-environment` | deploy (`development-environment` also cleanup) | `development`, `pre-release`, `release` | Environment each trigger deploys to. An empty value disables that trigger. `development-environment` also hosts ephemeral workspaces. |
| `github_app_client_id`, `github_app_private_key`, `git_auth_token` | all | none | Credentials for private module sources. Both App secrets mint an App token; otherwise `git_auth_token` is used. Set both App secrets or neither. Replaces `pre-exec-script`. Git uses the token for `github.com` for the rest of the job. |
| `tf-aws-tag-policy-compliance` | deploy, pr-validation | none | `warning` or `error`. Sets `TF_AWS_TAG_POLICY_COMPLIANCE`. |
| `DYNATRACE_ENVIRONMENT_ID`, `DYNATRACE_PLATFORM_TOKEN` | all | none | Dynatrace provider credentials. |
| `runner` | all | `ubuntu-latest` | Runner for jobs that call real providers. |
| `plan` | pr-validation | `true` | Set `false` for a module-only repository: only `lint` and `test` run, with no AWS access or state. The caller still grants `contents: read` and `id-token: write`. |
| `terraform-version` | all | deploy `1.17.2`, others `>= 1.10.0` | Use an exact version for deploy. A range can resolve differently at apply and invalidate the saved plan. |
| `aws-region` | all | `eu-west-2` | State backend region. |
| `terraform-dir` | deploy, pr-validation, cleanup | `source/terraform` | Folder holding `components/`, `modules/` and `deployments.json`. A relative path of segments separated by `/`, each of letters, digits and `. _ -` only, not starting with `-`. No leading `./` or `/`, no trailing `/`, no `.` or `..` segment. |
| `deployments-file` | all | `<terraform-dir>/deployments.json` | Set only if the file is somewhere else. |

`terraform-pr-validation.yml` accepts `sonar_host_url` and `sonar_token` for existing callers and ignores them.

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
        options: [development, pre-release, release]
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
        description: "throwaway per-PR workspace (development only, needs an open PR)"
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
    uses: Home-Office-Digital/core-cloud-workflow-terraform-actions/.github/workflows/terraform-multi-env-deploy.yml@<tag>
    with:
      component: ${{ inputs.component }}
      deployment: ${{ inputs.deployment }}
      environment: ${{ inputs.environment }}
      version: ${{ inputs.version != '' && inputs.version || github.ref_name }}
      ephemeral: ${{ inputs.ephemeral || false }}
      plan-only: ${{ inputs.plan-only || false }}
      terraform-version: "1.17.2"
```

The PR validation and cleanup callers have the same shape and call `terraform-pr-validation.yml` and `terraform-ephemeral-cleanup.yml`.

- PR validation triggers on `pull_request` for `source/terraform/**` and passes `environment: development`.
- Cleanup runs weekly and on dispatch. The `scope` input is `all` for closed or merged PRs, or `pr-<n>` for one PR in any state. The caller passes `scope: ${{ inputs.scope || 'all' }}` and `environment: development`, which must equal `development-environment`.
- Cleanup has no gate and only touches `pr-*` workspaces in that environment.

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
