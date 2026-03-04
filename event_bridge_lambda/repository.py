import os
import boto3
from boto3.dynamodb.conditions import Key
from datetime import date, datetime, timedelta
from decimal import Decimal
from zoneinfo import ZoneInfo
from models import Winner

EASTERN = ZoneInfo("America/New_York")

TABLE_NAME = os.environ["DYNAMODB_TABLE"]
PARTITION_KEY = "STOCK_WINNER"


dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(TABLE_NAME)


# Helper called by save_winner to compute the Unix timestamp 31 days after the record date,
# used as the DynamoDB TTL so records auto-expire after one month.
def _ttl(date: datetime) -> int:
    return int((date + timedelta(days=31)).timestamp())


# Called by lambda_handler after calculate_winner; writes the Winner record to DynamoDB
# using a conditional put to prevent overwriting an existing entry for the same date.
def save_winner(winner: Winner):

    dt = datetime.strptime(winner.date, "%Y-%m-%d").replace(tzinfo=EASTERN)
    try:
        table.put_item(
            Item={
                "PK":          PARTITION_KEY,
                "SK":          winner.date,
                "ticker_symbol":       winner.stock,
                "date":        winner.date,
                "close_price": Decimal(str(winner.close_price)),
                "pct_change":  Decimal(str(winner.pct_change)),
                "expiresAt":   _ttl(dt),
            },
            ConditionExpression="attribute_not_exists(PK) AND attribute_not_exists(SK)",
        )
    except dynamodb.meta.client.exceptions.ConditionalCheckFailedException:
        print(f"  [{winner.stock}] {winner.date} already exists — skipping.")


# Called at the start of lambda_handler to find the most recent stored date,
# so the handler only fetches quotes for days not yet in DynamoDB.
def get_latest_stock_date() -> date | None:
    response = table.query(
        KeyConditionExpression=Key("PK").eq(PARTITION_KEY),
        ScanIndexForward=False,
        Limit=1,
    )

    if response["Count"] == 0:
        return None
    return date.fromisoformat(response["Items"][0]["SK"])