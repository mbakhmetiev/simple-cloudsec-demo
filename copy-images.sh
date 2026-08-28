#!/usr/bin/env bash
set -e

REGISTRY="925517157861.dkr.ecr.us-east-1.amazonaws.com"
REPO="simple-cloudsec-demo"

aws ecr get-login-password --region us-east-1 |
  skopeo login --username AWS --password-stdin "$REGISTRY"

grep 'image:' kubernetes.yaml | awk -F'"' '{print $2}' | while read -r src; do
  image="${src##*/}"
  dst="$REGISTRY/$REPO/$image"

  aws ecr describe-repositories --repository-names "$REPO/${image%:*}" \
    --region us-east-1 >/dev/null 2>&1 ||
    aws ecr create-repository --repository-name "$REPO/${image%:*}" \
      --region us-east-1 >/dev/null

  skopeo copy "docker://$src" "docker://$dst"
  sed -i "s|$src|$dst|g" kubernetes.yaml
done
