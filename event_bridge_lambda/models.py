from dataclasses import dataclass

# Holds open/close data for one stock on one trading day; populated by fetch_stock_quotes and consumed by calculate_winner.
@dataclass
class StockQuote:
    stock: str
    date: str
    open: float
    close: float

# Represents the largest absolute percentage mover for a single trading day; returned by calculate_winner and written to DynamoDB by save_winner.
@dataclass
class Winner:
    stock: str
    date: str
    close_price: float
    pct_change: float
