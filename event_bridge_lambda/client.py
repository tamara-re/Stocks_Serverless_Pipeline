import os
import time
import requests
from datetime import date
from dotenv import load_dotenv

from utils import millis_to_date_iso
from models import StockQuote

load_dotenv() 

MASSIVE_API_KEY = os.environ["MASSIVE_API_KEY"]
MASSIVE_BASE_URL = "https://api.massive.com/v2"  



# Called by lambda_handler in handler.py; iterates over each ticker, requests daily OHLC bars
# from the Massive API with rate-limit throttling, and returns a nested map of date → ticker → StockQuote.
def fetch_stock_quotes(stocks: list[str], start_date: date, today: date) -> dict[str, dict[str, StockQuote]]:
    
    quotes_map: dict[str, dict[str, StockQuote]] = {}

    for i, stock in enumerate(stocks):
        if i > 0 and i % 5 == 0:
            time.sleep(60)

        url = f"{MASSIVE_BASE_URL}/aggs/ticker/{stock}/range/1/day/{start_date}/{today}"

        for attempt in range(3):
            response = requests.get(
                url,
                params={"apiKey": MASSIVE_API_KEY, "adjusted": "true"},
                timeout=10,
            )
            if response.status_code == 429:
                wait = int(response.headers.get("Retry-After", 60))
                time.sleep(wait)
                continue
            break

        if response.status_code == 429:
            raise RuntimeError(f"Rate limit exceeded for {stock} after 3 attempts")
        if 400 <= response.status_code < 500:
            raise ValueError(f"Massive API client error: {response.status_code} - {response.text}")
        if 500 <= response.status_code < 600:
            raise RuntimeError(f"Massive API server error: {response.status_code} - {response.text}")

        for bar in response.json().get("results", []):
            date_iso = millis_to_date_iso(bar["t"])
            quotes_map.setdefault(date_iso, {})[stock] = StockQuote(
                stock=stock,
                date=date_iso,
                open=float(bar["o"]),
                close=float(bar["c"]),
            )
    
    return quotes_map