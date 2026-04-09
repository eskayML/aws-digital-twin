#!/bin/bash
set -e

ENVIRONMENT=${1:-dev}          # dev | test | prod
PROJECT_NAME=${2:-twin}

echo "🚀 Deploying ${PROJECT_NAME} to ${ENVIRONMENT}..."

# 1. Build Lambda package
cd "$(dirname "$0")/.."        # project root
echo "📦 Building Lambda package..."
(cd backend && uv run deploy.py)

# 2. Terraform workspace & apply
cd terraform

# The S3 backend requires configuration since it's empty in backend.tf
STATE_BUCKET="twin-terraform-state-${AWS_ACCOUNT_ID}"

terraform init \
  -backend-config="bucket=${STATE_BUCKET}" \
  -backend-config="key=github-actions.tfstate" \
  -backend-config="region=${DEFAULT_AWS_REGION}" \
  -backend-config="dynamodb_table=twin-terraform-locks" \
  -backend-config="encrypt=true" \
  -reconfigure \
  -input=false

if ! terraform workspace list | grep -q "$ENVIRONMENT"; then
  terraform workspace new "$ENVIRONMENT"
else
  terraform workspace select "$ENVIRONMENT"
fi

# Use prod.tfvars for production environment
COMMON_VARS=(-var="project_name=$PROJECT_NAME" -var="environment=$ENVIRONMENT" -var="github_repository=${GITHUB_REPOSITORY:-eskayML/aws-digital-twin}" -var="openai_api_key=$OPENAI_API_KEY")

if [ "$ENVIRONMENT" = "prod" ]; then
  TF_APPLY_CMD=(terraform apply -var-file=prod.tfvars "${COMMON_VARS[@]}" -auto-approve)
else
  TF_APPLY_CMD=(terraform apply "${COMMON_VARS[@]}" -auto-approve)
fi

echo "🎯 Applying Terraform..."
"${TF_APPLY_CMD[@]}"

API_URL=$(terraform output -raw api_gateway_url)
FRONTEND_BUCKET=$(terraform output -raw s3_frontend_bucket)
CUSTOM_URL=$(terraform output -raw custom_domain_url 2>/dev/null || true)

# 3. Build + deploy frontend
cd ../frontend

# Create production environment file with API URL
echo "📝 Setting API URL for production..."
echo "NEXT_PUBLIC_API_URL=$API_URL" > .env.production

# Use pnpm as requested for a reliable build
echo "🏗️ Installing frontend dependencies with pnpm..."
pnpm install
pnpm run build
aws s3 sync ./out "s3://$FRONTEND_BUCKET/" --delete
cd ..

# 4. Final messages
echo -e "\n✅ Deployment complete!"
echo "🌐 CloudFront URL : $(terraform -chdir=terraform output -raw cloudfront_url)"
if [ -n "$CUSTOM_URL" ]; then
  echo "🔗 Custom domain  : $CUSTOM_URL"
fi
echo "📡 API Gateway    : $API_URL"
