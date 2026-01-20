#!/bin/bash
set -e

# ========== 配置 ==========
FUNCTION_NAME="glm-chat"
REGION="us-east-1"
DYNAMODB_TABLE="glm-conversations"
ZHIPU_API_KEY="aeb5dc49d4bc45e790a8dacbe9bef17b.Ridz7zV1ctghiHMS"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "Account ID: $ACCOUNT_ID"
echo "Region: $REGION"

# ========== 1. 创建 DynamoDB 表 ==========
echo "Creating DynamoDB table..."
aws dynamodb create-table \
    --table-name $DYNAMODB_TABLE \
    --attribute-definitions \
        AttributeName=session_id,AttributeType=S \
        AttributeName=timestamp,AttributeType=N \
    --key-schema \
        AttributeName=session_id,KeyType=HASH \
        AttributeName=timestamp,KeyType=RANGE \
    --billing-mode PAY_PER_REQUEST \
    --region $REGION \
    2>/dev/null || echo "Table already exists or error creating"

# 启用 TTL
sleep 5
aws dynamodb update-time-to-live \
    --table-name $DYNAMODB_TABLE \
    --time-to-live-specification "Enabled=true, AttributeName=ttl" \
    --region $REGION \
    2>/dev/null || echo "TTL already enabled"

# ========== 2. 创建 IAM 角色 ==========
echo "Creating IAM role..."

cat > /tmp/trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

aws iam create-role \
    --role-name ${FUNCTION_NAME}-role \
    --assume-role-policy-document file:///tmp/trust-policy.json \
    2>/dev/null || echo "Role already exists"

cat > /tmp/permissions-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:PutItem",
        "dynamodb:GetItem",
        "dynamodb:Query"
      ],
      "Resource": "arn:aws:dynamodb:${REGION}:${ACCOUNT_ID}:table/${DYNAMODB_TABLE}"
    }
  ]
}
EOF

aws iam put-role-policy \
    --role-name ${FUNCTION_NAME}-role \
    --policy-name ${FUNCTION_NAME}-policy \
    --policy-document file:///tmp/permissions-policy.json

echo "Waiting for IAM role to propagate..."
sleep 10

# ========== 3. 打包并部署 Lambda ==========
echo "Deploying Lambda function..."

cd /home/ec2-user/glm-lambda
zip -j function.zip lambda_function.py

if aws lambda get-function --function-name $FUNCTION_NAME --region $REGION 2>/dev/null; then
    echo "Updating existing function..."
    aws lambda update-function-code \
        --function-name $FUNCTION_NAME \
        --zip-file fileb://function.zip \
        --region $REGION

    sleep 5
    aws lambda update-function-configuration \
        --function-name $FUNCTION_NAME \
        --environment "Variables={ZHIPU_API_KEY=${ZHIPU_API_KEY},DYNAMODB_TABLE=${DYNAMODB_TABLE},GLM_API_URL=https://api.z.ai/api/paas/v4/chat/completions}" \
        --timeout 60 \
        --region $REGION
else
    echo "Creating new function..."
    aws lambda create-function \
        --function-name $FUNCTION_NAME \
        --runtime python3.11 \
        --handler lambda_function.lambda_handler \
        --zip-file fileb://function.zip \
        --role arn:aws:iam::${ACCOUNT_ID}:role/${FUNCTION_NAME}-role \
        --timeout 60 \
        --memory-size 256 \
        --environment "Variables={ZHIPU_API_KEY=${ZHIPU_API_KEY},DYNAMODB_TABLE=${DYNAMODB_TABLE},GLM_API_URL=https://api.z.ai/api/paas/v4/chat/completions}" \
        --region $REGION
fi

# ========== 4. 创建 Function URL ==========
echo "Creating Function URL..."
sleep 5

aws lambda add-permission \
    --function-name $FUNCTION_NAME \
    --statement-id FunctionURLAllowPublicAccess \
    --action lambda:InvokeFunctionUrl \
    --principal "*" \
    --function-url-auth-type NONE \
    --region $REGION \
    2>/dev/null || echo "Permission already exists"

FUNCTION_URL=$(aws lambda create-function-url-config \
    --function-name $FUNCTION_NAME \
    --auth-type NONE \
    --region $REGION \
    --query 'FunctionUrl' \
    --output text 2>/dev/null || \
    aws lambda get-function-url-config \
    --function-name $FUNCTION_NAME \
    --region $REGION \
    --query 'FunctionUrl' \
    --output text)

# ========== 清理 ==========
rm -f /tmp/trust-policy.json /tmp/permissions-policy.json function.zip

# ========== 完成 ==========
echo ""
echo "=========================================="
echo "部署完成!"
echo "=========================================="
echo "Function URL: $FUNCTION_URL"
echo ""
echo "测试命令:"
echo "curl -X POST $FUNCTION_URL \\"
echo "  -H 'Content-Type: application/json' \\"
echo "  -d '{\"message\": \"你好\", \"session_id\": \"test123\"}'"
