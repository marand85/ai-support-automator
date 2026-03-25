import json
import boto3
import os
from datetime import datetime, timezone, timedelta

dynamodb = boto3.resource('dynamodb')
sns = boto3.client('sns')


def store_result(event, context):
    """
    Step Functions task: saves processed ticket to DynamoDB.
    Calculates SLA deadline based on urgency.
    """

    ticket = event['ticket']
    classification = event['classification']
    ai_response = event.get('ai_response', 'No response generated')
    ticket_id = ticket['ticket_id']

    print(f"Storing result for ticket {ticket_id}")

    table = dynamodb.Table(os.environ['DYNAMODB_TABLE'])

    # Calculate SLA deadline
    sla_minutes = get_sla_minutes(classification['urgency'])
    submitted_at = datetime.fromisoformat(ticket['submitted_at'])
    sla_deadline = (submitted_at + timedelta(minutes=sla_minutes)).isoformat()

    now = datetime.now(timezone.utc).isoformat()

    item = {
        'ticket_id': ticket_id,
        'subject': ticket['subject'],
        'body': ticket['body'],
        'customer': ticket['customer'],
        'channel': ticket.get('channel', 'web'),
        'submitted_at': ticket['submitted_at'],
        'processed_at': now,
        'status': 'processed',
        'urgency': classification['urgency'],
        'category': classification['category'],
        'classification_reasoning': classification.get('reasoning', ''),
        'ai_response': ai_response,
        'sla_deadline': sla_deadline,
        'sla_breached': False
    }

    table.update_item(
        Key={'ticket_id': ticket_id},
        UpdateExpression='SET #s = :status, processed_at = :processed, urgency = :urgency, category = :category, classification_reasoning = :reasoning, ai_response = :response, sla_deadline = :deadline, sla_breached = :breached',
        ExpressionAttributeNames={
            '#s': 'status' # status is a reserved keyword in DynamoDB hence an alias
        },
        ExpressionAttributeValues={
            ':status': 'processed',
            ':processed': now,
            ':urgency': classification['urgency'],
            ':category': classification['category'],
            ':reasoning': classification.get('reasoning', ''),
            ':response': ai_response,
            ':deadline': sla_deadline,
            ':breached': False
        }
    )

    print(f"Ticket {ticket_id} stored: {classification['urgency']} / {classification['category']}")

    return {
        'ticket': ticket,
        'classification': classification,
        'ai_response': ai_response,
        'stored': True
    }


def send_critical_alert(event, context):
    """
    Step Functions task: sends immediate SNS alert for critical tickets.
    Runs in parallel with response generation.
    """

    ticket = event['ticket']
    ticket_id = ticket['ticket_id']

    print(f"Sending critical alert for ticket {ticket_id}")

    topic_arn = os.environ['SNS_CRITICAL_TOPIC_ARN']

    message_lines = [
        "CRITICAL TICKET ALERT",
        "",
        f"Ticket ID: {ticket_id}",
        f"Customer: {ticket['customer']}",
        f"Channel: {ticket.get('channel', 'web')}",
        f"Subject: {ticket['subject']}",
        "",
        "Description:",
        ticket['body'],
        "",
        "This ticket requires IMMEDIATE attention.",
        "SLA: respond within 5 minutes."
    ]

    sns.publish(
        TopicArn=topic_arn,
        Subject=f"CRITICAL: {ticket['subject'][:80]}",
        Message="\n".join(message_lines)
    )

    print(f"Critical alert sent for {ticket_id}")

    return {
        'alert_sent': True,
        'ticket_id': ticket_id
    }


def notify_customer(event, context):
    """
    Step Functions task: sends confirmation notification to customer.
    """

    ticket = event['ticket']
    classification = event['classification']
    ai_response = event.get('ai_response', '')
    ticket_id = ticket['ticket_id']

    print(f"Notifying customer for ticket {ticket_id}")

    topic_arn = os.environ['SNS_TOPIC_ARN']

    message_lines = [
        f"Support Ticket Confirmation - #{ticket_id}",
        "",
        f"Dear {ticket['customer']},",
        "",
        f"We have received your support ticket regarding:",
        f"\"{ticket['subject']}\"",
        "",
        f"Priority: {classification['urgency'].upper()}",
        f"Category: {classification['category']}",
        "",
        "Our AI assistant has prepared an initial response:",
        "",
        ai_response,
        "",
        f"Ticket ID: {ticket_id}",
        "Our team will follow up shortly."
    ]

    sns.publish(
        TopicArn=topic_arn,
        Subject=f"Ticket #{ticket_id} received: {ticket['subject'][:60]}",
        Message="\n".join(message_lines)
    )

    print(f"Customer notified for {ticket_id}")

    return {
        'notified': True,
        'ticket_id': ticket_id
    }


def handle_error(event, context):
    """
    Step Functions error handler: stores failed ticket in DynamoDB.
    """

    ticket = event.get('ticket', {})
    error = event.get('error', {})
    ticket_id = ticket.get('ticket_id', 'unknown')

    print(f"Handling error for ticket {ticket_id}: {json.dumps(error)}")

    table = dynamodb.Table(os.environ['DYNAMODB_TABLE'])

    now = datetime.now(timezone.utc).isoformat()

    item = {
        'ticket_id': ticket_id,
        'subject': ticket.get('subject', 'Unknown'),
        'body': ticket.get('body', ''),
        'customer': ticket.get('customer', 'Unknown'),
        'channel': ticket.get('channel', 'web'),
        'submitted_at': ticket.get('submitted_at', now),
        'processed_at': now,
        'status': 'failed',
        'urgency': 'unknown',
        'category': 'unknown',
        'classification_reasoning': '',
        'ai_response': '',
        'sla_deadline': now,
        'sla_breached': False,
        'error_details': json.dumps(error)
    }

    table.put_item(Item=item)

    print(f"Error stored for ticket {ticket_id}")

    return {
        'error_handled': True,
        'ticket_id': ticket_id
    }


def get_sla_minutes(urgency):
    """Get SLA minutes from environment variables based on urgency."""
    sla_map = {
        'critical': int(os.environ.get('SLA_CRITICAL_MIN', '5')),
        'high': int(os.environ.get('SLA_HIGH_MIN', '15')),
        'medium': int(os.environ.get('SLA_MEDIUM_MIN', '30')),
        'low': int(os.environ.get('SLA_LOW_MIN', '60'))
    }
    return sla_map.get(urgency, 30)