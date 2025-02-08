import os
import boto3
from datetime import datetime

# Constants for database and table names
database_name = "crypto_timestream_db"
price_table_name = "crypto_prices"
sma_table_name = "sma_indicators"

short_window = 3
long_window = 6

def calculate_sma(coin, window):
    timestream_client = boto3.client("timestream-query")

    query = f"""
    SELECT
        NOW() AS time,
        coin_name,
        AVG(measure_value::double) OVER (
            PARTITION BY coin_name
            ORDER BY time
            ROWS BETWEEN {window} PRECEDING AND CURRENT ROW
        ) AS sma_{window}
    FROM "{database_name}"."{price_table_name}"
    WHERE coin_name = '{coin}'
        AND time BETWEEN ago({window * 10}m) AND now()
    LIMIT 1
    """

    try:
        response = timestream_client.query(QueryString=query)
        return response["Rows"]
    except Exception as e:
        print(f"Error calculating SMA for {coin}: {str(e)}")
        return []

def write_to_timestream(records, table_name_target):
    client = boto3.client('timestream-write')
    
    try:
        result = client.write_records(
            DatabaseName=database_name,
            TableName=table_name_target,
            Records=records,
            CommonAttributes={}
        )
        print(f"Successfully wrote {len(records)} records to {table_name_target}")
        return result
    except client.exceptions.RejectedRecordsException as e:
        print("Rejected Records:", e.response['RejectedRecords'])
    except Exception as e:
        print("Write Error:", str(e))

def lambda_handler(event, context):
    coins = ["bitcoin"]
    timestream_records = []
    timestamp = str(int(datetime.utcnow().timestamp() * 1e3))
    
    for coin in coins:
        # Short SMA (10 periods)
        short_sma_data = calculate_sma(coin, short_window)
        for row in short_sma_data:
            sma_value = row['Data'][2]['ScalarValue']
            timestream_records.append({
                'Dimensions': [{'Name': 'coin_name', 'Value': coin, 'DimensionValueType': 'VARCHAR'}],
                'MeasureName': 'sma_10',
                'MeasureValue': str(sma_value),
                'MeasureValueType': 'DOUBLE',
                "Time": timestamp,
                "TimeUnit": "MILLISECONDS",
                "Version": int(datetime.utcnow().timestamp())
            })

        # Long SMA (30 periods)
        long_sma_data = calculate_sma(coin, long_window)
        for row in long_sma_data:
            sma_value = row['Data'][2]['ScalarValue']
            timestream_records.append({
                'Dimensions': [{'Name': 'coin_name', 'Value': coin, 'DimensionValueType': 'VARCHAR'}],
                'MeasureName': 'sma_30',
                'MeasureValue': str(sma_value),
                'MeasureValueType': 'DOUBLE',
                "Time": timestamp,
                "TimeUnit": "MILLISECONDS",
                "Version": int(datetime.utcnow().timestamp())
            })
    
    write_to_timestream(timestream_records, sma_table_name)
    
    return {
        'statusCode': 200,
        'body': f"Processed {len(timestream_records)} SMA records"
    }
