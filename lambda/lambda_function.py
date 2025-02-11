import json
import boto3
import requests
import os
import re
from datetime import datetime, timedelta, timezone
from typing import Dict, Any, Union, TypedDict, Tuple


class WeatherData(TypedDict):
    city_name: str
    description: str
    temperature_celsius: float


class JokeData(TypedDict):
    setup: str
    punchline: str


ResponseData = Dict[str, Union[WeatherData, JokeData, str]]

dynamodb = boto3.resource("dynamodb")
table_name = os.environ["DYNAMODB_TABLE_NAME"]
weather_api_key = os.environ["OPENWEATHER_API_KEY"]
logs_table = dynamodb.Table(table_name)

# Cache for weather data
WEATHER_CACHE = {}
WEATHER_CACHE_EXPIRY_SECONDS = 300

# Cache for joke data
JOKE_CACHE = {}
JOKE_CACHE_EXPIRY_SECONDS = 600


def get_weather(city: str) -> Dict[str, Union[str, float]]:
    now = datetime.now(timezone.utc)
    if city in WEATHER_CACHE and WEATHER_CACHE[city]["expiry"] > now:
        print(f"Cache hit for weather in {city}")
        return WEATHER_CACHE[city]["data"]

    base_url = "https://api.openweathermap.org/data/2.5/weather"
    params = {"q": city, "appid": weather_api_key, "units": "metric"}
    try:
        response = requests.get(base_url, params=params)
        response.raise_for_status()
        data = response.json()
        weather_data = {
            "city_name": data["name"],
            "description": data["weather"][0]["description"],
            "temperature_celsius": data["main"]["temp"],
        }
        WEATHER_CACHE[city] = {
            "data": weather_data,
            "expiry": now + timedelta(seconds=WEATHER_CACHE_EXPIRY_SECONDS),
        }
        print(f"Weather data fetched and cached for {city}")
        return weather_data
    except requests.exceptions.RequestException as e:
        print(f"Weather API error: {e}")
        return {"error": "Failed to fetch weather data due to an API error."}


def get_joke() -> Dict[str, str]:
    now = datetime.now(datetime.timezone.utc)
    if "joke" in JOKE_CACHE and JOKE_CACHE["joke"]["expiry"] > now:
        print("Cache hit for joke")
        return JOKE_CACHE["joke"]["data"]

    url = "https://official-joke-api.appspot.com/random_joke"
    try:
        response = requests.get(url)
        response.raise_for_status()
        data = response.json()
        joke_data = {"setup": data["setup"], "punchline": data["punchline"]}
        JOKE_CACHE["joke"] = {
            "data": joke_data,
            "expiry": now + timedelta(seconds=JOKE_CACHE_EXPIRY_SECONDS),
        }
        print("Joke data fetched and cached")
        return joke_data
    except requests.exceptions.RequestException as e:
        print(f"Joke API error: {e}")
        return {"error": "Failed to fetch joke due to an API error."}


def lambda_handler(event: Dict[str, Any]) -> Dict[str, Any]:
    query, user_query = extract_query(event)
    if not query:
        return {
            "statusCode": 400,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"error": "Missing query"}),
        }

    final_response = process_query(query)
    log_query(user_query, final_response)

    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(final_response),
    }


def extract_query(event: Dict[str, Any]) -> Tuple[str, str]:
    query = ""
    user_query = ""
    try:
        if "body" in event and event["body"]:
            request_body = json.loads(event["body"])
            query = request_body.get("query", "")
        elif "queryStringParameters" in event and event["queryStringParameters"]:
            query = event["queryStringParameters"].get("query", "")
        elif isinstance(event, dict):  # Handle direct invocation with query parameter
            query = event.get("query", "")
        user_query = query
        query_lower = query.lower()
    except (json.JSONDecodeError, TypeError):
        return "", ""

    return query, user_query


weather_pattern = re.compile(
    r"(weather|forecast|temperature)\s+(?:in|for|about|of)?\s*(.+)")
joke_pattern = re.compile(r"(joke|funny|humor)")


def process_query(query: str) -> Dict[str, Union[Dict[str, Union[str, float]], str]]:
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
        final_response["general_response"] = (
            "I can only process weather and joke requests."
        )

    return final_response

    return final_response


def log_query(user_query: str, final_response: Dict[str, Union[Dict[str, Union[str, float]], str]]) -> None:
    timestamp = datetime.now(timezone.utc).isoformat()
    log_data = {
        "Timestamp": timestamp,
        "Query": user_query,
        "Response": json.dumps(final_response),
    }

    try:
        logs_table.put_item(Item=log_data)
    except Exception as e:
        print(f"DynamoDB Logging error: {e}")
