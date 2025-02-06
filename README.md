# **GracyChat - Multi-Domain Chatbot**

Multi-Domain Chatbot to fetch Weather Information and Random Jokes.

1. **Deployment steps** (e.g., aws cloudformation deploy).
2. **Sample requests/responses** for weather and jokes.
3. **High-level architecture notes** (API Gateway → Lambda → DynamoDB).


## **Architecture Overview**

![Architecture Overview](docs/GracyChat-Diagram.png)

*Public Access: [GracyChat Diagram](https://s3.amazonaws.com/gracychat-bucket-342173272267-us-east-1/GracyChat-Diagram.png)*

### **Components and Services**
1. **User:** The individual or application interacting with the chatbot via a POST request to the `/chatbot` endpoint.
2. **API Gateway:** A fully managed service that acts as a single entry point for all API requests. It handles routing, authentication, authorization, and API request throttling.  It receives the POST request from the user.
3. **Lambda Function:** A serverless compute service that executes code in response to events (API Gateway requests in this case).  The diagram shows three Lambda functions:
    * **OpenWeather REST:** Fetches weather data from the OpenWeatherMap API.
    * **Joke REST:** Fetches jokes from a Jokes API.
    * **API Interaction Logs (DynamoDB):** Logs API interactions and queries to a DynamoDB database.

4. **CloudFormation:** A service that allows defining infrastructure as code. It's used to deploy and update the API. The engineer interacts with CloudFormation to manage the infrastructure.
5. **OpenWeatherMap API & Jokes API:** External REST APIs providing weather and joke data, respectively.
6. **DynamoDB:** A NoSQL database used to store API interaction logs and user queries.
7. **S3 Bucket:** Object storage service for storing assets (e.g., static files, images) related to the application.

### **Flow**
1. **Deployment:** An engineer uses CloudFormation to define and deploy the API and its resources (Lambda functions, API Gateway, DynamoDB, S3 Bucket).
2. **User Interaction:** A user sends a POST request to the API Gateway's `/chatbot` endpoint.
3. **API Gateway Routing:** API Gateway receives the request and routes it to the appropriate Lambda function(s).
4. **Lambda Execution:** Lambda functions execute logic:
    * They may call external APIs (OpenWeatherMap, Jokes API) to fetch data.
    * They may interact with DynamoDB to log requests or store data.
    * They may retrieve assets from the S3 bucket.

5. **Response:** Lambda functions return a response to API Gateway.
6. **Response to User:** API Gateway forwards the response back to the user.

----
# **Deployment Guide**

This guide provides steps to build and deploy a basic multi-domain chatbot, GracyChat, that fetches weather data and random jokes from free APIs, deployed using CloudFormation and uses AWS API Gateway, AWS Lambda, AWS DynamoDB, and AWS S3.

> ### **External API**
> - OpenWeather API: http://api.openweathermap.org/data/2.5/weather (from https://openweathermap.org/api)
> - Random Jokes API: https://official-joke-api.appspot.com/random_joke (from https://github.com/15Dkatz/official_joke_api)

### **Setting Up Development Environment**
#### 1. Private Repository:
   - Create a private Git repository on GitHub or GitLab
   - Clone the repository to your local development machine

> **Project Structure**
> ```shell
> gracychat/
> ├── cloudformation/
> │   └── gracychat.yaml       
> ├── lambda/
> │   └── lambda_function.py  
> │   └── requirements.txt 
> ├── docs/
> │   └── GracyChat-Diagram.png
> ├── .gitignore
> ├── .env
> └── README.md
> ```
> ----

#### 2. Local Development Environment Setup

Assuming you are using Linux or macOS, the following is written while using AlmaLinux running on WSL2 on Windows 11.
1. Install Python and `venv`:
```bash
$ sudo yum update
$ sudo yum install python3 python3-venv
```
2. Create and activate virtual environment:
```bash
$ python3 -m venv venv
$ source venv/bin/activate
```

#### 3. AWS Setup and Permissions
##### **Create IAM User for Development using AWS Web Console**

1. Login to AWS Console
2. Navigate to IAM
3. Click "Users" and then "Add users"
4. Enter a username
5. Select "Access key - Programmatic access"
6. Click "Next Permission" then "Attach existing policies directly"
7. Find and select: `AdministrationAccess`
8. Click "Next: Tags", "Next: Review", and "Create User"
9. Downlod `.csv` file containing `accessKeyId` and `secretAccessKey` 


#### 4. AWS-CLI Configuration
1. Install AWS-CLI:
```bash
$ sudo curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
$ sudo unzip awscliv2.zip
$ sudo ./aws/install
```

2. Verify the installation:
```bash
$ aws --version
aws-cli/2.23.11 Python/3.12.6 Linux/5.15.167.4-microsoft-standard-WSL2 exe/x86_64.almalinux.9
```

3. Configure AWS CLI Using Default Profile:
```bash
$ aws configure
```
Enter the `accessKeyId`, `secretAccessKey`, default region (e.g., `us-east-1`), and default output format (e.g., `json`) when prompted. Use the credentials downloaded in the previous step for the IAM user.

#### 5. Create S3 Bucket using AWS-CLI
Getting your AWS Account ID and Region, and using it to create an S3 Bucket. This storage will be used to store static assets and zipped lambda code.

```bash
$ AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text) # get AWS Account ID
$ AWS_REGION=$(aws configure get region)                                      # get AWS region
$ BUCKET_NAME="gracychat-bucket-${AWS_ACCOUNT_ID}-${AWS_REGION}"              # S3 bucket name


$ echo $BUCKET_NAME                                             # Verify the bucket name that we're going to create
gracychat-bucket-112233445566-us-east-1

$ aws s3 mb s3://${BUCKET_NAME} --region ${AWS_REGION}          # Create S3 Bucket:

$ aws s3 ls                                                     # Verify the created S3 Bucket:
2025-02-04 06:43:03 gracychat-bucket-112233445566-us-east-1
```
----

### **Develop Lambda Function**

#### 1. Dependencies (`lambda/requirements.txt`)
Specify the Python dependencies.

*Source code available in the repository*

#### 2. Lambda Function (`lambda/lambda_function.py`)
Implement the chatbot logic.

*Source code available in the repository*

#### 3. CloudFormatino Template for Deployment (`cloudformation/gracychat.yaml`)

The following cloudformation template defines the infrastructure for GracyChat.

*Source code available in the repository*

----

## **Deployment Process** 
### **Package Lambda Function and Dependencies**
1. Go to `lambda/` directory
2. Install Python dependencies into local directory for lambda layer packaging:
    ```bash
    $ mkdir python
    $ pip install -r requirements.txt -t ./python
    $ zip -r9 python_requests_layer.zip python/

    $ unzip -l python_requests_layer.zip          # verify the content of the created lambda layer package
    ```
3. Create a ZIP archive for the lambda function:
    ```bash
    $ zip -r lambda_package.zip lambda_function.py
    ```

4. Upload both packages to S3 bucket:
    ```bash
    # Note: ${BUCKET_NAME} is an environment variable that we created in the previous section.
    $ aws s3 cp lambda_package.zip s3://${BUCKET_NAME}/lambda_package.zip
    $ aws s3 cp python_requests_layer.zip s3://${BUCKET_NAME}/python_requests_layer.zip
    ```

### **Deploy CloudFormation Stack**
1. Navigate to project's root directory and run the following AWS CLI command:
    ```bash
    $ aws cloudformation deploy \
        --template-file cloudformation/gracychat.yaml \
        --stack-name gracychat-stack \
        --capabilities CAPABILITY_IAM \
        --parameter-overrides OpenWeatherApiKey="${OPENWEATHER_API_KEY}" \
                                DynamoTableName="GracyChatLogs" \
                                AssetsBucketName="${BUCKET_NAME}"
    ```

2. Verify the Deployment using AWS CLI:
    ```bash
    $ aws cloudformation describe-stacks --stack-name gracychat-stack \
        --query 'Stacks[0].{StackName: StackName, CreationTime: CreationTime, LastUpdateTime: LastUpdatedTime, StackStatus: StackStatus, ApiEndpoint: Outputs[?OutputKey==`ApiEndpoint`].OutputValue}' \
        --output json
    ```
    > **Description**:
    >
    > *   **`StackName`**:  Displays the name of your CloudFormation stack (e.g., "gracychat-stack").
    > *   **`CreationTime`**: Shows the timestamp when the stack was initially created (e.g., "2024-03-01T10:00:00.000Z").
    > *   **`LastUpdateTime`**: Shows the timestamp of the last successful update to the stack. If the stack has only been created and not updated since, this time will be the same as `CreationTime`.
    > *   **`StackStatus`**: Displays the current status of the CloudFormation stack (e.g., "UPDATE_COMPLETE", "CREATE_COMPLETE", "UPDATE_ROLLBACK_COMPLETE"). This is for verifying successful deployments or identifying failures.
    > *   **`ApiEndpoint`**: Shows the API Gateway endpoint URL for the chatbot.

## **Test the Chatbot API**
Test the API using `curl`:

```bash
# Get the API_ENDPOINT URL using AWS CLI and store it an environment variable
$ API_ENDPOINT=$(aws cloudformation describe-stacks --stack-name gracychat-stack --query "Stacks[0].Outputs[?OutputKey=='ApiEndpoint'].OutputValue" --output text)

# Test the API using curl

# Weather
$ curl -X POST "${API_ENDPOINT}" -H "Content-Type: application/json" -d '{"query": "What'\''s the weather in London?"}'
{"weather": {"city_name": "London", "description": "clear sky", "temperature_celsius": 4.45}}

# Jokes
$ curl -X POST "${API_ENDPOINT}" -H "Content-Type: application/json" -d '{"query": "Tell me a joke."}'
{"joke": {"setup": "What do ghosts call their true love?", "punchline": "Their ghoul-friend"}}

```
