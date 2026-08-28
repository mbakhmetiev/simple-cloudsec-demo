#!/usr/bin/bash
set +x

region="us-east-1"

IFS=, && read keyid key <<<$(tail -n 1 $1)

aws configure set aws_access_key_id $keyid
aws configure set aws_secret_access_key $key
aws configure set default.region $region

aws ec2 describe-key-pairs &>/dev/null

if [ $? -eq 0 ]; then
  echo "aws login successful"
else
  echo "aws login failed"
fi
