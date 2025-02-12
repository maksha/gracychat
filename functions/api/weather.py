"""
weather.py: functions to fetch weather data from the OpenWeather API.
"""
from datetime import datetime, timedelta, timezone
import requests
import logging
from typing import Dict, Any, Union
from functions.config import WEATHER_API_KEY, WEATHER_API_URL, WEATHER_CACHE_EXPIRY_SECONDS

logger = logging.getLogger("lambdaLogger")

# Cache for weather data.
weather_cache: Dict[str, Any] = {}


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
        weather_data = {
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
        return {"error": "Failed to fetch weather data due to an API error"}
