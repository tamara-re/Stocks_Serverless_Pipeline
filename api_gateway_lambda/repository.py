import os
import boto3
from boto3.dynamodb.conditions import Key
from utils import get_date_14_days_ago

TABLE_NAME = os.environ["DYNAMODB_TABLE"]
PARTITION_KEY = "STOCK_WINNER"

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(TABLE_NAME)

# Called by lambda_handler in the API Gateway Lambda; queries DynamoDB for the n most recent
# winner records within a 14-day window and returns them as a list of dicts for JSON serialization.
def get_last_n_winners(n: int = 7) -> list[dict]:
    from_date = get_date_14_days_ago()
    response = table.query(
        KeyConditionExpression=Key("PK").eq(PARTITION_KEY) & Key("SK").gte(from_date),
        ScanIndexForward=False,
        Limit=n,
    )
    return [
        {
            "date": item["SK"],
            "ticker_symbol": item["ticker_symbol"],
            "close_price": float(item["close_price"]),
            "pct_change": float(item["pct_change"]),
        }
        for item in response["Items"]
    ]