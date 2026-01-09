# core-cloud-workflow-terraform-actions

## Overview
This repository contains composite actions for individual terraform command fragments that you can use individually
- `terraform init`
- `terraform fmt`
- `terraform validate`
- `terraform plan`
- `terraform apply`

and a complete [Terraform workflow file](https://github.com/UKHomeOffice/core-cloud-workflow-terraform-actions/blob/main/.github/workflows/standard-pipeline.yml) when you just want to use a complete Terraform pipeline.

NOTE: - As `terraform lint` is not part of the official Terraform CLI, its composite action can be found [here](https://github.com/UKHomeOffice/core-cloud-workflow-tflint-scan/blob/main/action.yaml) but is included in the complete workflow file within this repo.

## Pre-requisites
1: Create a Github Environment
2: Create a Github Environment secret called ACCOUNT_ID and add the AWS Account ID to it.

## Features
- If absent, the `terraform init` fragment will bootstrap your defined state bucket and DynamoDB table.
- A customised Github Actions summary page that provides at-a-glance debugging features and current configuration used without needing to delve into the steps or files.
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
        uses: UKHomeOffice/core-cloud-workflow-terraform-actions/.github/workflows/standard-pipeline.yml@main
        with:
          working-directory: '.'
          github-environment: '<GITHUB_ENVIRONMENT_NAME>'
          state-bucket: '<DESIRED_NAME_OF_S3_BUCKET_FOR_STORING_STATE_FILES>'
          state-dynamodb-table: '<DESIRED_DYNAMODB_TABLE_NAME>'
          role-to-assume: '<AWS_ROLE_THAT_HAS_PERMISSIONS_TO_CREATE_AND_DESTROY_RESOURCES>'
        secrets:
          account_id: ${{ secrets.ACCOUNT_ID }}

## Usage of composite actions
Please refer to the [Terraform workflow file](https://github.com/UKHomeOffice/core-cloud-workflow-terraform-actions/blob/main/.github/workflows/standard-pipeline.yml) for examples of using composite actions.
NOTE: Running `terraform validate` has conditional logic to initialise the terraform code, so you don't need to add the `terraform init` fragment beforehand.
