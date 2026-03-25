import json
import anthropic
import os
from textwrap import dedent


def classify_ticket(event, context):
    """
    Step Functions task: Claude classifies ticket urgency and category.
    Input: {"ticket": {...}}
    Output: {"ticket": {...}, "classification": {"urgency": "...", "category": "..."}}
    """

    ticket = event['ticket']
    ticket_id = ticket['ticket_id']

    print(f"Classifying ticket {ticket_id}: {ticket['subject']}")

    client = anthropic.Anthropic()

    prompt = dedent(f"""
        Classify this support ticket. Return ONLY valid JSON, no other text.

        Ticket:
        Subject: {ticket['subject']}
        Body: {ticket['body']}
        Customer: {ticket['customer']}
        Channel: {ticket['channel']}

        Return this exact JSON structure:
        {{
            "urgency": "critical|high|medium|low",
            "category": "billing|technical|account|security|other",
            "reasoning": "one sentence explanation"
        }}

        Classification rules:
        - critical: system down, data loss, security breach, payment system failure
        - high: cannot use core feature, login issues, data incorrect
        - medium: non-core feature broken, slow performance, UI issues
        - low: feature request, cosmetic issue, general question
    """).strip()

    try:
        message = client.messages.create(
            model="claude-sonnet-4-20250514",
            max_tokens=256,
            messages=[{
                "role": "user",
                "content": prompt
            }]
        )

        response_text = message.content[0].text.strip()

        # Parse JSON from Claude response
        classification = parse_json_response(response_text)

        # Validate required fields
        if classification.get('urgency') not in ['critical', 'high', 'medium', 'low']:
            classification['urgency'] = 'medium'
        if classification.get('category') not in ['billing', 'technical', 'account', 'security', 'other']:
            classification['category'] = 'other'

        print(f"Ticket {ticket_id} classified: {classification['urgency']} / {classification['category']}")

    except Exception as e:
        print(f"Classification error for {ticket_id}: {str(e)}")
        classification = {
            'urgency': 'medium',
            'category': 'other',
            'reasoning': f'Auto-classified due to AI error: {str(e)}'
        }

    return {
        'ticket': ticket,
        'classification': classification
    }


def generate_response(event, context):
    """
    Step Functions task: Claude generates draft response for customer.
    Input: {"ticket": {...}, "classification": {...}}
    Output: {"ticket": {...}, "classification": {...}, "ai_response": "..."}
    """

    ticket = event['ticket']
    classification = event['classification']
    ticket_id = ticket['ticket_id']

    print(f"Generating response for ticket {ticket_id} ({classification['urgency']})")

    client = anthropic.Anthropic()

    prompt = dedent(f"""
        You are a professional customer support agent. Write a helpful response
        to this support ticket.

        Ticket:
        Subject: {ticket['subject']}
        Body: {ticket['body']}
        Customer: {ticket['customer']}

        Classification:
        Urgency: {classification['urgency']}
        Category: {classification['category']}

        Guidelines:
        - Be empathetic and professional
        - Acknowledge the issue clearly
        - Provide specific next steps
        - If critical: emphasize immediate action being taken
        - Keep response concise (3-5 sentences)
        - Do NOT include greeting or signature (those are added automatically)
    """).strip()

    try:
        message = client.messages.create(
            model="claude-sonnet-4-20250514",
            max_tokens=512,
            messages=[{
                "role": "user",
                "content": prompt
            }]
        )

        ai_response = message.content[0].text.strip()
        print(f"Response generated for {ticket_id}: {len(ai_response)} chars")

    except Exception as e:
        print(f"Response generation error for {ticket_id}: {str(e)}")
        ai_response = (
            "Thank you for contacting support. We have received your ticket "
            "and our team is reviewing it. We will get back to you shortly."
        )

    return {
        'ticket': ticket,
        'classification': classification,
        'ai_response': ai_response
    }


def parse_json_response(text):
    """
    Extract JSON from Claude response.
    Claude sometimes wraps JSON in markdown code blocks.
    """

    # Remove markdown code block if present
    if '```json' in text:
        text = text.split('```json')[1].split('```')[0]
    elif '```' in text:
        text = text.split('```')[1].split('```')[0]

    return json.loads(text.strip())