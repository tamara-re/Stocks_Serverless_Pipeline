from dataclasses import dataclass

# Represents a single winner record returned by the API; shape mirrors the DynamoDB item returned by get_last_n_winners.
@dataclass
class WinnerResponse:
    date: str
    ticker_symbol: str
    close_price: float
    pct_change: float