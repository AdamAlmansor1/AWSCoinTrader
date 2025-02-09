import os
import boto3
import json

s3 = boto3.client('s3')
trade_bucket = os.getenv("trade_states_bucket")

def lambda_handler(event, context):
    try:
        # Fetch balance
        balance_response = s3.get_object(Bucket=trade_bucket, Key="balance.json")
        balance_data = json.loads(balance_response['Body'].read().decode('utf-8'))
        
        # Fetch Bitcoin trade state
        trade_response = s3.get_object(Bucket=trade_bucket, Key="bitcoin_state.json")
        trade_state = json.loads(trade_response['Body'].read().decode('utf-8'))

        return {
            "statusCode": 200,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"balance": balance_data, "trade_state": trade_state})
        }
    except Exception as e:
        print(f"Error retrieving data: {e}")
        return {
            "statusCode": 500,
            "body": json.dumps({"error": str(e)})
        }
