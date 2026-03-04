from datetime import date, datetime
from zoneinfo import ZoneInfo

EASTERN = ZoneInfo("America/New_York")

# Called by lambda_handler to establish today's date in Eastern Time as the upper bound for quote fetching.
def get_todays_date() -> date:
    return datetime.now(EASTERN).date()


# Called by fetch_stock_quotes to convert each bar's millisecond timestamp into an ISO date string used as the map key.
def millis_to_date_iso(millis: int) -> str:
    return datetime.fromtimestamp(millis / 1000, tz=EASTERN).date().isoformat()
