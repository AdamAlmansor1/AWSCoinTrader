import os
import boto3
import requests
from datetime import datetime

coin_gecko_key = os.getenv("coin_gecko_key")
region = os.getenv("region")

# Initialise the Timestream client
timestream_client = boto3.client("timestream-write", region_name=region)

# Constants for database and table names
database_name = "crypto_timestream_db"
table_name = "crypto_prices"

def lambda_handler(event, context):
    api_url = f"https://api.coingecko.com/api/v3/simple/price?x_cg_demo_api_key={coin_gecko_key}"
    params = {"ids": "bitcoin,ethereum", "vs_currencies": "aud"}

    try:
        # Fetch cryptocurrency prices
        response = requests.get(api_url, params=params)
        response.raise_for_status()
        coins_prices = response.json()

        timestamp = str(int(datetime.utcnow().timestamp() * 1e3))

        records = [
            {
                "Dimensions": [
                    {"Name": "coin_name", "Value": coin}
                ],
                "MeasureName": "price",
                "MeasureValue": str(info["aud"]),
                "MeasureValueType": "DOUBLE",
                "Time": timestamp,
                "TimeUnit": "MILLISECONDS"
            }
            for coin, info in coins_prices.items()
        ]

        # Write records to Timestream
        response = timestream_client.write_records(
            DatabaseName=database_name,
            TableName=table_name,
            Records=records
        )

        print(f"Timestream write response: {response}")
        return {"statusCode": 200, "body": "Data written to Timestream"}
    
    except requests.exceptions.RequestException as e:
        print(f"Error fetching prices: {e}")
        return {"statusCode": 400, "body": f"Error fetching prices: {e}"}

    except Exception as e:
        print(f"Error: {e}")
        return {"statusCode": 500, "body": "Error"}
