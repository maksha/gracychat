"""
joke.py: functions to fetch jokes from the Official Joke API.
"""
from datetime import datetime, timedelta, timezone
import requests
import logging
from typing import Dict, Any
from functions.config import JOKE_API_URL, JOKE_CACHE_EXPIRY_SECONDS

logger = logging.getLogger("lambdaLogger")

# In-memory cache for jokes.
joke_cache: Dict[str, Any] = {}


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
        joke_data = {"setup": data["setup"], "punchline": data["punchline"]}
        joke_cache["joke"] = {
            "data": joke_data,
            "expiry": now + timedelta(seconds=JOKE_CACHE_EXPIRY_SECONDS),
        }
        logger.info("Joke data fetched and cached")
        return joke_data
    except requests.exceptions.RequestException as e:
        logger.error(f"Joke API error: {e}")
        return {"error": "Failed to fetch joke due to an API error."}
