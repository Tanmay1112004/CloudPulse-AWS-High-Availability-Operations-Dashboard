# Run CloudPulse with Terraform (PowerShell and WSL)

This guide describes how to launch the existing CloudPulse project. It does not change the application or provision anything by itself. Terraform commands that use AWS create billable resources, so review the plan and account before applying it.

## 1. Run the dashboard locally (no AWS)

Open PowerShell in the project folder:

```powershell
python --version
python app/server.py
```

Open <http://127.0.0.1:8080>. The local counter is in memory. Stop the server with `Ctrl+C`.

## 2. Install and configure AWS tools

For AWS deployment you need an AWS account, AWS CLI v2, Terraform 1.5 or later, and Bash. WSL Ubuntu is recommended because the deployment and cleanup scripts are Bash scripts.

In WSL, install AWS CLI and Terraform using their official installation instructions. Configure the AWS CLI with `aws configure` or your approved AWS SSO flow, then confirm the selected identity:

```bash
aws sts get-caller-identity
aws configure get region
terraform version
```

Do not put AWS keys in project files or commit credentials.

## 3. Open the project from WSL

If the project is in the Windows Downloads directory, WSL usually mounts it under `/mnt/c`:

```bash
cd /mnt/c/Users/Dell/Downloads/aws-ha-dashboard-project/aws-ha-dashboard
```

If the project is in a different location, change the path to match. Keeping active Terraform projects in the WSL filesystem (for example, `~/projects/aws-ha-dashboard`) can improve file performance.

## 4. Initialize, format, validate, and review the plan

Choose the AWS region and a short lowercase project name. The name must start with a letter and use lowercase letters, digits, or hyphens.

```bash
export AWS_REGION=us-east-1
export STACK_NAME=cloudpulse-demo

aws sts get-caller-identity
terraform -chdir=terraform init
terraform -chdir=terraform fmt -recursive
terraform -chdir=terraform validate
terraform -chdir=terraform plan \
  -var="aws_region=$AWS_REGION" \
  -var="project_name=$STACK_NAME"
```

Read the complete plan. Confirm the AWS account, region, resource names, and expected cost before applying. The stack creates an internet-facing HTTP load balancer and EC2 capacity across two Availability Zones; these resources can incur charges while they exist.

## 5. Apply with Terraform

From WSL, the included deploy script initializes and applies Terraform using the `AWS_REGION` and `STACK_NAME` environment variables:

```bash
./deploy.sh
```

It prints the dashboard URL when Terraform completes. The first EC2 boot and health checks can take several minutes.

Alternatively, apply directly with Terraform after reviewing the plan:

```bash
terraform -chdir=terraform apply \
  -var="aws_region=$AWS_REGION" \
  -var="project_name=$STACK_NAME"
```

Terraform asks for confirmation unless you add `-auto-approve`. Do not use `-auto-approve` without reviewing the plan.

## 6. Verify the deployment

Get the URL from Terraform and check the application endpoints:

```bash
URL="$(terraform -chdir=terraform output -raw website_url)"
printf 'Dashboard: %s\n' "$URL"
curl --fail --show-error "$URL/health"
curl --fail --show-error "$URL/health/ready"
curl --fail --show-error "$URL/api/status"
curl --fail --show-error "$URL/api/visits"
```

Open the printed URL in your browser. The supplied live smoke-check script can also be run from WSL:

```bash
./scripts/test.sh
```

Use AWS Console or AWS CLI to verify target health and the Auto Scaling Group. The dashboard reports application telemetry; it is not a substitute for AWS control-plane health checks.

## 7. Destroy the stack when finished

From WSL, run the cleanup script:

```bash
./cleanup.sh
```

It shows the AWS identity and asks you to type `DESTROY`. Check the identity, region, project name, and Terraform state before confirming. Keep the state until destroy succeeds, then verify that the project resources were removed.

PowerShell can run Terraform directly too. From the project folder, review the AWS identity and plan first:

```powershell
$env:AWS_REGION = "us-east-1"
$projectName = "cloudpulse-demo"
aws sts get-caller-identity
terraform -chdir=terraform init
terraform -chdir=terraform validate
terraform -chdir=terraform plan `
  "-var=aws_region=$env:AWS_REGION" `
  "-var=project_name=$projectName"
```

After reviewing the plan, apply interactively:

```powershell
terraform -chdir=terraform apply `
  "-var=aws_region=$env:AWS_REGION" `
  "-var=project_name=$projectName"
```

To destroy from PowerShell, use the same variable values and review the prompt carefully:

```powershell
terraform -chdir=terraform destroy `
  "-var=aws_region=$env:AWS_REGION" `
  "-var=project_name=$projectName"
```
