import json
import os
import boto3

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(os.environ["TABLE_NAME"])


def lambda_handler(event, context):
    """Read or atomically increment the shared page-request counter."""
    action = event.get("action")
    counter_id = event.get("counter_id", "homepage")
    if action == "get":
        response = table.get_item(Key={"counter_id": counter_id}, ConsistentRead=True)
        visits = int(response.get("Item", {}).get("visits", 0))
        return {
            "statusCode": 200,
            "body": json.dumps({"counter_id": counter_id, "visits": visits}),
        }

    if action != "increment":
        return {
            "statusCode": 400,
            "body": json.dumps({"error": "Unsupported action"}),
        }

    response = table.update_item(
        Key={"counter_id": counter_id},
        UpdateExpression="ADD visits :increment",
        ExpressionAttributeValues={":increment": 1},
        ReturnValues="UPDATED_NEW",
    )
    return {
        "statusCode": 200,
        "body": json.dumps({
            "counter_id": counter_id,
            "visits": int(response["Attributes"]["visits"]),
        }),
    }
