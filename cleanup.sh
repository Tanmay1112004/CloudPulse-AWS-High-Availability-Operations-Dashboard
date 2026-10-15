#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"
: "${AWS_REGION:=us-east-1}"
: "${STACK_NAME:=aws-capstone}"
export AWS_REGION STACK_NAME
echo "About to DESTROY Terraform-managed resources for project: ${STACK_NAME}"
echo "Region: ${AWS_REGION}"
aws sts get-caller-identity
read -r -p "Type DESTROY to continue: " confirm
if [[ "$confirm" != "DESTROY" ]]; then
  echo "Cancelled."
  exit 1
fi
terraform -chdir=terraform destroy \
  -var="aws_region=${AWS_REGION}" \
  -var="project_name=${STACK_NAME}" \
  -auto-approve
