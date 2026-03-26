import json
import boto3
import os
from datetime import datetime, timezone
from boto3.dynamodb.conditions import Attr

dynamodb = boto3.resource('dynamodb')
sns = boto3.client('sns')


def lambda_handler(event, context):
    """
    SLA Checker: finds tickets that exceeded their SLA deadline.
    Checks TWO scenarios:
    1. Processed tickets where SLA deadline passed
    2. Stuck tickets still in 'submitted' status too long
    Triggered by EventBridge every X minutes.
    """

    table = dynamodb.Table(os.environ['DYNAMODB_TABLE'])
    topic_arn = os.environ['SNS_TOPIC_ARN']

    now = datetime.now(timezone.utc).isoformat()

    print(f"SLA check running at {now}")

    # Check 1: Processed tickets with expired SLA
    processed_breaches = find_processed_breaches(table, now)

    # Check 2: Stuck tickets (still 'submitted' after SLA deadline)
    stuck_tickets = find_stuck_tickets(table, now)

    total_issues = len(processed_breaches) + len(stuck_tickets)

    if total_issues == 0:
        print("No SLA breaches or stuck tickets found")
        return {'breaches_found': 0, 'stuck_found': 0}

    # Mark processed breaches
    for ticket in processed_breaches:
        mark_as_breached(table, ticket['ticket_id'], now)

    # Mark stuck tickets
    for ticket in stuck_tickets:
        mark_as_stuck(table, ticket['ticket_id'], now)

    # Send combined alert
    send_alert(topic_arn, processed_breaches, stuck_tickets, now)

    return {
        'breaches_found': len(processed_breaches),
        'stuck_found': len(stuck_tickets),
        'breached_ids': [t['ticket_id'] for t in processed_breaches],
        'stuck_ids': [t['ticket_id'] for t in stuck_tickets]
    }


def find_processed_breaches(table, now):
    """Find processed tickets where SLA deadline has passed."""

    result = table.scan(
        FilterExpression=(
            Attr('status').is_in(['submitted', 'processed']) &
            Attr('sla_breached').eq(False) &
            Attr('sla_deadline').lt(now)
        )
    )

    tickets = result.get('Items', [])
    print(f"Found {len(tickets)} processed SLA breaches")
    return tickets


def find_stuck_tickets(table, now):
    """
    Find tickets stuck in 'submitted' status.
    If a ticket is still 'submitted' after the maximum SLA time (critical = 5 min),
    something went wrong in the pipeline.
    """

    # Use critical SLA as threshold for stuck detection
    # If ticket hasn't been processed within critical SLA time, it's stuck
    result = table.scan(
        FilterExpression=(
            Attr('status').eq('submitted') &
            Attr('submitted_at').lt(now)
        )
    )

    # Filter: only tickets submitted more than 5 minutes ago
    stuck = []
    for ticket in result.get('Items', []):
        minutes_waiting = calculate_minutes_over(ticket['submitted_at'], now)
        if minutes_waiting > 5:
            stuck.append(ticket)

    print(f"Found {len(stuck)} stuck tickets")
    return stuck


def mark_as_breached(table, ticket_id, now):
    """Mark processed ticket as SLA breached."""

    table.update_item(
        Key={'ticket_id': ticket_id},
        UpdateExpression='SET sla_breached = :val, sla_breached_at = :time',
        ExpressionAttributeValues={
            ':val': True,
            ':time': now
        }
    )
    print(f"Ticket {ticket_id} marked as SLA breached")


def mark_as_stuck(table, ticket_id, now):
    """Mark submitted ticket as stuck."""

    table.update_item(
        Key={'ticket_id': ticket_id},
        UpdateExpression='SET #s = :status, sla_breached = :val, sla_breached_at = :time, stuck_detected_at = :time',
        ExpressionAttributeNames={
            '#s': 'status' # status is a reserved keyword in DynamoDB hence an alias
        },
        ExpressionAttributeValues={
            ':status': 'stuck',
            ':val': True,
            ':time': now
        }
    )
    print(f"Ticket {ticket_id} marked as STUCK")


def send_alert(topic_arn, processed_breaches, stuck_tickets, now):
    """Send combined SLA alert."""

    message_lines = [
        "SLA MONITORING ALERT",
        "",
        f"Time: {now}",
        f"SLA breaches: {len(processed_breaches)}",
        f"Stuck tickets: {len(stuck_tickets)}",
        ""
    ]

    if processed_breaches:
        message_lines.append("=== SLA BREACHES (processed too late) ===")
        message_lines.append("")
        for ticket in processed_breaches:
            minutes_over = calculate_minutes_over(ticket['sla_deadline'], now)
            message_lines.extend([
                f"Ticket: {ticket['ticket_id']}",
                f"Customer: {ticket.get('customer', 'Unknown')}",
                f"Subject: {ticket.get('subject', 'No subject')}",
                f"Urgency: {ticket.get('urgency', 'unknown')}",
                f"Overdue by: {minutes_over} minutes",
                ""
            ])

    if stuck_tickets:
        message_lines.append("=== STUCK TICKETS (pipeline failure) ===")
        message_lines.append("")
        for ticket in stuck_tickets:
            minutes_waiting = calculate_minutes_over(ticket['submitted_at'], now)
            message_lines.extend([
                f"Ticket: {ticket['ticket_id']}",
                f"Customer: {ticket.get('customer', 'Unknown')}",
                f"Subject: {ticket.get('subject', 'No subject')}",
                f"Waiting: {minutes_waiting} minutes",
                f"ACTION: Check Kinesis/SQS/Step Functions logs",
                ""
            ])

    sns.publish(
        TopicArn=topic_arn,
        Subject=f"SLA ALERT: {len(processed_breaches)} breaches, {len(stuck_tickets)} stuck",
        Message="\n".join(message_lines)
    )

    print("SLA alert sent")


def calculate_minutes_over(time_str, now_str):
    """Calculate minutes between two ISO timestamps."""
    try:
        t1 = datetime.fromisoformat(time_str)
        t2 = datetime.fromisoformat(now_str)
        delta = t2 - t1
        return max(0, int(delta.total_seconds() / 60))
    except (ValueError, TypeError):
        return 0
