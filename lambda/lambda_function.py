"""
Lambda function to fetch weather data using the OpenWeather API or random jokes using the Official Joke API.
- OpenWeather API: https://openweathermap.org/api
- Official Joke API: https://official-joke-api.appspot.com/random_joke 
- Caches results to reduce API calls.
- Logs queries and responses to a DynamoDB table.
- Returns errors in the response body when they occur.
"""

import json
import boto3
import requests
import os
import re
import logging
from datetime import datetime, timedelta, timezone
from typing import Dict, Any, Union, TypedDict, Tuple

# Define TypedDicts for structured responses.


class WeatherData(TypedDict):
    city_name: str
    description: str
    temperature_celsius: float


class JokeData(TypedDict):
    setup: str
    punchline: str


ResponseData = Dict[str, Union[WeatherData, JokeData, str]]

# Initialize
DYNAMODB = boto3.resource("dynamodb")
TABLE_NAME = os.environ["DYNAMODB_TABLE_NAME"]
WEATHER_API_KEY = os.environ["OPENWEATHER_API_KEY"]
LOGS_TABLE = DYNAMODB.Table(TABLE_NAME)

# External API URLs.
WEATHER_API_URL = "https://api.openweathermap.org/data/2.5/weather"
JOKE_API_URL = "https://official-joke-api.appspot.com/random_joke"

# Set up in-memory caches.
weather_cache: Dict[str, Any] = {}
WEATHER_CACHE_EXPIRY_SECONDS = 60

joke_cache: Dict[str, Any] = {}
JOKE_CACHE_EXPIRY_SECONDS = 60

# Configure logging to use CloudWatch Logs.
# Ref: https://docs.aws.amazon.com/lambda/latest/dg/python-logging.html
logger = logging.getLogger("lambdaLogger")
logger.setLevel(logging.INFO)


def get_weather(city: str) -> Dict[str, Union[str, float]]:
    """
    Fetches weather data for a given city from the OpenWeather API and caches the result.
    """
    now = datetime.now(timezone.utc)
    if city in weather_cache and weather_cache[city]["expiry"] > now:
        logger.info(f"Cache hit for weather in {city}")
        return weather_cache[city]["data"]

    params = {"q": city, "appid": WEATHER_API_KEY, "units": "metric"}
    try:
        response = requests.get(WEATHER_API_URL, params=params)
        response.raise_for_status()
        data = response.json()
        weather_data: WeatherData = {
            "city_name": data["name"],
            "description": data["weather"][0]["description"],
            "temperature_celsius": data["main"]["temp"],
        }
        weather_cache[city] = {
            "data": weather_data,
            "expiry": now + timedelta(seconds=WEATHER_CACHE_EXPIRY_SECONDS),
        }
        logger.info(f"Weather data fetched and cached for {city}")
        return weather_data
    except requests.exceptions.RequestException as e:
        logger.error(f"Weather API error: {e}")
        return {"error": "Failed to fetch weather data due to an API error."}


def get_joke() -> Dict[str, str]:
    """
    Fetches a random joke from the Official Joke API and caches the result.
    """
    now = datetime.now(timezone.utc)
    if "joke" in joke_cache and joke_cache["joke"]["expiry"] > now:
        logger.info("Cache hit for joke")
        return joke_cache["joke"]["data"]

    try:
        response = requests.get(JOKE_API_URL)
        response.raise_for_status()
        data = response.json()
        joke_data: JokeData = {
            "setup": data["setup"], "punchline": data["punchline"]}
        joke_cache["joke"] = {
            "data": joke_data,
            "expiry": now + timedelta(seconds=JOKE_CACHE_EXPIRY_SECONDS),
        }
        logger.info("Joke data fetched and cached")
        return joke_data
    except requests.exceptions.RequestException as e:
        logger.error(f"Joke API error: {e}")
        return {"error": "Failed to fetch joke due to an API error."}


def extract_query(event: Dict[str, Any]) -> Tuple[str, str]:
    """
    Extracts the query from the incoming event.
    """
    query = ""
    user_query = ""
    try:
        if "body" in event and event["body"]:
            request_body = json.loads(event["body"])
            query = request_body.get("query", "")
        elif "queryStringParameters" in event and event["queryStringParameters"]:
            query = event["queryStringParameters"].get("query", "")
        elif isinstance(event, dict):
            query = event.get("query", "")
            user_query = query
    except (json.JSONDecodeError, TypeError) as e:
        logger.error(f"Error extracting query: {e}")
        return "", ""
    return query, user_query


# regex patterns to match weather and joke queries
weather_pattern = re.compile(
    r"(weather|forecast|temperature)\s+(?:in|for|about|of)?\s*(.+)")
joke_pattern = re.compile(r"(joke|funny|humor)")


def process_query(query: str) -> Dict[str, Union[Dict[str, Union[str, float]], str]]:
    """
    Processes the query to fetch weather data or a joke based on the query content.
    """
    final_response: Dict[str, Union[Dict[str, Union[str, float]], str]] = {}
    query_lower = query.lower()

    weather_match = weather_pattern.search(query_lower)
    if weather_match:
        city = weather_match.group(2).strip().rstrip("?")
        weather_data = get_weather(city)
        if "error" not in weather_data:
            final_response["weather"] = weather_data
        else:
            final_response["weather_error"] = weather_data["error"]

    joke_match = joke_pattern.search(query_lower)
    if joke_match:
        joke_data = get_joke()
        if "error" not in joke_data:
            final_response["joke"] = joke_data
        else:
            final_response["joke_error"] = joke_data["error"]

    if not final_response:
        final_response["general_response"] = "I can only process weather and joke requests."

    return final_response


def log_query(user_query: str, final_response: Dict[str, Union[Dict[str, Union[str, float]], str]]) -> None:
    """
    Logs the query and its response to the DynamoDB table.
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


# ---------------------- Lambda Handler ---------------------- #
def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    AWS Lambda handler that processes the incoming event and returns a response.
    Reference: https://docs.aws.amazon.com/lambda/latest/dg/python-handler.html
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

    final_response = process_query(query)
    log_query(user_query, final_response)

    # Return the final response
    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(final_response),
    }
