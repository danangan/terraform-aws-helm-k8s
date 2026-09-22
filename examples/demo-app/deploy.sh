#!/bin/bash

set -euo pipefail

# This scripts uses docker or podman as container engine. It'll use docker by default.
if command -v docker &>/dev/null; then
  echo "Docker detected in the system, using docker as engine"
  CONTAINER_ENGINE=docker
elif command -v podman &>/dev/null; then
  echo "Docker is not available in the system, using podman as fallback"
  CONTAINER_ENGINE=podman
else
  echo "Error: neither docker nor podman found in PATH" >&2
  exit 1
fi

ECR_REPO_URL="$(terraform -chdir=../demo-k8s-cluster output -raw ecr_repository_url)"
REGISTRY="${ECR_REPO_URL%%/*}"
TAG="$(date +%Y%m%d%H%M%S)"

echo "Logging in to ECR..."

aws ecr get-login-password --region us-east-1 \
  | ${CONTAINER_ENGINE} login --username AWS --password-stdin "${REGISTRY}"

echo "Building and pushing ${ECR_REPO_URL}:${TAG}..."

"${CONTAINER_ENGINE}" build -t "${ECR_REPO_URL}:${TAG}" .
"${CONTAINER_ENGINE}" push "${ECR_REPO_URL}:${TAG}"

echo "Updating kubeconfig via aws cmd..."
aws eks update-kubeconfig --region us-east-1 --name platform-cluster

echo "Deploying via Helm..."
helm upgrade --install app . \
  --set image.repository="${ECR_REPO_URL}" \
  --set image.tag="${TAG}"

echo "Done!"
