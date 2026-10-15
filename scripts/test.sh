#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
URL="$(terraform -chdir="$ROOT_DIR/terraform" output -raw website_url)"
echo "Testing $URL"
for path in /health /health/ready /api/status /; do
  echo
  echo "== $path =="
  curl --fail --silent --show-error --max-time 15 "${URL}${path}" | head -c 1600
  echo
done
