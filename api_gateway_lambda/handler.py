import json
import os
import time
from repository import get_last_n_winners

MAX_RETRIES = 3
RETRY_DELAY_SECONDS = 1
ALLOWED_ORIGIN = os.environ["ALLOWED_ORIGIN"]

# Entry point for API Gateway GET /movers; retrieves the last 7 winners from DynamoDB
# via get_last_n_winners and returns them as a JSON response with CORS headers.
# Retries up to MAX_RETRIES times with a 1-second delay between attempts.
def lambda_handler(event, context):
    last_error = None
    for attempt in range(MAX_RETRIES + 1):
        try:
            winners = get_last_n_winners(7)
            return {
                "statusCode": 200,
                "headers": {
                    "Content-Type": "application/json",
                    "Access-Control-Allow-Origin": ALLOWED_ORIGIN,
                },
                "body": json.dumps(winners),
            }
        except Exception as e:
            last_error = e
            if attempt < MAX_RETRIES:
                time.sleep(RETRY_DELAY_SECONDS)
    raise last_error