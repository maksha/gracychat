#!/bin/bash

SCRIPT_NAME=$(basename "$0")

usage() {
    echo -e "\n$SCRIPT_NAME: Upload CloudFormation Stack.\n"
    echo -e " Usage: \n       $SCRIPT_NAME [options]\n"
    echo -e " Options:"
    echo -e "   -t <cloudformation_template_file>  CloudFormation template file (required)"
    echo -e "   -b <bucket_name>                   S3 bucket name (required if not the same as the hardcoded format)"
    echo -e "   -k <openweathermap_api_key>        OpenWeatherMap API key (required if not in .env as OPENWEATHER_API_KEY)"
    echo -e "   -f <lambda_function_s3key>         Lambda function package S3 key"
    echo -e "   -l <lambda_layer_s3key>            Lambda layer package S3 key"
    echo -e "   -h                                 Show this help message\n"
    echo -e " Environment Variables:"
    echo -e "   OPENWEATHER_API_KEY                OpenWeatherMap API key (can be set in .env file)"
    echo -e "   LAMBDA_FUNCTION_S3KEY              Lambda function package S3 key (can be set in .env file)"
    echo -e "   LAMBDA_LAYER_S3KEY                 Lambda layer package S3 key (can be set in .env file)\n"
    echo -e " Note:"
    echo -e "   - OPENWEATHER_API_KEY is required either as a parameter or in .env file."
    echo -e "   - LAMBDA_FUNCTION_S3KEY and LAMBDA_LAYER_S3KEY will be read from parameters if not found in .env."
    echo -e "\n Examples:"
    echo -e "   # Deploy using template file, bucket name, and API key as parameters:"
    echo -e "     $SCRIPT_NAME -t cloudformation/gracychat.yaml -b gracychat-bucket-112233445566-us-east-1 -k YOUR_API_KEY"
    echo -e "\n   # Deploy using template file only, bucket name, API key, and Lambda package keys from .env:"
    echo -e "     $SCRIPT_NAME -t cloudformation/gracychat.yaml"
    echo -e "\n   # Deploy using template file and bucket name, API key from .env, and providing Lambda package keys:"
    echo -e "     $SCRIPT_NAME -t cloudformation/gracychat.yaml -b gracychat-bucket-112233445566-us-east-1 -f lambda_package.zip -l python_layer.zip"
    echo -e "\n   # Show help message:"
    echo -e "     $SCRIPT_NAME -h"
    exit 1
}

# Load .env file if it exists
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
fi


# Parse command line arguments
while getopts "t:b:k:f:l:h" opt; do
  case "$opt" in
    t) CLOUDFORMATION_TEMPLATE_FILE="$OPTARG" ;;
    b) BUCKET_NAME="$OPTARG" ;;
    k) OPENWEATHER_API_KEY="$OPTARG" ;;
    f) LAMBDA_FUNCTION_S3KEY="$OPTARG" ;;
    l) LAMBDA_LAYER_S3KEY="$OPTARG" ;;
    h) usage ;;
    \?) usage ;;
  esac
done

# ANSI escape codes
GREEN='\033[0;32m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'
CHECKMARK="${GREEN}${BOLD}\u2713${NC}"
X_MARK="${RED}${BOLD}\u2717${NC}"

# Validate required parameters
if [ -z "$CLOUDFORMATION_TEMPLATE_FILE" ]; then
    echo -e " ${X_MARK} ${RED}${BOLD}Error:${NC} CloudFormation template file is required! Use -t <cloudformation_template_file>"
    exit 1
fi

if [ ! -f "$CLOUDFORMATION_TEMPLATE_FILE" ]; then
    echo -e " ${X_MARK} ${RED}${BOLD}Error:${NC} CloudFormation template file '$CLOUDFORMATION_TEMPLATE_FILE' not found!"
    exit 1
fi

# Get S3 Bucket Name from .env or parameter
if [ -z "$BUCKET_NAME" ]; then
    if [ -z "$BUCKET_NAME" ]; then
        BUCKET_NAME="${BUCKET_NAME}" # Fallback to env variable if parameter not provided
    fi
    if [ -z "$BUCKET_NAME" ]; then
       AWS_REGION=$(aws configure get region)
       AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
       BUCKET_NAME="gracychat-bucket-${AWS_ACCOUNT_ID}-${AWS_REGION}"
    fi
    if [ -z "$BUCKET_NAME" ]; then
        echo -e " ${X_MARK} ${RED}${BOLD}Error:${NC} S3 bucket name is required! Use -b <bucket_name> or set BUCKET_NAME in .env"
        exit 1
    fi
fi

# Get OpenWeather API Key from .env or parameter
if [ -z "$OPENWEATHER_API_KEY" ]; then
    if [ -z "$OPENWEATHER_API_KEY" ]; then
        OPENWEATHER_API_KEY="${OPENWEATHER_API_KEY_FILE}" # Fallback to env variable if parameter not provided
    fi
    if [ -z "$OPENWEATHER_API_KEY" ]; then
        echo -e " ${X_MARK} ${RED}${BOLD}Error:${NC} OpenWeatherMap API key is required! Use -k <openweathermap_api_key> or set OPENWEATHER_API_KEY in .env"    
        exit 1
    fi
fi

# Get Lambda function and layer S3 keys from parameters or environment variables
if [ -z "$LAMBDA_FUNCTION_S3KEY" ]; then
    LAMBDA_FUNCTION_S3KEY="${LAMBDA_FUNCTION_S3KEY}" # Read from env if not set via parameter
    if [ -n "$LAMBDA_FUNCTION_S3KEY" ] && [ ! -f "$LAMBDA_FUNCTION_S3KEY" ]; then
        echo -e " ${X_MARK} ${RED}${BOLD}Error:${NC} Lambda package file '$LAMBDA_FUNCTION_S3KEY' not found!"
        exit 1
    fi
fi

if [ -z "$LAMBDA_LAYER_S3KEY" ]; then
    LAMBDA_LAYER_S3KEY="${LAMBDA_LAYER_S3KEY}" # Read from env if not set via parameter
    if [ -n "$LAMBDA_LAYER_S3KEY" ] && [ ! -f "$LAMBDA_LAYER_S3KEY" ]; then
        echo -e " ${X_MARK} ${RED}${BOLD}Error:${NC} Lambda layer package file '$LAMBDA_LAYER_S3KEY' not found!"
        exit 1
    fi
fi

# Display deployment parameters before continuing
echo -e ""
echo -e "----------------------------------------------------------------------------------------------"
echo -e "  ${BOLD}Deployment Parameters:${NC}"
echo -e "  ${BOLD}CloudFormation Template:${NC} \t$CLOUDFORMATION_TEMPLATE_FILE"
echo -e "  ${BOLD}S3 Bucket Name         :${NC} \t$BUCKET_NAME"
echo -e "  ${BOLD}OpenWeather API Key    :${NC} \t*******$(echo "$OPENWEATHER_API_KEY" | rev | cut -c-3 | rev)"
echo -e "  ${BOLD}Lambda Function S3 Key :${NC} \t$LAMBDA_FUNCTION_S3KEY"
echo -e "  ${BOLD}Lambda Layer S3 Key    :${NC} \t$LAMBDA_LAYER_S3KEY"
echo -e "----------------------------------------------------------------------------------------------\n"

echo -en "${BOLD}Press 'q' to quit, or any other key to proceed with deployment. ${NC}\n"
read -n 1 -s key

if [[ "$key" == "q" || "$key" == "Q" ]]; then
    exit 0
else
    echo -e "\n${BOLD}Continuing with deployment...${NC}\n"
fi

# Delete Lambda function and layer ZIP files from S3 bucket
LAMBDA_FUNCTION_BASENAME=$(basename "$LAMBDA_FUNCTION_S3KEY" | sed 's/-.*//')
LAMBDA_LAYER_BASENAME=$(basename "$LAMBDA_LAYER_S3KEY" | sed 's/-.*//')

echo -e "\n- Deleting existing Lambda function and layer ZIP files from S3 bucket: ${BUCKET_NAME}"
aws s3 rm s3://${BUCKET_NAME}/ --recursive --exclude "*" --include "${LAMBDA_FUNCTION_BASENAME}*" --include "${LAMBDA_LAYER_BASENAME}*"
if [ $? -ne 0 ]; then
    echo -e " ${X_MARK} ${RED}${BOLD}Error:${NC} Failed to delete existing Lambda ZIP files from S3 bucket '${BUCKET_NAME}'."
    exit 1
fi
echo -e "${CHECKMARK} - Existing Lambda function and layer ZIP files deleted from S3 bucket '${BUCKET_NAME}'\n"

# Upload both packages to S3 bucket
if [ -n "$LAMBDA_FUNCTION_S3KEY" ]; then
    echo -e "\n- Uploading packages to S3 bucket: ${BUCKET_NAME}"
    aws s3 cp "$LAMBDA_FUNCTION_S3KEY" "s3://${BUCKET_NAME}/${LAMBDA_FUNCTION_S3KEY}"
    if [ $? -ne 0 ]; then
        echo -e " ${X_MARK} ${RED}${BOLD}Error:${NC} Failed to upload '$LAMBDA_FUNCTION_S3KEY' to S3 bucket '${BUCKET_NAME}'."
        exit 1
    fi
    echo -e "${CHECKMARK} - Uploaded '$LAMBDA_FUNCTION_S3KEY' to S3 bucket '${BUCKET_NAME}'\n"
fi

if [ -n "$LAMBDA_LAYER_S3KEY" ]; then
    aws s3 cp "$LAMBDA_LAYER_S3KEY" "s3://${BUCKET_NAME}/${LAMBDA_LAYER_S3KEY}"
    if [ $? -ne 0 ]; then
        echo -e " ${X_MARK} ${RED}${BOLD}Error:${NC} Failed to upload '$LAMBDA_LAYER_S3KEY' to S3 bucket '${BUCKET_NAME}'."
        exit 1
    fi
    echo -e "${CHECKMARK} - Uploaded '$LAMBDA_LAYER_S3KEY' to S3 bucket '${BUCKET_NAME}'"
fi


# Deploy CloudFormation Stack
echo -e "\n- Deploying CloudFormation stack..."
aws cloudformation deploy \
    --template-file "$CLOUDFORMATION_TEMPLATE_FILE" \
    --stack-name gracychat-stack \
    --capabilities CAPABILITY_IAM \
    --parameter-overrides OpenWeatherApiKey="$OPENWEATHER_API_KEY" \
                            DynamoTableName="GracyChatLogs" \
                            AssetsBucketName="$BUCKET_NAME" \
                            LambdaFunctionS3Key="$LAMBDA_FUNCTION_S3KEY" \
                            LambdaLayerS3Key="$LAMBDA_LAYER_S3KEY"
if [ $? -ne 0 ]; then
    echo -e " ${X_MARK} ${RED}${BOLD}Error:${NC} Failed to deploy CloudFormation stack."
    exit 1
fi
echo -e "${CHECKMARK} - CloudFormation stack deployed successfully"

# Verify the Deployed CloudFormation Stack
echo -e "\n- Verifying the deployment..."
DEPLOYMENT_INFO=$(aws cloudformation describe-stacks --stack-name gracychat-stack \
    --query 'Stacks[0].{StackName: StackName, StackStatus: StackStatus, ApiEndpoint: Outputs[?OutputKey==`ApiEndpoint`].OutputValue}' \
    --output json)

if [ $? -ne 0 ]; then
    echo -e " ${X_MARK} ${RED}${BOLD}Error:${NC} Failed to verify deployment."
    exit 1
fi

# Check Stack Status
STACK_STATUS=$(echo "$DEPLOYMENT_INFO" | jq -r '.StackStatus')

if [[ "$STACK_STATUS" == "CREATE_COMPLETE" || "$STACK_STATUS" == "UPDATE_COMPLETE" ]]; then
    API_ENDPOINT_VALUE=$(echo "$DEPLOYMENT_INFO" | jq -r '.ApiEndpoint')
    export API_ENDPOINT="$API_ENDPOINT_VALUE"

    echo -e "${CHECKMARK} ${GREEN}${BOLD}Deployment Verified!${NC}"
    echo -e "--------------------------------------------------------------------------"
    echo -e "${BOLD}Details:${NC}"
    echo -e "  ${BOLD}Stack Status:${NC} \t\t${STACK_STATUS}"
    echo -e "  ${BOLD}API Endpoint:${NC} \t\t$(echo "$DEPLOYMENT_INFO" | jq -r '.ApiEndpoint')"
    echo -e "--------------------------------------------------------------------------"
else
    echo -e " ${X_MARK} ${RED}${BOLD}Error:${NC} Deployment Verification Failed."
    echo -e "  ${BOLD}Stack Status:${NC} \t\t${STACK_STATUS}"
    echo -e "  Raw Deployment Info for Debugging:"
    echo -e "$DEPLOYMENT_INFO \n"
    exit 1
fi

echo -e "\n${GREEN}${BOLD} Deployment complete!${NC}\n"