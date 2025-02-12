"""
Lambda function to fetch data using external APIs.
"""

import json
import logging
from typing import Dict, Any
from datetime import datetime, timezone

from functions.config import LOGS_TABLE
from functions.api.weather import get_weather
from functions.api.joke import get_joke
from functions.utils.query import extract_query, process_query

logger = logging.getLogger("lambdaLogger")
logger.setLevel(logging.INFO)


def log_query(user_query: str, final_response: Dict[str, Any]) -> None:
    """
    Logs the query and its response to the DynamoDB table.
    Ref: https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/GettingStarted.Python.03.html
    """
    timestamp = datetime.now(timezone.utc).isoformat()
    log_data = {
        "Timestamp": timestamp,
        "Query": user_query,
        "Response": json.dumps(final_response),
    }
    try:
        LOGS_TABLE.put_item(Item=log_data)
        logger.info("Query logged to DynamoDB")
    except Exception as e:
        logger.error(f"DynamoDB Logging error: {e}")


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    AWS Lambda handler to process incoming event and returns a response.
    Ref: https://docs.aws.amazon.com/lambda/latest/dg/python-handler.html
    """
    query, user_query = extract_query(event)
    if not query:
        error_msg = "Missing query"
        logger.error(error_msg)
        return {
            "statusCode": 400,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"error": error_msg}),
        }

    final_response = process_query(query, get_weather, get_joke)
    log_query(user_query, final_response)

    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(final_response),
    }
