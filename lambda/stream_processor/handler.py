import json
import boto3
import base64
import os

sqs = boto3.client('sqs')


def lambda_handler(event, context):
    """
    Stream processor: reads from Kinesis, forwards to SQS.
    Triggered automatically by Kinesis event source mapping.
    """

    queue_url = os.environ['SQS_QUEUE_URL']
    records = event.get('Records', [])

    print(f"Received {len(records)} records from Kinesis")

    success_count = 0
    error_count = 0

    for record in records:
        try:
            # Kinesis records are base64 encoded
            payload = base64.b64decode(record['kinesis']['data']).decode('utf-8')
            ticket = json.loads(payload)

            print(f"Processing ticket {ticket.get('ticket_id', 'unknown')}: {ticket.get('subject', 'no subject')}")

            # Forward to SQS for Step Functions processing
            sqs.send_message(
                QueueUrl=queue_url,
                MessageBody=json.dumps(ticket),
                MessageAttributes={
                    'ticket_id': {
                        'DataType': 'String',
                        'StringValue': ticket.get('ticket_id', 'unknown')
                    },
                    'customer': {
                        'DataType': 'String',
                        'StringValue': ticket.get('customer', 'unknown')
                    }
                }
            )

            success_count += 1

        except Exception as e:
            print(f"Error processing record: {str(e)}")
            error_count += 1

    print(f"Processed: {success_count} success, {error_count} errors")

    return {
        'statusCode': 200,
        'processed': success_count,
        'errors': error_count
    }