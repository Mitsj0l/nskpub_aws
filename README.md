# NPA Publisher AWS Cloudformation Deployment

Automated deployment solution for Netskope Private Access Publishers in AWS using CloudFormation.

![AWS ZTNA Architecture](https://raw.githubusercontent.com/Mitsj0l/nskpub_aws/refs/heads/main/AWS_ZTNA_1.png)

## Overview

This solution provides automated deployment of Netskope Private Access Publishers in AWS and the Netskope portal using CloudFormation. It consists of three components:

- CloudFormation template for AWS infrastructure
- Parameter file for configuration
- Bash deployment script for Netskope integration (forked from [Publisher-auto-register](https://github.com/sartioli/Publisher-auto-register) 🙌)

## Prerequisites

### AWS Requirements

- AWS Account with permissions for:
  - CloudFormation
  - EC2 (including Launch Templates and Auto Scaling)
  - IAM role creation
  - S3 access

- S3 bucket `ztnatemplate` containing `nsk-deployment.sh` (self-hosted with appropriate permissions)
  ```bash
  aws s3 cp nsk-deployment.sh s3://ztnatemplate/
  aws s3api put-bucket-policy --bucket ztnatemplate --policy file://bucket-policy.json
  ```

  Example bucket policy:
  ```json
  {
      "Version": "2012-10-17",
      "Statement": [
          {
              "Effect": "Allow",
              "Principal": {
                  "Service": "cloudformation.amazonaws.com"
              },
              "Action": "s3:GetObject",
              "Resource": "arn:aws:s3:::ztnatemplate/*"
          }
      ]
  }
  ```

### Netskope Requirements

- Tenant URL
- API Token with publisher management permissions
- Publisher upgrade profile ID (defaults to 1 for Default profile)

### Required Netskope API Permissions

The API token needs these permissions:
- `/api/v2/infrastructure/publisherupgradeprofiles` (Read)
- `/api/v2/infrastructure/publishers` (Read + Write)

## Deployment Process

### 1. Prepare Environment

1. Create S3 bucket and upload deployment script
2. Configure AWS CLI with appropriate credentials
3. Customize parameters file with your values

### 2. Deploy Stack
```bash
aws cloudformation create-stack \
--stack-name netskope-publishers \
--template-body file://netskope-publisher.yaml \
--parameters file://netskope-parameters.json \
--capabilities CAPABILITY_IAM
```


### 3. Deployment Flow

1. CloudFormation creates infrastructure
2. Launch Template provisions instances
3. UserData script downloads and configures deployment script
4. Deployment script:
   - Validates environment
   - Creates publisher in Netskope
   - Retrieves registration token
   - Completes publisher registration

## Monitoring and Troubleshooting

### Log Locations

- CloudFormation: AWS Console Events tab
- UserData execution: `/var/log/user-data.log`
- Deployment script: `/usr/local/bin/run-publisher-setup.sh`
- Publisher registration and operation details: 
  - `/home/ubuntu/logs/agent.txt`
  - `/home/ubuntu/logs/publisher_wizard.log`

## Security Features

1. Infrastructure:
   - Minimal IAM permissions
   - Security group limited to SSH
   - No public IP addresses by default (unless your existing network group uses one)

2. Authentication:
   - Key-based SSH only
   - API token and Netskope Tenant variables in AWS protected using NoEcho
   - Secure token retrieval process within the script

## Contributing
https://github.com/sartioli/Publisher-auto-register
