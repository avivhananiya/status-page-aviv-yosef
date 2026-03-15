#!/usr/bin/env bash
# Bootstrap script: creates the S3 bucket and DynamoDB table for Terraform remote state.
# Run this ONCE before running `terraform init`.

set -euo pipefail

BUCKET="yosef-aviv-status-page-tf-state"
TABLE="yosef-aviv-status-page-tf-lock"
REGION="us-east-1"

echo "Creating S3 bucket for Terraform state..."
aws s3api create-bucket \
  --bucket "$BUCKET" \
  --region "$REGION"

echo "Enabling versioning on state bucket..."
aws s3api put-bucket-versioning \
  --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled

echo "Blocking public access on state bucket..."
aws s3api put-public-access-block \
  --bucket "$BUCKET" \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

echo "Enabling default encryption on state bucket..."
aws s3api put-bucket-encryption \
  --bucket "$BUCKET" \
  --server-side-encryption-configuration \
    '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"aws:kms"},"BucketKeyEnabled":true}]}'

echo "Creating DynamoDB table for state locking..."
aws dynamodb create-table \
  --table-name "$TABLE" \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region "$REGION"

echo ""
echo "Backend infrastructure created successfully."
echo "You can now run: terraform init"
