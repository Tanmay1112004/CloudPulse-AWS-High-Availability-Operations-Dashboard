#!/usr/bin/env bash
set -euo pipefail
sudo apt-get update
sudo apt-get install -y git curl unzip zip python3 python3-pip python3-venv
echo "Install Terraform and AWS CLI using their official Ubuntu instructions:"
echo "https://developer.hashicorp.com/terraform/install"
echo "https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
