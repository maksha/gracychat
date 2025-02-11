#!/bin/bash
# deploy.sh: Packaging and deployment script for GracyChat.
#  Run this script from the project root directory to use the default value.

set -e

# ---------- Usage  ----------
usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  -l <lambda_function_file>   Path to Lambda function file (default: lambda/lambda_function.py)
  -r <requirements_file>      Path to requirements.txt file (default: lambda/requirements.txt)
  -t <template_file>          Path to CloudFormation template file (default: cloudformation/gracychat.yaml)
  -b <s3_bucket_name>         S3 bucket name (default: gracychat-bucket-{AWS_ACCOUNT_ID}-{AWS_REGION})
  -k <openweathermap_api_key> OpenWeatherMap API key (default: value from OPENWEATHER_API_KEY env variable)
  -h                          Show this help message

Example:
  $0 -l lambda/lambda_function.py -r lambda/requirements.txt -t cloudformation/gracychat.yaml -k YOUR_API_KEY

EOF
  exit 1
}

# Load available environment variables from .env file
if [ -f .env ]; then
  set -a
  source .env
  set +a
fi

# Function to get zip package info
get_zip_info() {
  local zip_file=$1
  local info
  info=$(unzip -l "$zip_file" | tail -n 1)
  local num_files total_size
  num_files=$(echo "$info" | awk '{print $2}')
  total_size=$(echo "$info" | awk '{print $1}')
  echo "$num_files file(s), $total_size byte(s)"
}

# ANSI escape codes for pretty output
GREEN='\033[0;32m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'
CHECKMARK="${GREEN}${BOLD}\u2713${NC}"
X_MARK="${RED}${BOLD}\u2717${NC}"

# ---------- Parse Command Line Arguments ----------
while getopts "l:r:t:b:k:h" opt; do
  case "$opt" in
  l) LAMBDA_FUNCTION_FILENAME="$OPTARG" ;;
  r) REQUIREMENTS_FILENAME="$OPTARG" ;;
  t) CLOUDFORMATION_TEMPLATE_FILE="$OPTARG" ;;
  b) BUCKET_NAME="$OPTARG" ;;
  k) OPENWEATHER_API_KEY="$OPTARG" ;;
  h) usage ;;
  *) usage ;;
  esac
done

# ---------- Interactive Prompts for Missing Parameters ----------
echo -e "\n${BOLD}GracyChat Deployment Script${NC}"
echo -e "Run this script from the project root directory to deploy GracyChat."
echo -e "Press 'Enter' to use the default value in brackets. Press 'Ctrl+C' to exit.\n"

DEFAULT_LAMBDA_FILE="lambda/lambda_function.py"
DEFAULT_REQUIREMENTS_FILE="lambda/requirements.txt"
DEFAULT_TEMPLATE_FILE="cloudformation/gracychat.yaml"
DEFAULT_OPENWEATHER_API_KEY="${OPENWEATHER_API_KEY:-}"

# Lambda function file
if [ -z "$LAMBDA_FUNCTION_FILENAME" ]; then
  read -p "Enter path to the Lambda function file (default: ${DEFAULT_LAMBDA_FILE}): " input
  LAMBDA_FUNCTION_FILENAME="${input:-$DEFAULT_LAMBDA_FILE}"
fi
if [ ! -f "$LAMBDA_FUNCTION_FILENAME" ]; then
  echo -e "${X_MARK} Error: Lambda function file '$LAMBDA_FUNCTION_FILENAME' not found!"
  exit 1
fi

# Requirements file
if [ -z "$REQUIREMENTS_FILENAME" ]; then
  read -p "Enter path to the requirements file (default: ${DEFAULT_REQUIREMENTS_FILE}): " input
  REQUIREMENTS_FILENAME="${input:-$DEFAULT_REQUIREMENTS_FILE}"
fi
if [ ! -f "$REQUIREMENTS_FILENAME" ]; then
  echo -e "${X_MARK} Error: Requirements file '$REQUIREMENTS_FILENAME' not found!"
  exit 1
fi

# CloudFormation template file
if [ -z "$CLOUDFORMATION_TEMPLATE_FILE" ]; then
  read -p "Enter CloudFormation template file (default: ${DEFAULT_TEMPLATE_FILE}): " input
  CLOUDFORMATION_TEMPLATE_FILE="${input:-$DEFAULT_TEMPLATE_FILE}"
fi
if [ ! -f "$CLOUDFORMATION_TEMPLATE_FILE" ]; then
  echo -e "${X_MARK} Error: CloudFormation template file '$CLOUDFORMATION_TEMPLATE_FILE' not found!"
  exit 1
fi

# OpenWeatherMap API key
if [ -z "$OPENWEATHER_API_KEY" ]; then
  read -p "Enter your OpenWeatherMap API key (default from env): " input
  OPENWEATHER_API_KEY="${input:-$DEFAULT_OPENWEATHER_API_KEY}"
fi
if [ -z "$OPENWEATHER_API_KEY" ]; then
  echo -e "${X_MARK} Error: OpenWeatherMap API key is required!"
  exit 1
fi

# S3 bucket name
if [ -z "$BUCKET_NAME" ]; then
  AWS_REGION=$(aws configure get region)
  AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
  DEFAULT_BUCKET_NAME="gracychat-bucket-${AWS_ACCOUNT_ID}-${AWS_REGION}"
  read -p "Enter S3 bucket name for assets (default: ${DEFAULT_BUCKET_NAME}): " input
  BUCKET_NAME="${input:-$DEFAULT_BUCKET_NAME}"
fi

# ---------- Packaging Process ----------
echo -e "\n${BOLD}Packaging Lambda function and dependencies...${NC}"
TEMP_DIR="TEMP_DIR"
mkdir -p "$TEMP_DIR/python"

# Copy the Lambda function file for packaging
cp "$LAMBDA_FUNCTION_FILENAME" "$TEMP_DIR/"

# Install Python dependencies for packaging
pip install -r "$REQUIREMENTS_FILENAME" -t "$TEMP_DIR/python"

# Generate a timestamp for versioning
TIMESTAMP=$(date +%Y%m%d%H%M%S)

# Define versioned S3 keys for the packages
LAMBDA_FUNCTION_S3KEY="lambda_package-v${TIMESTAMP}.zip"
LAMBDA_LAYER_S3KEY="python_layer-v${TIMESTAMP}.zip"

# Create ZIP packages
(
  cd "$TEMP_DIR" || exit 1
  zip -r9 "../$LAMBDA_FUNCTION_S3KEY" "$(basename "$LAMBDA_FUNCTION_FILENAME")"
  zip -r9 "../$LAMBDA_LAYER_S3KEY" python/
)
# Clean up temporary directory
rm -rf "$TEMP_DIR"

echo -e "\nPackaging complete. Generated packages:"
echo -e " ${CHECKMARK} $(pwd)/$LAMBDA_FUNCTION_S3KEY ($(get_zip_info "$(pwd)/$LAMBDA_FUNCTION_S3KEY"))"
echo -e " ${CHECKMARK} $(pwd)/$LAMBDA_LAYER_S3KEY ($(get_zip_info "$(pwd)/$LAMBDA_LAYER_S3KEY"))"

# ---------- S3 Upload and CloudFormation Deployment ----------
echo -e "\n${BOLD}Deployment Parameters:${NC}"
echo -e " CloudFormation Template: \t$CLOUDFORMATION_TEMPLATE_FILE"
echo -e " S3 Bucket Name: \t\t$BUCKET_NAME"
echo -e " OpenWeather API Key: \t\t*******$(echo "$OPENWEATHER_API_KEY" | rev | cut -c-3 | rev)"
echo -e " Lambda Function S3 Key: \t$LAMBDA_FUNCTION_S3KEY"
echo -e " Lambda Layer S3 Key: \t\t$LAMBDA_LAYER_S3KEY"
echo -e " Stack Name: \t\t\tgracychat-stack"
echo -e "\nPress 'q' to quit, or any other key to continue with deployment."
read -n 1 -s key
if [[ "$key" == "q" || "$key" == "Q" ]]; then
  echo -e "\nDeployment cancelled."
  exit 0
fi
echo -e "\nContinuing with deployment..."

# Delete any existing Lambda package ZIP files in the bucket
LAMBDA_FUNCTION_BASENAME=$(basename "$LAMBDA_FUNCTION_S3KEY" | cut -d'-' -f1)
LAMBDA_LAYER_BASENAME=$(basename "$LAMBDA_LAYER_S3KEY" | cut -d'-' -f1)

echo -e "\nDeleting existing Lambda packages in S3 bucket '${BUCKET_NAME}'..."
aws s3 rm s3://${BUCKET_NAME}/ --recursive --exclude "*" --include "${LAMBDA_FUNCTION_BASENAME}*" --include "${LAMBDA_LAYER_BASENAME}*"

echo -e "${CHECKMARK} Existing Lambda packages deleted (if any)."

# Upload new packages to S3
echo -e "\nUploading packages to S3 bucket '${BUCKET_NAME}'..."
aws s3 cp "$LAMBDA_FUNCTION_S3KEY" "s3://${BUCKET_NAME}/${LAMBDA_FUNCTION_S3KEY}"
aws s3 cp "$LAMBDA_LAYER_S3KEY" "s3://${BUCKET_NAME}/${LAMBDA_LAYER_S3KEY}"
echo -e "${CHECKMARK} Packages uploaded successfully."

# Clean-up the generated ZIP files
echo -e "\nCleaning up generated ZIP files..."
rm -f "$LAMBDA_FUNCTION_S3KEY" "$LAMBDA_LAYER_S3KEY"
echo -e "${CHECKMARK} Clean-up complete."

# Deploy the CloudFormation stack
echo -e "\nDeploying CloudFormation stack..."
aws cloudformation deploy \
  --template-file "$CLOUDFORMATION_TEMPLATE_FILE" \
  --stack-name gracychat-stack \
  --capabilities CAPABILITY_IAM \
  --parameter-overrides \
  OpenWeatherApiKey="$OPENWEATHER_API_KEY" \
  DynamoTableName="GracyChatLogs" \
  AssetsBucketName="$BUCKET_NAME" \
  LambdaFunctionS3Key="$LAMBDA_FUNCTION_S3KEY" \
  LambdaLayerS3Key="$LAMBDA_LAYER_S3KEY"

echo -e "${CHECKMARK} CloudFormation stack deployed successfully."

# Verify deployment and output API endpoint
echo -e "\nVerifying deployment..."
API_ENDPOINT=$(aws cloudformation describe-stacks --stack-name gracychat-stack \
  --query 'Stacks[0].Outputs[?OutputKey==`ApiEndpoint`].OutputValue' \
  --output text)
STACK_STATUS=$(aws cloudformation describe-stacks --stack-name gracychat-stack \
  --query 'Stacks[0].StackStatus' \
  --output text)

# If STACK_STATUS is not CREATE_COMPLETE OR UPDATE_COMPLETE, then exit with error
if [ "$STACK_STATUS" != "CREATE_COMPLETE" ] && [ "$STACK_STATUS" != "UPDATE_COMPLETE" ]; then
  echo -e "${X_MARK} Error: CloudFormation stack creation failed. Please check the stack events."
  exit 1
else
  echo -e "${CHECKMARK} Deployment Verified!"
  echo -e "Stack Status: ${BOLD}$STACK_STATUS${NC}"
fi

echo -e "\n${GREEN}${BOLD}Deployment complete!${NC}\n"

# Add or Update API_ENDPOINT variable in .env for future use
if [ -f .env ]; then
  sed -i "s#API_ENDPOINT=.*#API_ENDPOINT=$API_ENDPOINT#" .env
else
  echo "API_ENDPOINT=$API_ENDPOINT" >>.env
fi

echo -e "\n------------------------------------------------------------------------------------------------------------------------"
echo -e "${GREEN}${BOLD}## Test the API ##${NC}"
echo -e "\nAPI Endpoint added/updated in .env:"
echo -e "  ${BOLD}API_ENDPOINT${NC}="
echo -e "\nReload .env:" 
echo -e "  $ ${BOLD}source .env${NC}" 
echo -e "\nVerify that the API is working by sending a POST request to the endpoint:"
echo -e "  $ curl -X POST -H 'Content-Type: application/json' -d '{\"query\": \"What is the weather in London?\"}' \"\$API_ENDPOINT\""
echo -e "  $ curl -X POST -H 'Content-Type: application/json' -d '{\"query\": \"Tell me a joke\"}' \"\$API_ENDPOINT\""
echo -e "------------------------------------------------------------------------------------------------------------------------\n"