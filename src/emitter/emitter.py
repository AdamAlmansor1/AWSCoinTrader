import os
import boto3
import requests
from datetime import datetime

# Initialise AWS client
sqs = boto3.client('sqs')

# Environment variable containing the SQS queue URL
QUEUE_URL = os.getenv("QUEUE_URL")
COIN_GECKO_KEY = os.getenv("COIN_GECKO_KEY")

def lambda_handler(event, context):
    api_url = f"https://api.coingecko.com/api/v3/simple/price?x_cg_demo_api_key={COIN_GECKO_KEY}"
    params = {"ids": "bitcoin,ethereum", "vs_currencies": "aud"}

    try:
        # Fetch cryptocurrency prices
        response = requests.get(api_url, params=params)
        response.raise_for_status()
        coins_prices = response.json()

        transformed_coins_prices = [{"timestamp": datetime.utcnow().isoformat(), "coin": coin, "price": info["aud"]} for coin, info in coins_prices.items()]

        for item in transformed_coins_prices:
            # Send the message to the SQS queue
            sqs.send_message(
                QueueUrl=QUEUE_URL,
                MessageBody=str(item)
            )
            print(f"Message sent to SQS: {item}")

        return {"statusCode": 200, "body": "Prices sent successfully"}
    
    except Exception as e:
        print(f"Error: {e}")
        return {"statusCode": 500, "body": "Failed to fetch prices"}
