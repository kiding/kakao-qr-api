#!/bin/bash
set -Eeuo pipefail
PROJECT_NAME=kakao-qr-api

echo '[-] 의존성 설치 중...'
command -v brew > /dev/null || /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
command -v npm > /dev/null || brew install npm
command -v aws > /dev/null || brew install awscli

echo '[-] aws-cli 설정 중...'
aws configure get aws_access_key_id > /dev/null || aws configure
aws configure get aws_secret_access_key > /dev/null || aws configure
export AWS_PAGER=
export AWS_DEFAULT_OUTPUT=text
export AWS_REGION=ap-northeast-2

echo '[-] 기존 AWS 리소스 정리 중...'

# -- API Gateway

API_ID=$(
  aws apigateway get-rest-apis \
    --query "items[?name==\`$PROJECT_NAME\`].id"
)
if [[ -n "$API_ID" ]]; then
  aws apigateway delete-rest-api \
    --rest-api-id "$API_ID" \
    > /dev/null
fi

USAGE_PLAN_ID=$(
  aws apigateway get-usage-plans \
    --query "items[?name==\`$PROJECT_NAME\`].id"
)
if [[ -n "$USAGE_PLAN_ID" ]]; then
  aws apigateway delete-usage-plan \
    --usage-plan-id "$USAGE_PLAN_ID" \
    > /dev/null
fi

KEY_ID=$(
  aws apigateway get-api-keys \
    --query "items[?name==\`$PROJECT_NAME\`].id"
)
if [[ -n "$KEY_ID" ]]; then
  aws apigateway delete-api-key \
    --api-key "$KEY_ID" \
    > /dev/null
fi

# -- Lambda

FUNCTION_NAME=$(
  aws lambda list-functions \
    --query "Functions[?FunctionName==\`$PROJECT_NAME\`].FunctionName"
)
if [[ -n "$FUNCTION_NAME" ]]; then
  aws lambda delete-function \
    --function-name "$FUNCTION_NAME" \
    > /dev/null
fi

# -- IAM

ROLE_NAME=$(
  aws iam list-roles \
    --query "Roles[?RoleName==\`$PROJECT_NAME\`].RoleName"
)
if [[ -n "$ROLE_NAME" ]]; then
  POLICY_NAME=$(
    aws iam list-role-policies \
      --role-name "$PROJECT_NAME" \
      --query "PolicyNames[?@==\`$PROJECT_NAME\`]"
  )
  if [[ -n "$POLICY_NAME" ]]; then
    aws iam delete-role-policy \
      --role-name "$ROLE_NAME" \
      --policy-name "$POLICY_NAME" \
    > /dev/null
  fi

  aws iam delete-role \
    --role-name "$ROLE_NAME" \
    > /dev/null
fi

echo '[-] 소스 코드 준비 중...'
npm install --prod --silent > /dev/null
rm -f deploy.zip
zip -r deploy.zip ./* > /dev/null

echo '[-] 카카오 계정 정보 입력 중...'
read -r -p '카카오계정(이메일 또는 전화번호): ' KAKAO_USERNAME
KAKAO_USERNAME=$(sed "s/'/\\\'/g" <<< "${KAKAO_USERNAME:?}")
read -s -r -p '비밀번호: ' KAKAO_PASSWORD
KAKAO_PASSWORD=$(sed "s/'/\\\'/g" <<< "${KAKAO_PASSWORD:?}")

echo ''
echo '[-] AWS 리소스 생성 중...'

# -- IAM

ROLE_ARN=$(
  aws iam create-role \
    --role-name "$PROJECT_NAME" \
    --assume-role-policy-document \
'{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "lambda.amazonaws.com" },
      "Action": "sts:AssumeRole"
    },
    {
      "Effect": "Allow",
      "Principal": { "Service": "apigateway.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}' \
    --query 'Role.Arn'
)

AWS_ID=$(aws sts get-caller-identity --query Account --output text)

aws iam put-role-policy \
  --role-name "$PROJECT_NAME" \
  --policy-name "$PROJECT_NAME" \
  --policy-document \
'{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "LogGroup",
      "Effect": "Allow",
      "Action": "logs:CreateLogGroup",
      "Resource": "arn:aws:logs:'"$AWS_REGION"':'"$AWS_ID"':log-group:*"
    },
    {
      "Sid": "LogStream",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:'"$AWS_REGION"':'"$AWS_ID"':log-group:/aws/lambda/'"$PROJECT_NAME"':*"
    },
    {
      "Sid": "LambdaFunction",
      "Effect": "Allow",
      "Action": [
        "lambda:InvokeFunction",
        "lambda:UpdateFunctionConfiguration",
        "lambda:GetFunctionConfiguration"
      ],
      "Resource": "arn:aws:lambda:'"$AWS_REGION"':'"$AWS_ID"':function:'"$PROJECT_NAME"'"
    }
  ]
}' \
  > /dev/null

# -- Lambda

LAMBDA_ARN=$(
  aws lambda create-function \
    --function-name "$PROJECT_NAME" \
    --runtime 'nodejs12.x' \
    --role "$ROLE_ARN" \
    --handler 'index.handler' \
    --timeout 60 \
    --memory-size 768 \
    --environment "Variables={KAKAO_USERNAME='$KAKAO_USERNAME',KAKAO_PASSWORD='$KAKAO_PASSWORD'}" \
    --zip-file 'fileb://deploy.zip' \
    --query 'FunctionArn'
)

# -- API Gateway

API_ID=$(
  aws apigateway create-rest-api \
    --name "$PROJECT_NAME" \
    --api-key-source 'HEADER' \
    --endpoint-configuration 'types=REGIONAL' \
    --query 'id'
)

RESOURCE_ID=$(
  aws apigateway get-resources \
    --rest-api-id "$API_ID" \
    --query "items[0].id"
)

aws apigateway put-method \
  --rest-api-id "$API_ID" \
  --resource-id "$RESOURCE_ID" \
  --http-method 'GET' \
  --authorization-type 'NONE' \
  --api-key-required \
  > /dev/null

aws apigateway put-integration \
  --rest-api-id "$API_ID" \
  --resource-id "$RESOURCE_ID" \
  --http-method 'GET' \
  --type 'AWS_PROXY' \
  --integration-http-method 'POST' \
  --uri 'arn:aws:apigateway:'"$AWS_REGION"':lambda:path/2015-03-31/functions/'"$LAMBDA_ARN"'/invocations' \
  --credential "$ROLE_ARN" \
  > /dev/null

aws apigateway create-deployment \
  --rest-api-id "$API_ID" \
  --stage-name 'default' \
  > /dev/null

USAGE_PLAN_ID=$(
  aws apigateway create-usage-plan \
    --name "$PROJECT_NAME" \
    --api-stages "apiId=$API_ID,stage=default" \
    --query 'id'
)

read -r KEY_ID KEY_VALUE <<< "$(
  aws apigateway create-api-key \
    --name "$PROJECT_NAME" \
    --enabled \
    --query '[id, value]'
)"

aws apigateway create-usage-plan-key \
  --usage-plan-id "$USAGE_PLAN_ID" \
  --key-id "$KEY_ID" \
  --key-type 'API_KEY' \
  > /dev/null

API_URL="https://$API_ID.execute-api.$AWS_REGION.amazonaws.com/default"

for ((i=0; i<10; i++)) {
  echo '[-] 배포 완료 대기 중...'
  sleep 60

  echo '[-] 테스트 중...'
  TEST_RESULT=$(curl "$API_URL" -H "X-API-KEY: $KEY_VALUE" -w '%{response_code}' -o /dev/null -#)

  if [[ "$TEST_RESULT" == '200' ]]; then
    echo '[+] 배포 완료!'
    echo "[+] $API_URL"
    echo "[+] X-API-KEY: $KEY_VALUE"
    exit 0
  fi
}

echo '[-] 배포 실패.'
exit 1
