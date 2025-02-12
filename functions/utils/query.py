"""
query.py: Utility functions to extract and process queries from incoming events.
"""
import json
import re
import logging
from typing import Dict, Any, Tuple

logger = logging.getLogger("lambdaLogger")

# Regex patterns to match weather and joke queries.
weather_pattern = re.compile(
    r"(weather|forecast|temperature)\s+(?:in|for|about|of)?\s*(.+)", re.IGNORECASE
)
joke_pattern = re.compile(r"(joke|funny|humor)", re.IGNORECASE)


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
            user_query = query
        elif "queryStringParameters" in event and event["queryStringParameters"]:
            query = event["queryStringParameters"].get("query", "")
            user_query = query
        elif isinstance(event, dict):
            query = event.get("query", "")
            user_query = query
    except (json.JSONDecodeError, TypeError) as e:
        logger.error(f"Error extracting query: {e}")
        return "", ""
    return query, user_query


def process_query(query: str, get_weather_func, get_joke_func) -> Dict[str, Any]:
    """
    Processes the query to fetch external data based on the query content.
    """
    final_response: Dict[str, Any] = {}
    query_lower = query.lower()

    # Weather data
    weather_match = weather_pattern.search(query_lower)
    if weather_match:
        city = weather_match.group(2).strip().rstrip("?")
        weather_data = get_weather_func(city)
        if "error" not in weather_data:
            final_response["weather"] = weather_data
        else:
            final_response["weather_error"] = weather_data["error"]

    # Joke data
    joke_match = joke_pattern.search(query_lower)
    if joke_match:
        joke_data = get_joke_func()
        if "error" not in joke_data:
            final_response["joke"] = joke_data
        else:
            final_response["joke_error"] = joke_data["error"]

    if not final_response:
        final_response["general_response"] = "I can only process weather and joke requests."

    return final_response
