#!/bin/bash

LOG_GROUP_NAME="/aws/lambda/GracyChatFunction"

LOG_STREAM_NAME=$(
  aws logs describe-log-streams --log-group-name $LOG_GROUP_NAME \
    --order-by LastEventTime \
    --descending --limit 1 \
    --query 'logStreams[0].logStreamName' \
    --output text
)
aws logs get-log-events --log-group-name $LOG_GROUP_NAME \
  --log-stream-name $LOG_STREAM_NAME \
  --start-from-head --query 'events[*].message' \
  --output text
