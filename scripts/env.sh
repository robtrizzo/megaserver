#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
ROOT_DIR=${SCRIPT_DIR}/..
cd ${ROOT_DIR}
INFR_DIR=${ROOT_DIR}/infra
[[ -f "${ROOT_DIR}/.env.local" ]] && source "${ROOT_DIR}/.env.local"

REGION="${REGION:-us-east-1}"
ENVIRONMENT="${ENVIRONMENT:-dev}"
VERSION="${VERSION:-main}"

usage() {
  echo "Usage: $0 standup|teardown [OPTIONS]"
  echo ""
  echo "Terraform and environment management only. For code/Docker/ECS deploys use scripts/deploy.sh."
  echo ""
  echo "Commands:"
  echo "  standup    Create or update the full environment (Terraform apply)."
  echo "  teardown   Destroy the environment (Terraform destroy)."
  echo ""
  echo "Options:"
  echo "  -r, --region REGION       AWS region (default: \$REGION or us-east-1)"
  echo "  -e, --environment ENV     Environment name (default: \$ENVIRONMENT or dev)"
  echo "  -v, --version VERSION     Deployment version for cluster naming (default: \$VERSION or main)"
  echo "  -h, --help                Show this help"
  exit 0
}

cmd=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    standup|teardown) cmd="$1"; shift ;;
    -r|--region) REGION="$2"; shift 2 ;;
    -e|--environment) ENVIRONMENT="$2"; shift 2 ;;
    -v|--version) VERSION="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown option or command: $1"; usage ;;
  esac
done

if [[ -z "$cmd" ]]; then
  echo "Missing command: standup or teardown"
  usage
fi

for c in aws terraform; do
  if ! command -v "$c" &>/dev/null; then
    echo "Missing required command: $c"
    exit 1
  fi
done

export AWS_SHARED_CREDENTIALS_FILE="${AWS_SHARED_CREDENTIALS_FILE:-$HOME/.aws/credentials}"
[[ -f "$AWS_SHARED_CREDENTIALS_FILE" ]] || { echo "AWS credentials file not found: $AWS_SHARED_CREDENTIALS_FILE"; exit 1; }

APP_VERSION="${APP_VERSION:-$(git rev-parse --short HEAD 2>/dev/null)}"
[[ -n "${AWS_ACCOUNT_ID:-}" ]] || { echo "AWS_ACCOUNT_ID not set. Add it to .env.local."; exit 1; }

TF_VARS=(-var "aws_account_id=$AWS_ACCOUNT_ID" -var "creds_file=$AWS_SHARED_CREDENTIALS_FILE" -var "region=$REGION" -var "environment=$ENVIRONMENT" -var "deploy_version=$VERSION" -var "app_version=$APP_VERSION")

echo "Initializing Terraform"
terraform -chdir="${INFR_DIR}" init

if [[ "$cmd" == "standup" ]]; then
  echo "Standing up environment (Terraform apply): region=$REGION environment=$ENVIRONMENT version=$VERSION"
  terraform -chdir="${INFR_DIR}" apply -auto-approve "${TF_VARS[@]}"
  echo "Standup complete."
elif [[ "$cmd" == "teardown" ]]; then
  echo "Tearing down environment (Terraform destroy): region=$REGION environment=$ENVIRONMENT version=$VERSION"
  terraform -chdir="${INFR_DIR}" destroy -auto-approve "${TF_VARS[@]}"
  echo "Teardown complete."
fi
