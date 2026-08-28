#!/usr/bin/bash
set +x

region="us-east-1"

IFS=, && read keyid key <<< `tail -n 1 $1`

# AWS creds can be set as env variables
# export AWS_ACCESS_KEY_ID="anaccesskey"
# export AWS_SECRET_ACCESS_KEY="asecretkey"
# export AWS_DEFAULT_REGION="us-east-1"

aws configure set aws_access_key_id $keyid
aws configure set aws_secret_access_key $key
aws configure set default.region $region

aws ec2 describe-key-pairs &> /dev/null

if [ $? -eq 0 ] 
    then
        echo "aws login successful"
    else
        echo "aws login failed"
fi

