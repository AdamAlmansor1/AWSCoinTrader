def calculate_sma(data, window):
    # Example calculation for Simple Moving Average
    return sum(data[-window:]) / window
