# SIMPLE CLOUD SECURITY DEMO

This project is based on the original work of the [retail-store-sample-app](https://github.com/aws-containers/retail-store-sample-app) team. The motivation behind my project is to have a way to easily spin up an environment in AWS that can be used to reference the infrastructure to onboard into a CNAPP platform such as PaloAlto Networks Prisma Cloud or Cortex Cloud

## Domain name

In my project I'll be using registered domain name that can be used to access the web shop during the demo. It will remain inaccessible outside of the active demo I'm running for customers or colleagues

I've registered mine with [OVHcoud](https://www.ovhcloud.com/fr/domains/tld/fr/)

The web-shop created with this project can be used without a domain name, in the kubernetes deployment section below, after the microservices are deployed, the web-shop can be accessed via the URL of `ui` kubernetes service. The DNS, TLS ans ALB/Ingress section are for the deployment of the web-shop accessible via https

## Deploy an `eks` cluster

### 1. Install `eksctl` and `aws cli`

Use this [guide](https://docs.aws.amazon.com/eks/latest/eksctl/installation.html) to install `eksctl` and `aws cli` as per this [guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html#getting-started-install-instructions)

### 2. Authenticate to AWS

Dkownload the access key and use this script to verify the authentication status

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

### 3. Create the eks cluster

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

## Deploy the web-shop with kubernetes

### 1. Prepare the images

The idea of this cloud security demo project is to have all the resources in our control
In the reference [retail-store-sample-app](https://github.com/aws-containers/retail-store-sample-app) project the images are stored in the public AWS registry. We'll move all images to our AWS project to be able to onboard that repository for vulnerability scanning with the CNAPP solution we'll be demoing.

From the reference project `kubernetes` installation option we can locate the yaml manifest that we would use to deploy the target infrastructure

`$wget https://github.com/aws-containers/retail-store-sample-app/releases/latest/download/kubernetes.yaml`

We need to create a private registry and then use it int the script below which parses the actual image locations in puclic aws ecr and copy them with `skopeo` to our private registry and then update the `kubernetes.yaml` with new images location

```bash
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
```

### 2. Kubernetes deployment

Run the script `copy-images.sh` and once the script is complete we should be able to deploy our web-shop with `kubernetes` with new images location

```bash
kubectl apply -f kubernetes.yaml
kubectl wait --for=condition=available deployments --all
```

Get the URL for the frontend load balancer like so:

`kubectl get svc ui`

To remove the application use kubectl again:

`kubectl delete -f kubernetes.yaml`

## Setup DNS and TLS certificate to access the web-shop via <https://cloudsec-demos.fr>

### 1. DNS Setup

We need to delegate `cloudsec-demos.fr` from OVHcloud to an AWS Route 53 public hosted zone.

Overall the process would follow these steps:

```bash
OVHcloud = domain registrar
        │
        │ NS delegation
        ▼
AWS Route 53 = authoritative DNS
        │
        └── shop.cloudsec-demos.fr → ALB
```

Create `Route 53` hosted zone

```bash
aws route53 create-hosted-zone \
  --name cloudsec-demos.fr \
  --caller-reference "$(date +%s)"
```

Check the zone was created

```bash
aws route53 list-hosted-zones-by-name \
  --dns-name cloudsec-demos.fr
```

We need `Zone ID` to retrive AWS authoritative nameservers

```bash
ZONE_ID=$(aws route53 list-hosted-zones-by-name \
  --dns-name cloudsec-demos.fr \
  --query "HostedZones[?Name=='cloudsec-demos.fr.'].Id | [0]" \
  --output text)

echo "$ZONE_ID"

aws route53 get-hosted-zone \
  --id "$ZONE_ID" \
  --query 'DelegationSet.NameServers' \
  --output table

-----------------------------
|       GetHostedZone       |
+---------------------------+
|  ns-430.awsdns-53.com     |
|  ns-1491.awsdns-58.org    |
|  ns-1823.awsdns-35.co.uk  |
|  ns-963.awsdns-56.net     |
+---------------------------+

```

Configure AWS zones at OVHcloud

Because OVHcloud remains the registrar, we need to change the domain's authoritative nameservers at OVH from the OVH DNS servers to those four AWS servers.

We changed its DNS delegation and thus domains will be transferred to AWS.
To verify:

```bash
dig NS cloudsec-demos.fr +short

ns-1823.awsdns-35.co.uk.
ns-430.awsdns-53.com.
ns-963.awsdns-56.net.
ns-1491.awsdns-58.org.
```

This confirms that Route 53 had become authoritative for the domain.

### 2. TLS certificate

Request the certificate

```bash
CERT_ARN=$(aws acm request-certificate \
  --domain-name cloudsec-demos.fr \
  --validation-method DNS \
  --region us-east-1 \
  --query CertificateArn \
  --output text)

echo "$CERT_ARN"
```

Get the validation record:

```bash
aws acm describe-certificate \
  --certificate-arn "$CERT_ARN" \
  --region us-east-1 \
  --query 'Certificate.DomainValidationOptions[0].ResourceRecord'
```

Create that CNAME in the existing Route 53 zone exactly as before, then wait for:

```bash
aws acm wait certificate-validated \
  --certificate-arn "$CERT_ARN" \
  --region us-east-1
```

Check the certificate and obtain the DNS validation record

```bash
aws acm describe-certificate \
  --certificate-arn "$CERT_ARN" \
  --region us-east-1 \
  --query 'Certificate.DomainValidationOptions'
```

Extract the validation CNAME name:

```bash
VALIDATION_NAME=$(aws acm describe-certificate \
  --certificate-arn "$CERT_ARN" \
  --region us-east-1 \
  --query 'Certificate.DomainValidationOptions[0].ResourceRecord.Name' \
  --output text)

echo "$VALIDATION_NAME"
```

Get the CNAME target:

```bash
VALIDATION_VALUE=$(aws acm describe-certificate \
  --certificate-arn "$CERT_ARN" \
  --region us-east-1 \
  --query 'Certificate.DomainValidationOptions[0].ResourceRecord.Value' \
  --output text)

echo "$VALIDATION_VALUE"
```

Get the existing Route 53 hosted-zone ID
We already had cloudsec-demos.fr delegated from OVHcloud to Route 53.

```bash
ZONE_ID=$(aws route53 list-hosted-zones-by-name \
  --dns-name cloudsec-demos.fr \
  --query "HostedZones[?Name=='cloudsec-demos.fr.'].Id | [0]" \
  --output text)

echo "$ZONE_ID"
```

Create the ACM validation CNAME in Route 53:

```bash
aws route53 change-resource-record-sets \
  --hosted-zone-id "$ZONE_ID" \
  --change-batch "{
    \"Changes\": [{
      \"Action\": \"UPSERT\",
      \"ResourceRecordSet\": {
        \"Name\": \"$VALIDATION_NAME\",
        \"Type\": \"CNAME\",
        \"TTL\": 300,
        \"ResourceRecords\": [{
          \"Value\": \"$VALIDATION_VALUE\"
        }]
      }
    }]
  }"
```

Verify the validation record directly against Route 53

```bash
dig CNAME "$VALIDATION_NAME" @ns-430.awsdns-53.com
```

Check ACM status

```bash
aws acm wait certificate-validated \
  --certificate-arn "$CERT_ARN" \
  --region us-east-1
```

Check if the certificate is issued

```bash
aws acm describe-certificate \
  --certificate-arn "$CERT_ARN" \
  --region us-east-1 \
  --query 'Certificate.Status' \
  --output text
```

### 3. Deploy the `ALB`

Set the variables to be referenced in the commands below

```bash
export CLUSTER_NAME=deb-test100
export AWS_REGION=us-east-1
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
```

Associate the cluster's OIDC provider:

```bash
eksctl utils associate-iam-oidc-provider \
  --cluster "$CLUSTER_NAME" \
  --region "$AWS_REGION" \
  --approve
```

Download the controller IAM policy:

```bash
curl -O \
https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.14.1/docs/install/iam_policy.json
```

Create the IAM policy:

```bash
aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file://iam_policy.json
```

Create the Kubernetes ServiceAccount and its IAM role:

```bash
eksctl create iamserviceaccount \
  --cluster "$CLUSTER_NAME" \
  --namespace kube-system \
  --name aws-load-balancer-controller \
  --attach-policy-arn "arn:aws:iam::$ACCOUNT_ID:policy/AWSLoadBalancerControllerIAMPolicy" \
  --override-existing-serviceaccounts \
  --region "$AWS_REGION" \
  --approve
```

Verify the ServiceAccount has an IAM role:

```bash
kubectl get sa aws-load-balancer-controller \
  -n kube-system \
  -o yaml
```

Install the ALB:

```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo update eks

helm install aws-load-balancer-controller \
  eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName="$CLUSTER_NAME" \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --version 1.14.0
```

Verify the load-balancer is installed and running:

```bash
kubectl get deployment -n kube-system aws-load-balancer-controller
```

### 4. Install the Ingress

The ingress `yaml` should reference earlier created `ACM certificate ARN` and the `ALB`

```bash
CERT_ARN=$(aws acm list-certificates \
  --region us-east-1 \
  --query "CertificateSummaryList[?DomainName=='cloudsec-demos.fr'].CertificateArn | [0]" \
  --output text)

echo "$CERT_ARN"

cat > ingress.yaml <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: retail-store-ingress
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80},{"HTTPS":443}]'
    alb.ingress.kubernetes.io/ssl-redirect: '443'
    alb.ingress.kubernetes.io/certificate-arn: $CERT_ARN

spec:
  ingressClassName: alb

  rules:
    - host: cloudsec-demos.fr
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: ui
                port:
                  number: 80
EOF
```

Create the Route 53 record for the apex domain
First get the ALB DNS name from the Ingress:

```bash
kubectl get ingress retail-store-ingress \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'; echo
```

Then get the ALB's hosted zone ID:

```bash
ALB_DNS=$(kubectl get ingress retail-store-ingress \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

ALB_ZONE_ID=$(aws elbv2 describe-load-balancers \
  --region us-east-1 \
  --query "LoadBalancers[?DNSName=='$ALB_DNS'].CanonicalHostedZoneId | [0]" \
  --output text)

echo "$ALB_DNS"
echo "$ALB_ZONE_ID"
```

Now get your Route 53 hosted-zone ID:

```bash
ZONE_ID=$(aws route53 list-hosted-zones-by-name \
  --dns-name cloudsec-demos.fr \
  --query "HostedZones[?Name=='cloudsec-demos.fr.'].Id | [0]" \
  --output text)

echo "$ZONE_ID"
```

Then create the apex A Alias:

```bash
aws route53 change-resource-record-sets \
  --hosted-zone-id "$ZONE_ID" \
  --change-batch "{
    \"Changes\": [{
      \"Action\": \"UPSERT\",
      \"ResourceRecordSet\": {
        \"Name\": \"cloudsec-demos.fr\",
        \"Type\": \"A\",
        \"AliasTarget\": {
          \"HostedZoneId\": \"$ALB_ZONE_ID\",
          \"DNSName\": \"$ALB_DNS\",
          \"EvaluateTargetHealth\": false
        }
      }
    }]
  }"
```

Verify:

```bash
dig +short cloudsec-demos.fr
```

Test the site is up and running and is ready to be used in a demo

```bash
curl -I https://cloudsec-demos.fr
```

And final verification, the vulenerabl web-shop for demo purposes is up and running

```bash
 curl -I https://cloudsec-demos.fr
HTTP/2 200
date: Tue, 01 Sep 2026 21:09:16 GMT
content-type: text/plain;charset=UTF-8
```

## Tear down the web-shop

To tear down the web-shop and to be able to recreate it easily for later use,
we would follow this procedure:

### 1. Keep what can be reused and takes time to recreate

```bash
ECR repositories + images
Route 53 hosted zone
cloudsec-demos.fr DNS delegation at OVH
ACM certificate + validation CNAME
local project files/scripts
```

First delete the Ingress and let AWS Load Balancer Controller remove the ALB:

```bash
kubectl delete -f ingress.yaml
```

Watch until the ALB disappears:

```bash
aws elbv2 describe-load-balancers \
  --region us-east-1 \
  --query 'LoadBalancers[].{Name:LoadBalancerName,DNS:DNSName}' \
  --output table
```

Then delete the application:

```bash
kubectl delete -f kubernetes.yaml
```

Then delete the EKS cluster:

```bash
eksctl delete cluster \
  --name deb-test100 \
  --region us-east-1
```

Delete the apex ALB alias because that particular ALB is about to disappear, every new ALB will get a new DNS name.

```bash
ZONE_ID=$(aws route53 list-hosted-zones-by-name \
  --dns-name cloudsec-demos.fr \
  --query "HostedZones[?Name=='cloudsec-demos.fr.'].Id | [0]" \
  --output text)
```
