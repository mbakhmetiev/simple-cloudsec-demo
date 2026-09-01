#!/usr/bin/env bash
set -euo pipefail

REGION="us-east-1"
REGISTRY="925517157861.dkr.ecr.us-east-1.amazonaws.com"
REPO="simple-cloudsec-demo"

aws ecr get-login-password --region "$REGION" |
  skopeo login --username AWS --password-stdin "$REGISTRY"

grep 'image:' kubernetes.yaml |
  awk -F'"' '{print $2}' |
  while read -r src; do

    # Skip images already pointing to our private ECR
    if [[ "$src" == "$REGISTRY/"* ]]; then
      echo "Skipping already mirrored image: $src"
      continue
    fi

    image="${src##*/}"
    repo_name="$REPO/${image%:*}"
    dst="$REGISTRY/$repo_name:${image##*:}"

    echo
    echo "$src"
    echo "  -> $dst"

    aws ecr describe-repositories \
      --repository-names "$repo_name" \
      --region "$REGION" >/dev/null 2>&1 ||
      aws ecr create-repository \
        --repository-name "$repo_name" \
        --region "$REGION" >/dev/null

    skopeo \
      --override-os linux \
      --override-arch amd64 \
      copy \
      "docker://$src" \
      "docker://$dst"

    sed -i "s|$src|$dst|g" kubernetes.yaml
  done
