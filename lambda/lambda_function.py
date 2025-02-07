import json
import boto3
import requests
import os
import re
from datetime import datetime
from typing import Dict, Any, Union

dynamodb = boto3.resource('dynamodb')
table_name = os.environ['DYNAMODB_TABLE_NAME']
weather_api_key = os.environ['OPENWEATHER_API_KEY']
logs_table = dynamodb.Table(table_name)

def get_weather(city: str) -> Dict[str, Union[str, float]]:
    base_url = "https://api.openweathermap.org/data/2.5/weather"
    params = {
        'q': city,
        'appid': weather_api_key,
        'units': 'metric'
    }
    try:
        response = requests.get(base_url, params=params)
        response.raise_for_status()
        data = response.json()
        return {
            "city_name": data['name'],
            "description": data['weather'][0]['description'],
            "temperature_celsius": data['main']['temp']
        }
    except requests.exceptions.RequestException as e:
        print(f"Weather API error: {e}")
        return {"error": "Failed to fetch weather data due to an API error."}

def get_joke() -> Dict[str, str]:
    url = "https://official-joke-api.appspot.com/random_joke"
    try:
        response = requests.get(url)
        response.raise_for_status()
        data = response.json()
        return {
            "setup": data['setup'],
            "punchline": data['punchline']
        }
    except requests.exceptions.RequestException as e:
        print(f"Joke API error: {e}")
        return {"error": "Failed to fetch joke due to an API error."}

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    query = ''
    user_query = ''
    try:
        if 'body' in event and event['body']:
            request_body = json.loads(event['body'])
            query = request_body.get('query', '')
        elif 'queryStringParameters' in event and event['queryStringParameters']:
            query = event['queryStringParameters'].get('query', '')
        elif isinstance(event, dict):
            query = event.get('query', '')
        user_query = query
        query_lower = query.lower()
    except (json.JSONDecodeError, TypeError):
        return {
            'statusCode': 400,
            'headers': {
                'Content-Type': 'application/json'
            },
            'body': json.dumps({"error": "Invalid request"})
        }
    
    if not query:
        return {
            'statusCode': 400,
            'headers': {
                'Content-Type': 'application/json'
            },
            'body': json.dumps({"error": "Missing query"})
        }
    
    final_response: Dict[str, Union[Dict[str, Union[str, float]], str]] = {}
    weather_match = re.search(r"(weather|forecast|temperature)\s+(?:in|for|about|of)?\s*(.+)", query_lower)
    if weather_match:
        city = weather_match.group(2).strip().rstrip('?')
        weather_data = get_weather(city)
        if "error" not in weather_data:
            final_response['weather'] = weather_data
        else:
            final_response['weather_error'] = weather_data['error']
    
    joke_match = re.search(r"(joke|funny|humor)", query_lower)
    if joke_match:
        joke_data = get_joke()
        if "error" not in joke_data:
            final_response['joke'] = joke_data
        else:
            final_response['joke_error'] = joke_data['error']
    
    if not final_response:
        final_response['general_response'] = "I can only process weather and joke requests."
    
    timestamp = datetime.utcnow().isoformat()
    log_data = {
        'Timestamp': timestamp,
        'Query': user_query,
        'Response': json.dumps(final_response)
    }
    
    try:
        logs_table.put_item(Item=log_data)
    except Exception as e:
        print(f"DynamoDB Logging error: {e}")
    
    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json'
        },
        'body': json.dumps(final_response)
    }