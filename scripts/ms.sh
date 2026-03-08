#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
ROOT_DIR=${SCRIPT_DIR}/..
INFR_DIR="${ROOT_DIR}/infra"
cd ${ROOT_DIR}
[[ -f "${ROOT_DIR}/.env.local" ]] && source "${ROOT_DIR}/.env.local"

REGION="${REGION:-us-east-1}"
ENVIRONMENT="${ENVIRONMENT:-dev}"
VERSION="${VERSION:-$(git branch --show-current 2>/dev/null || echo 'main')}"
TAG="${TAG:-}"
DOCKER_NO_CACHE=false

CMD=""

usage() {
  echo "Usage: $0 COMMAND [OPTIONS]"
  echo ""
  echo "Code, Docker, and ECS management only (no Terraform). Use scripts/env.sh for environment standup/teardown."
  echo ""
  echo "Commands:"
  echo "  build             Build and push the Docker image."
  echo "  deploy            Deploy current image. No build/push."
  echo "  build-deploy|bd   Build, push, and deploy. Short form: bd"
  echo "  list              List ECR image tags and current ECS deployment info."
  echo "  stop              Stop the ECS API service (scale to 0) via AWS ECS."
  echo "  start             Start the ECS API service (scale to 1) via AWS ECS."
  echo ""
  echo "Options:"
  echo "  -r, --region REGION       AWS region (default: \$REGION or us-east-1)"
  echo "  -e, --environment ENV     Environment (default: \$ENVIRONMENT or dev)"
  echo "  -v, --version VERSION     Deployment version for cluster naming (default: git branch)"
  echo "  -t, --tag TAG             Image tag (default: git short sha)"
  echo "  -f, --force               Docker build with --no-cache (build/build-deploy only)"
  echo "  -h, --help                Show this help"
  exit 0
}

# Parse command (first non-option) and options
while [[ $# -gt 0 ]]; do
  case "$1" in
    build|deploy|build-deploy|bd|list|stop|start)
      if [[ -z "$CMD" ]]; then CMD="$1"; shift; else echo "Unknown option: $1"; usage; fi
      ;;
    -r|--region) REGION="$2"; shift 2 ;;
    -e|--environment) ENVIRONMENT="$2"; shift 2 ;;
    -v|--version) VERSION="$2"; shift 2 ;;
    -t|--tag) TAG="$2"; shift 2 ;;
    -f|--force) DOCKER_NO_CACHE=true; shift ;;
    -h|--help) usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

# Default command
if [[ -z "$CMD" ]]; then
  echo "Missing command: build, deploy, build-deploy, list, stop, or start"
  usage
  exit 1
fi

# Normalize bd -> build-deploy
if [[ "$CMD" == "bd" ]]; then
  CMD="build-deploy"
fi

VERSION_SAFE="${VERSION//\//-}"
# Instance naming includes version (e.g. dev-main); cluster/service/task are environment-only (e.g. dev).
INSTANCE_NAME="${ENVIRONMENT}-${VERSION_SAFE}"
REPO_NAME="megaserver/megaserver-api"
CLUSTER_NAME="megaserver-${ENVIRONMENT}"
SERVICE_NAME="megaserver-api-${ENVIRONMENT}"
TASK_FAMILY="megaserver-api-${ENVIRONMENT}"

if [[ "$CMD" == "list" ]]; then
  for c in aws; do
    if ! command -v "$c" &>/dev/null; then echo "Missing: $c"; exit 1; fi
  done
  export AWS_SHARED_CREDENTIALS_FILE="${AWS_SHARED_CREDENTIALS_FILE:-$HOME/.aws/credentials}"
  echo "=== ECS cluster: ${CLUSTER_NAME} ==="
  aws ecs describe-services --cluster "$CLUSTER_NAME" --services "$SERVICE_NAME" \
    --region "$REGION" --query 'services[0].{taskDefinition:taskDefinition,runningCount:runningCount,desiredCount:desiredCount}' --output table 2>/dev/null || echo "(cluster or service not found)"
  exit 0
fi

if [[ "$CMD" == "stop" ]]; then
  for c in aws; do
    if ! command -v "$c" &>/dev/null; then echo "Missing: $c"; exit 1; fi
  done
  export AWS_SHARED_CREDENTIALS_FILE="${AWS_SHARED_CREDENTIALS_FILE:-$HOME/.aws/credentials}"
  [[ -f "$AWS_SHARED_CREDENTIALS_FILE" ]] || { echo "AWS credentials file not found: $AWS_SHARED_CREDENTIALS_FILE"; exit 1; }
  echo "Stopping ECS API service (desired-count=0): cluster=$CLUSTER_NAME service=$SERVICE_NAME"
  aws ecs update-service --cluster "$CLUSTER_NAME" --service "$SERVICE_NAME" --desired-count 0 --region "$REGION" >/dev/null
  echo "ECS API service scaled to 0."
  exit 0
fi

if [[ "$CMD" == "start" ]]; then
  for c in aws terraform; do
    if ! command -v "$c" &>/dev/null; then echo "Missing: $c"; exit 1; fi
  done
  export AWS_SHARED_CREDENTIALS_FILE="${AWS_SHARED_CREDENTIALS_FILE:-$HOME/.aws/credentials}"
  [[ -f "$AWS_SHARED_CREDENTIALS_FILE" ]] || { echo "AWS credentials file not found: $AWS_SHARED_CREDENTIALS_FILE"; exit 1; }
  INFR_DIR="${ROOT_DIR}/infra"
  # Use Terraform's api_desired_count (same as env.sh / main.tf)
  DESIRED_COUNT=$(terraform -chdir="${INFR_DIR}" output -raw api_desired_count 2>/dev/null) || DESIRED_COUNT=1
  echo "Starting ECS API service (desired-count=$DESIRED_COUNT): cluster=$CLUSTER_NAME service=$SERVICE_NAME"
  aws ecs update-service --cluster "$CLUSTER_NAME" --service "$SERVICE_NAME" --desired-count "$DESIRED_COUNT" --region "$REGION" >/dev/null
  echo "ECS API service scaled to $DESIRED_COUNT."
  exit 0
fi

DO_BUILD=false
DO_DEPLOY=false
case "$CMD" in
  build)         DO_BUILD=true ;;
  deploy)        DO_DEPLOY=true ;;
  build-deploy)  DO_BUILD=true; DO_DEPLOY=true ;;
  *) echo "Unknown command: $CMD"; usage ;;
esac

# Build / push / deploy path
for cmd in aws docker; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Missing required command: $cmd"
    exit 1
  fi
done

export AWS_SHARED_CREDENTIALS_FILE="${AWS_SHARED_CREDENTIALS_FILE:-$HOME/.aws/credentials}"
[[ -f "$AWS_SHARED_CREDENTIALS_FILE" ]] || { echo "AWS Credentials file not found: $AWS_SHARED_CREDENTIALS_FILE"; exit 1; }

[[ -n "$TAG" ]] || TAG="$(git rev-parse --short HEAD 2>/dev/null)"
[[ -n "$TAG" ]] || { echo "TAG not set."; exit 1; }

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
[[ -n "$ACCOUNT_ID" ]] || { echo "Could not determine AWS account id."; exit 1; }

ECR_URI="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${REPO_NAME}"
REGISTRY="${ECR_URI%%/*}"

echo "Ensuring ECR repo exists: $REPO_NAME"
aws ecr describe-repositories --repository-names "$REPO_NAME" --region "$REGION" &>/dev/null || \
  aws ecr create-repository --repository-name "$REPO_NAME" --region "$REGION"

if [[ "$DO_BUILD" == true ]]; then
  echo "Logging into ECR registry"
  aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$REGISTRY"

  echo "Building image: ${ECR_URI}:${TAG}"
  DOCKER_BUILD_ARGS=(-f "${ROOT_DIR}/Dockerfile" -t "${ECR_URI}:${TAG}" --build-arg "DEV_ENV=${ENVIRONMENT}" --secret "id=env_vars,src=${ROOT_DIR}/.env.local")
  [[ "$DOCKER_NO_CACHE" == true ]] && DOCKER_BUILD_ARGS+=(--no-cache)
  docker build "${DOCKER_BUILD_ARGS[@]}" .

  echo "Pushing image: ${ECR_URI}:${TAG}"
  docker push "${ECR_URI}:${TAG}"
fi

if [[ "$DO_DEPLOY" == true ]]; then
  if ! command -v jq &>/dev/null; then
    echo "Missing required command: jq (needed to update ECS task definition)"
    exit 1
  fi
  echo "Deploying to ECS: new task definition revision with image ${ECR_URI}:${TAG}"
  TASK_JSON=$(aws ecs describe-task-definition --task-definition "$TASK_FAMILY" --region "$REGION" 2>/dev/null) || {
    echo "Task definition not found: $TASK_FAMILY. Run scripts/env.sh standup first to create the environment."
    exit 1
  }
  NEW_TASK_JSON=$(echo "$TASK_JSON" | jq --arg IMAGE "${ECR_URI}:${TAG}" '
    .taskDefinition
    | .containerDefinitions[0].image = $IMAGE
    | del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .compatibilities, .registeredAt, .registeredBy)
  ')
  aws ecs register-task-definition --region "$REGION" --cli-input-json "$NEW_TASK_JSON" >/dev/null
  aws ecs update-service --cluster "$CLUSTER_NAME" --service "$SERVICE_NAME" --task-definition "$TASK_FAMILY" --force-new-deployment --region "$REGION" >/dev/null
  echo "ECS service update triggered."
fi

echo "Done."
