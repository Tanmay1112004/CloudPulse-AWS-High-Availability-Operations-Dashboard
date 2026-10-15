#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"
: "${AWS_REGION:=us-east-1}"
: "${STACK_NAME:=aws-capstone}"
export AWS_REGION STACK_NAME
aws sts get-caller-identity >/dev/null
terraform -chdir=terraform init
terraform -chdir=terraform validate
terraform -chdir=terraform apply \
  -var="aws_region=${AWS_REGION}" \
  -var="project_name=${STACK_NAME}" \
  -auto-approve
echo
echo "Dashboard URL:"
terraform -chdir=terraform output -raw website_url
