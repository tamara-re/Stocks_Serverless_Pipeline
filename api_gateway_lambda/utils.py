from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

EASTERN = ZoneInfo("America/New_York")

# Called by get_last_n_winners to compute the start of the 14-day query window, bounding the DynamoDB scan.
def get_date_14_days_ago() -> str:
    return (datetime.now(EASTERN).date() - timedelta(days=14)).isoformat()