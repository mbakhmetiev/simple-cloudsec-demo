# SIMPLE CLOUD SECURITY DEMO

This project is based on the original work of the [retail-store-sample-app](https://github.com/aws-containers/retail-store-sample-app) team. The motivation behind my project is to have a way to easily spin up an environment in AWS that can be used to reference the infrastructure to onboard into a CNAPP platform such as PaloAlto Networks Prisma Cloud or Cortex Cloud

## Domain name

In my project I'll be using registered domain name that can be used to access the web shop during the demo. It will remain inaccessible outside of the active demo I'm running for customers or colleagues

I've registered mine with [OVHcoud](https://www.ovhcloud.com/fr/domains/tld/fr/)

## Deploy eks cluster

1. Install `eksctl` as per this [guide](https://docs.aws.amazon.com/eks/latest/eksctl/installation.html) and aws cli as per this [guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html#getting-started-install-instructions)

2. Authenticate to AWS. Download the access key and use this script to verify the authentication status

```bash
#!/usr/bin/bash
set +x

region="us-east-1"

IFS=, && read keyid key <<< `tail -n 1 $1`

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
```

Specify your region, to run the script pass the access key file as an argument to the script `aws_auth.sh <access-key.csv>`

1. Create the eks cluster

```bash
export eks-region="us-east-1"
export eks-version="1.31"
export eks-name="deb-test100"
eksctl create cluster --name dev-test100 --version ${eks-version} --region ${eks-region} --nodegroup-name workers --node-type t3.medium --nodes 3 --nodes-min 1 --nodes-max 3 --managed
eksctl get cluster
aws eks update-kubeconfig --name ${eks-name} --region ${eks-region}
```
