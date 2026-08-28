# SIMPLE CLOUD SECURITY DEMO

This project is based on the original work of the [retail-store-sample-app](https://github.com/aws-containers/retail-store-sample-app) team. The motivation behind my project is to have a way to easily spin up an environment in AWS that can be used to reference the infrastructure to onboard into a CNAPP platform such as PaloAlto Networks Prisma Cloud or Cortex Cloud

## Domain name

In my project I'll be using registered domain name that can be used to access the web shop during the demo. It will remain inaccessible outside of the active demo I'm running for customers or colleagues

I've registered mine with [OVHcoud](https://www.ovhcloud.com/fr/domains/tld/fr/)

## Deploy an `eks` cluster

1. Install `eksctl` as per this [guide](https://docs.aws.amazon.com/eks/latest/eksctl/installation.html) and `aws cli` as per this [guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html#getting-started-install-instructions)

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

Specify your region, to run the script pass the access key file as an argument to the script

| `$ aws_auth.sh <access-key.csv>`

1. Create the eks cluster

```bash
export eks_region="us-east-1"
export eks_version="1.31"
export eks_name="deb-test100"
eksctl create cluster --name ${eks_name} --version ${eks_version} \
--region ${eks_region} --nodegroup-name workers --node-type t3.medium \
--nodes 3 --nodes-min 1 --nodes-max 3 --managed
eksctl get cluster
aws eks update-kubeconfig --name ${eks_name} --region ${eks_region}
```

Verify the cluster is running

```bash
kubectl get nodes
```

1. Prepare the images

The idea of this cloud security demo project is to have all the resources in our control
In the reference [retail-store-sample-app](https://github.com/aws-containers/retail-store-sample-app) project the images are stored in the public AWS registry. We'll move all images to our AWS project to be able to onboard that repository for vulnerability scanning with the CNAPP solution we'll be demoing.

From the reference project `kubernetes` installation option we can locate the yaml manifest that we would use to deploy the target infrastructure

`$wget https://github.com/aws-containers/retail-store-sample-app/releases/latest/download/kubernetes.yaml`

We need to create a private registry and then use it int the script below which parses the actual image locations in puclic aws ecr and copy them with `skopeo` to our private registry and then update the `kubernetes.yaml` with new images location

```bash
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
```

Run the script `copy-images.sh` and the script is complete we should be able to deploy our web-shop with `kubernetes`

```bash
kubectl apply -f https://github.com/aws-containers/retail-store-sample-app/releases/latest/download/kubernetes.yaml
kubectl wait --for=condition=available deployments --all
```
