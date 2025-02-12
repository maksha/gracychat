import os
import boto3

DYNAMODB = boto3.resource("dynamodb")
TABLE_NAME = os.environ["DYNAMODB_TABLE_NAME"]
LOGS_TABLE = DYNAMODB.Table(TABLE_NAME)

WEATHER_API_KEY = os.environ["OPENWEATHER_API_KEY"]

WEATHER_API_URL = "https://api.openweathermap.org/data/2.5/weather"
JOKE_API_URL = "https://official-joke-api.appspot.com/random_joke"

WEATHER_CACHE_EXPIRY_SECONDS = 60
JOKE_CACHE_EXPIRY_SECONDS = 60
