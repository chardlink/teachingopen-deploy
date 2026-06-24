#!/usr/bin/env bash
set -euo pipefail

IMAGE_NAMESPACE="${IMAGE_NAMESPACE:-yourdockerhub}"
IMAGE_TAG="${IMAGE_TAG:-2.8.0}"

docker push "${IMAGE_NAMESPACE}/teachingopen-app:${IMAGE_TAG}"
docker push "${IMAGE_NAMESPACE}/teachingopen-web:${IMAGE_TAG}"
docker push "${IMAGE_NAMESPACE}/teachingopen-mysql:${IMAGE_TAG}"

echo
echo "推送完成："
echo "  ${IMAGE_NAMESPACE}/teachingopen-app:${IMAGE_TAG}"
echo "  ${IMAGE_NAMESPACE}/teachingopen-web:${IMAGE_TAG}"
echo "  ${IMAGE_NAMESPACE}/teachingopen-mysql:${IMAGE_TAG}"
