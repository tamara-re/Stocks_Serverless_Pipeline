# Stocks Pipeline — Deployment Guide

A serverless AWS pipeline that fetches daily stock data for AAPL, MSFT, GOOGL, AMZN, TSLA, and NVDA, identifies the biggest daily absolute mover, and serves the results through a REST API and static frontend.

---

## Architecture Overview

```
EventBridge (cron: Tue–Sat 7:00 UTC / 2:00 AM EST)
    └─> event_bridge_lambda/   — fetches prior day's quotes, computes winner, writes to DynamoDB

API Gateway GET /movers
    └─> api_gateway_lambda/    — reads last 7 winners from DynamoDB, returns JSON

S3 static site (frontend/index.html)
    └─> calls API Gateway → renders table of top absolute movers
```

---

## Prerequisites

Make sure the following are installed locally before starting:

- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.3.0
- [Python](https://www.python.org/downloads/) 3.12
- [Node.js](https://nodejs.org/) 20 (for the React frontend build)
- A GitHub account with this repository forked or cloned

---

## Step 1 — Get a Massive API Key

The pipeline uses the Massive API to fetch stock quotes.

1. Go to [massive.com](https://massive.com) and create an account
2. Navigate to your dashboard and generate an API key
3. Copy the key — you will need it in Step 4 and Step 6

---

## Step 2 — Create an AWS Account

If you do not already have one:

1. Go to [aws.amazon.com](https://aws.amazon.com) and click **Create an AWS Account**
2. Complete sign-up and log in to the AWS Console
3. Set your default region to **us-east-1** (N. Virginia)

---

## Step 3 — Create an IAM User for Deployments

This user will be used by GitHub Actions to deploy infrastructure.

1. In the AWS Console go to **IAM → Users → Create user**
2. Name it `github-actions-deployer`
3. Select **Attach policies directly** and attach the following:
   - `AmazonDynamoDBFullAccess`
   - `AWSLambda_FullAccess`
   - `AmazonAPIGatewayAdministrator`
   - `AmazonS3FullAccess`
   - `AmazonEventBridgeFullAccess`
   - `IAMFullAccess`
4. Create the user
5. Click into the user → **Security credentials** tab → **Create access key**
6. Choose **Application running outside AWS**
7. Copy the **Access Key ID** and **Secret Access Key** — you only see the secret once

---

## Step 4 — Configure the AWS CLI Locally

Configure the CLI with the credentials from Step 3 so you can run the setup commands below:

```bash
aws configure
```

Enter your Access Key ID, Secret Access Key, region (`us-east-1`), and output format (`json`).

---

## Step 5 — Create Terraform State Backend Resources

Terraform needs an S3 bucket to store its state file and a DynamoDB table for state locking. These must exist before the first `terraform apply`.

```bash
# Create the S3 bucket
aws s3api create-bucket \
  --bucket stocks-pipeline-tfstate-<YOUR_ACCOUNT_ID> \
  --region us-east-1

# Enable versioning so you can recover previous states
aws s3api put-bucket-versioning \
  --bucket stocks-pipeline-tfstate-<YOUR_ACCOUNT_ID> \
  --versioning-configuration Status=Enabled

# Create the DynamoDB lock table
aws dynamodb create-table \
  --table-name stocks-pipeline-tfstate-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

Replace `<YOUR_ACCOUNT_ID>` with your 12-digit AWS account ID. Then update the bucket name in the `backend "s3"` block in `terraform.tf` to match.

---

## Step 6 — Add Secrets to GitHub

1. Go to your GitHub repository → **Settings → Secrets and variables → Actions**
2. Add the following **repository secrets**:

| Secret name | Value |
|---|---|
| `AWS_ACCESS_KEY_ID` | Access Key ID from Step 3 |
| `AWS_SECRET_ACCESS_KEY` | Secret Access Key from Step 3 |
| `MASSIVE_API_KEY` | API key from Step 1 |

---

## Step 7 — Initialize Terraform Locally

Run this once locally to connect your project to the remote S3 backend. Terraform will prompt you to migrate any existing local state to S3.

```bash
terraform init
```

If prompted `Do you want to copy existing state to the new backend?` — type `yes`.

After this, your local `terraform.tfstate` is no longer used. All state is stored in S3.

---

## Step 8 — Deploy

Push to the `main` branch to trigger the GitHub Actions pipeline:

```bash
git add .
git commit -m "initial deploy"
git push origin main
```

The pipeline will:
1. Package both Lambda functions
2. Run `terraform plan`
3. Run `terraform apply` — provisioning all AWS infrastructure
4. Run `npm ci && npm run build` inside `frontend/` with `VITE_API_URL` set from Terraform output
5. Sync `frontend/dist/` to the S3 bucket with `aws s3 sync`

Monitor progress in your repository under the **Actions** tab.

---

## Step 9 — Verify

- **API**: `GET https://<id>.execute-api.us-east-1.amazonaws.com/movers` should return JSON
- **Frontend**: `http://stocks-frontend-<account-id>.s3-website-us-east-1.amazonaws.com` should show the table

The EventBridge rule fires Tuesday–Saturday at 7:00 AM UTC (2:00 AM EST) and populates data for the previous trading day. The first results will appear after the next scheduled run.

---

## Local Development

```bash
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

Create a `.env` file in the project root:

```
MASSIVE_API_KEY=your_key_here
```

Invoke a Lambda handler locally:

```bash
PYTHONPATH=. DYNAMODB_TABLE=stock-winners python -c "
from event_bridge_lambda.handler import lambda_handler
lambda_handler({}, {})"
```

---

## Step 10 — Teardown

To destroy all AWS infrastructure:

```bash
terraform destroy -var="massive_api_key=<KEY>"
```

Note: the Terraform state S3 bucket and DynamoDB lock table are not managed by Terraform and must be deleted manually in the AWS Console if no longer needed.
