import json
import boto3
import os
from datetime import datetime, timezone
from boto3.dynamodb.conditions import Key, Attr

dynamodb = boto3.resource('dynamodb')


def lambda_handler(event, context):
    """
    Dashboard API: handles all GET /tickets/* routes.
    Routes based on path from API Gateway.
    """

    table = dynamodb.Table(os.environ['DYNAMODB_TABLE'])
    path = event.get('rawPath', '')
    path_params = event.get('pathParameters', {}) or {}

    print(f"Dashboard request: {path}")

    try:
        if path == '/tickets/stats':
            result = get_stats(table)
        elif path == '/tickets/sla-breaches':
            result = get_sla_breaches(table)
        elif path_params.get('id'):
            result = get_ticket_by_id(table, path_params['id'])
        elif path == '/tickets':
            result = get_tickets(table, event)
        else:
            return response(404, {'error': f'Route not found: {path}'})

        return response(200, result)

    except Exception as e:
        print(f"Dashboard error: {str(e)}")
        return response(500, {'error': str(e)})


def get_tickets(table, event):
    """GET /tickets - list all tickets with optional filters."""

    query_params = event.get('queryStringParameters', {}) or {}
    status_filter = query_params.get('status')
    urgency_filter = query_params.get('urgency')

    # Scan with optional filters
    scan_kwargs = {}
    filter_expressions = []

    if status_filter:
        filter_expressions.append(Attr('status').eq(status_filter))
    if urgency_filter:
        filter_expressions.append(Attr('urgency').eq(urgency_filter))

    if filter_expressions:
        combined = filter_expressions[0]
        for expr in filter_expressions[1:]:
            combined = combined & expr
        scan_kwargs['FilterExpression'] = combined

    result = table.scan(**scan_kwargs)
    items = result.get('Items', [])

    # Sort by submitted_at descending (newest first)
    items.sort(key=lambda x: x.get('submitted_at', ''), reverse=True)

    # Convert DynamoDB types for JSON serialization
    items = [clean_item(item) for item in items]

    return {
        'count': len(items),
        'tickets': items
    }


def get_ticket_by_id(table, ticket_id):
    """GET /tickets/{id} - get single ticket details."""

    result = table.get_item(Key={'ticket_id': ticket_id})
    item = result.get('Item')

    if not item:
        return {'error': f'Ticket {ticket_id} not found'}

    return clean_item(item)


def get_stats(table):
    """GET /tickets/stats - aggregate statistics."""

    result = table.scan()
    items = result.get('Items', [])

    if not items:
        return {
            'total': 0,
            'by_status': {},
            'by_urgency': {},
            'by_category': {},
            'sla_breach_count': 0,
            'avg_processing_time_seconds': 0
        }

    # Count by status
    by_status = {}
    for item in items:
        status = item.get('status', 'unknown')
        by_status[status] = by_status.get(status, 0) + 1

    # Count by urgency
    by_urgency = {}
    for item in items:
        urgency = item.get('urgency', 'unknown')
        by_urgency[urgency] = by_urgency.get(urgency, 0) + 1

    # Count by category
    by_category = {}
    for item in items:
        category = item.get('category', 'unknown')
        by_category[category] = by_category.get(category, 0) + 1

    # SLA breaches
    sla_breach_count = sum(1 for item in items if item.get('sla_breached'))

    # Average processing time
    processing_times = []
    for item in items:
        submitted = item.get('submitted_at', '')
        processed = item.get('processed_at', '')
        if submitted and processed and item.get('status') == 'processed':
            try:
                t1 = datetime.fromisoformat(submitted)
                t2 = datetime.fromisoformat(processed)
                processing_times.append((t2 - t1).total_seconds())
            except (ValueError, TypeError):
                pass

    avg_time = sum(processing_times) / len(processing_times) if processing_times else 0

    return {
        'total': len(items),
        'by_status': by_status,
        'by_urgency': by_urgency,
        'by_category': by_category,
        'sla_breach_count': sla_breach_count,
        'avg_processing_time_seconds': round(avg_time, 1)
    }


def get_sla_breaches(table):
    """GET /tickets/sla-breaches - tickets that exceeded SLA."""

    result = table.scan(
        FilterExpression=Attr('sla_breached').eq(True)
    )
    items = result.get('Items', [])

    items.sort(key=lambda x: x.get('sla_deadline', ''), reverse=True)
    items = [clean_item(item) for item in items]

    return {
        'breach_count': len(items),
        'tickets': items
    }


def clean_item(item):
    """Convert DynamoDB types for JSON serialization."""
    cleaned = {}
    for key, value in item.items():
        if isinstance(value, bool):
            cleaned[key] = value
        elif isinstance(value, (int, float)):
            cleaned[key] = value
        elif hasattr(value, '__float__'):
            cleaned[key] = float(value)
        elif hasattr(value, '__int__'):
            cleaned[key] = int(value)
        else:
            cleaned[key] = str(value)
    return cleaned


def response(status_code, body):
    return {
        'statusCode': status_code,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        'body': json.dumps(body)
    }