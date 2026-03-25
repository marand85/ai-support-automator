import json
import boto3
import uuid
from datetime import datetime, timezone

kinesis = boto3.client('kinesis')


def lambda_handler(event, context):
    """
    Ingestion endpoint: validates ticket and sends to Kinesis.
    Triggered by API Gateway POST /tickets.
    """

    # Parse request body
    try:
        if isinstance(event.get('body'), str):
            body = json.loads(event['body'])
        else:
            body = event.get('body', {}) or {}
    except json.JSONDecodeError:
        return response(400, {'error': 'Invalid JSON'})

    # Validate required fields
    required_fields = ['subject', 'body', 'customer']
    missing = [f for f in required_fields if not body.get(f)]
    if missing:
        return response(400, {
            'error': f'Missing required fields: {", ".join(missing)}'
        })

    # Build ticket
    ticket_id = str(uuid.uuid4())[:8]
    ticket = {
        'ticket_id': ticket_id,
        'subject': body['subject'],
        'body': body['body'],
        'customer': body['customer'],
        'channel': body.get('channel', 'web'),
        'submitted_at': datetime.now(timezone.utc).isoformat(),
        'status': 'submitted'
    }

    # Store initial ticket in DynamoDB (for stuck detection)
    try:
        import os
        table_name = os.environ.get('DYNAMODB_TABLE')
        if table_name:
            ddb = boto3.resource('dynamodb')
            table = ddb.Table(table_name)
            table.put_item(Item={
                'ticket_id': ticket_id,
                'subject': ticket['subject'],
                'body': ticket['body'],
                'customer': ticket['customer'],
                'channel': ticket.get('channel', 'web'),
                'submitted_at': ticket['submitted_at'],
                'status': 'submitted',
                'urgency': 'pending',
                'category': 'pending',
                'sla_breached': False
            })
    except Exception as e:
        print(f"Warning: could not store initial ticket: {str(e)}")

    print(f"Ingesting ticket {ticket_id}: {ticket['subject']}")

    # Send to Kinesis
    try:
        kinesis.put_record(
            StreamName=event_stream_name(),
            Data=json.dumps(ticket),
            PartitionKey=ticket['customer']
        )
    except Exception as e:
        print(f"Error sending to Kinesis: {str(e)}")
        return response(500, {'error': 'Failed to submit ticket'})

    print(f"Ticket {ticket_id} sent to Kinesis")

    return response(202, {
        'message': 'Ticket submitted successfully',
        'ticket_id': ticket_id,
        'status': 'submitted'
    })


def event_stream_name():
    import os
    return os.environ['KINESIS_STREAM_NAME']


def response(status_code, body):
    return {
        'statusCode': status_code,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        'body': json.dumps(body)
    }