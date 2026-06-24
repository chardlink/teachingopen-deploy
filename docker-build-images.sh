#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAMESPACE="${IMAGE_NAMESPACE:-chardlink}"
IMAGE_TAG="${IMAGE_TAG:-2.8.0}"

cd "$ROOT_DIR"

docker build -f docker/app/Dockerfile -t "${IMAGE_NAMESPACE}/teachingopen-app:${IMAGE_TAG}" .
docker build -f docker/web/Dockerfile -t "${IMAGE_NAMESPACE}/teachingopen-web:${IMAGE_TAG}" .
docker build -f docker/mysql/Dockerfile -t "${IMAGE_NAMESPACE}/teachingopen-mysql:${IMAGE_TAG}" .

echo
echo "构建完成："
echo "  ${IMAGE_NAMESPACE}/teachingopen-app:${IMAGE_TAG}"
echo "  ${IMAGE_NAMESPACE}/teachingopen-web:${IMAGE_TAG}"
echo "  ${IMAGE_NAMESPACE}/teachingopen-mysql:${IMAGE_TAG}"
