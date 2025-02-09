import os
import boto3
import json
from datetime import datetime

# Constants for database and table names
database_name = "crypto_timestream_db"
price_table_name = "crypto_prices"
sma_table_name = "sma_indicators"
trade_bucket = os.getenv("trade_states_bucket")

s3 = boto3.client('s3')
timestream_query = boto3.client('timestream-query')

def initialise_state(coin):
    """Initialise trade state for a coin if it doesn't exist"""
    try:
        s3.head_object(Bucket=trade_bucket, Key=f"{coin}_state.json")
    except s3.exceptions.ClientError:
        # Create initial state
        s3.put_object(
            Bucket=trade_bucket,
            Key=f"{coin}_state.json",
            Body=json.dumps({"holding": False, "entry_price": 0})
        )

def get_state(coin):
    """Retrieve current trade state from S3"""
    try:
        response = s3.get_object(Bucket=trade_bucket, Key=f"{coin}_state.json")
        return json.loads(response['Body'].read().decode('utf-8'))
    except Exception as e:
        print(f"Error getting state for {coin}: {str(e)}")
        return {"holding": False, "entry_price": 0}

def update_state(coin, state):
    """Update trade state in S3"""
    s3.put_object(
        Bucket=trade_bucket,
        Key=f"{coin}_state.json",
        Body=json.dumps(state)
    )

def get_balance():
    """Get current balance from S3"""
    try:
        response = s3.get_object(Bucket=trade_bucket, Key="balance.json")
        return float(json.loads(response['Body'].read().decode('utf-8'))['balance'])
    except:
        # Initialize balance if not exists
        s3.put_object(
            Bucket=trade_bucket,
            Key="balance.json",
            Body=json.dumps({"balance": 1000.0})
        )
        return 1000.0

def update_balance(new_balance):
    """Update balance in S3"""
    s3.put_object(
        Bucket=trade_bucket,
        Key="balance.json",
        Body=json.dumps({"balance": round(new_balance, 2)})
    )

def query_smas(coin):
    """Retrieve SMAs from Timestream"""
    query = f"""
    SELECT * FROM (
        SELECT time, coin_name, measure_name, measure_value::double AS sma
        FROM "{database_name}"."{sma_table_name}"
        WHERE coin_name = '{coin}'
            AND time BETWEEN ago(40m) AND now()
        ORDER BY time DESC
    )
    LIMIT 4
    """

    try:
        response = timestream_query.query(QueryString=query)
        return response["Rows"]
    except Exception as e:
        print(f"Error querying SMAs for {coin}: {str(e)}")
        return []

def generate_signal(sma_data):
    """Determines trade signal based on crosses"""
    try:
        # Partition rows by measure_name
        short_sma_rows = [row for row in sma_data if row['Data'][2]['ScalarValue'] == 'sma_10']
        long_sma_rows  = [row for row in sma_data if row['Data'][2]['ScalarValue'] == 'sma_30']
        
        # Ensure we have at least two records for each SMA type
        if len(short_sma_rows) < 2 or len(long_sma_rows) < 2:
            print("Not enough SMA data to generate signal")
            return None
        
        prev_short = float(short_sma_rows[0]['Data'][3]['ScalarValue'])
        curr_short = float(short_sma_rows[1]['Data'][3]['ScalarValue'])
        prev_long  = float(long_sma_rows[0]['Data'][3]['ScalarValue'])
        curr_long  = float(long_sma_rows[1]['Data'][3]['ScalarValue'])
        
        print(f"Prev Short: {prev_short}, Curr Short: {curr_short}")
        print(f"Prev Long: {prev_long}, Curr Long: {curr_long}")
        
        if prev_short < prev_long and curr_short > curr_long:
            print('golden_cross')
            return 'golden_cross'
        elif prev_short > prev_long and curr_short < curr_long:
            print('death_cross')
            return 'death_cross'
        else:
            return 'no_signal'
    except Exception as e:
        print(f"Error generating signal: {str(e)}")
        return None

def lambda_handler(event, context):
    coins = ["bitcoin"]
    timestream_records = []
    timestamp = str(int(datetime.utcnow().timestamp() * 1e3))

    for coin in coins:
        # Retrieve the current state for the coin
        initialise_state(coin)
        balance = get_balance()
        state = get_state(coin)
        sma_data = query_smas(coin)
        signal = generate_signal(sma_data)

        # If there's no valid signal, skip this coin
        if not signal:
            print("No valid signal.")
            continue

        try:
            price = float(sma_data[0]['Data'][3]['ScalarValue'])
        except Exception as e:
            print(f"Couldn't get price for {coin}: {e}")
            continue

        # Process a buy signal if not currently holding
        if signal == 'golden_cross' and not state.get('holding', False):
            if balance >= price * 0.0005:
                state['holding'] = True
                state['entry_price'] = price * 0.0005
                balance -= price * 0.0005
                update_state(coin, state)
                print(f"Bought {coin} at {price * 0.0005}")

        # Process a sell signal if currently holding
        elif signal == 'death_cross' and state.get('holding', False):
            pnl = (price * 0.0005) - state['entry_price']
            balance += price * 0.0005
            state['holding'] = False
            state['entry_price'] = 0
            update_state(coin, state)
            print(f"Sold {coin} at {price * 0.0005}. P&L: {pnl:.2f}")

    update_balance(balance)

    return {
        'statusCode': 200,
        'body': f"Final balance: {balance:.2f}"
    }
