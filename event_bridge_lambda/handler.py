from models import StockQuote, Winner
from utils import get_todays_date
from repository import get_latest_stock_date, save_winner
from client import fetch_stock_quotes
from datetime import timedelta

STOCKS = ["AAPL", "MSFT", "GOOGL", "AMZN", "TSLA", "NVDA"]
DEFAULT_LOOKBACK_DAYS = 30

# Entry point triggered by EventBridge cron; determines missing dates, fetches quotes,
# computes a winner per day via calculate_winner, and persists each to DynamoDB via save_winner.
def lambda_handler(event, context):

    latest_stock_date = get_latest_stock_date()
    today = get_todays_date()

    from_date = (latest_stock_date + timedelta(days=1)) if latest_stock_date else (today - timedelta(days=DEFAULT_LOOKBACK_DAYS))

    stock_quotes_map = fetch_stock_quotes(STOCKS, from_date, today)

    winners_written = 0
    for date_iso, daily_quotes in stock_quotes_map.items():

        winner = calculate_winner(daily_quotes)

        if winner is None:
            continue

        save_winner(winner)
        winners_written += 1

    return {"status": "done", "winners_written": winners_written}

# Called by lambda_handler for each trading day; compares absolute percentage moves
# across all quotes and returns the stock with the largest move as a Winner.
def calculate_winner(daily_quotes: dict[str, StockQuote]) -> Winner | None:
    
    if not daily_quotes:
       return None

    best: StockQuote | None = None
    best_pct = float("-inf")

    for _, quote in daily_quotes.items():
        pct_signed = (quote.close - quote.open) / quote.open * 100
        pct_abs = abs(pct_signed)

        if pct_abs > best_pct:
            best_pct = pct_abs
            best = quote
            best_pct_signed = pct_signed


    return Winner(
        stock=best.stock,
        date=best.date,
        close_price=best.close,
        pct_change=round(best_pct_signed, 4),
    )