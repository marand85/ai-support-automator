#!/bin/bash

# AI Support Ticket Automator - Sample Tickets
# Usage: ./tickets.sh <API_ENDPOINT>
# Example: ./tickets.sh https://abc123.execute-api.eu-west-2.amazonaws.com

API=$1

if [ -z "$API" ]; then
  echo "Usage: ./tickets.sh <API_ENDPOINT>"
  echo "Example: ./tickets.sh https://abc123.execute-api.eu-west-2.amazonaws.com"
  exit 1
fi

echo "=== Submitting 5 sample tickets ==="
echo ""

# Ticket 1: CRITICAL - Payment system down
echo "1/5 - Critical: Payment system DOWN"
curl -s -X POST "$API/tickets" \
  -H "Content-Type: application/json" \
  -d '{
    "channel": "email",
    "subject": "Payment system completely DOWN",
    "body": "No customers can make payments since 10:00 AM. All transactions are failing with error code 500. This is affecting all users globally. Revenue loss estimated at $10,000 per hour.",
    "customer": "acme-corp"
  }' | python3 -m json.tool
echo ""

sleep 2

# Ticket 2: HIGH - Login issues
echo "2/5 - High: Cannot login"
curl -s -X POST "$API/tickets" \
  -H "Content-Type: application/json" \
  -d '{
    "channel": "web",
    "subject": "Cannot login to admin dashboard",
    "body": "Getting 403 Forbidden error when trying to access the admin panel. Tried clearing cookies and different browsers. Need access urgently to process end-of-month reports.",
    "customer": "globex-inc"
  }' | python3 -m json.tool
echo ""

sleep 2

# Ticket 3: MEDIUM - Report bug
echo "3/5 - Medium: Report shows wrong data"
curl -s -X POST "$API/tickets" \
  -H "Content-Type: application/json" \
  -d '{
    "channel": "web",
    "subject": "Monthly report shows incorrect dates",
    "body": "The monthly revenue report for March is showing February data. The date filter seems to be off by one month. This is not blocking but needs to be fixed before the board meeting next week.",
    "customer": "initech-llc"
  }' | python3 -m json.tool
echo ""

sleep 2

# Ticket 4: LOW - Feature request
echo "4/5 - Low: Feature request"
curl -s -X POST "$API/tickets" \
  -H "Content-Type: application/json" \
  -d '{
    "channel": "email",
    "subject": "Request: dark mode for dashboard",
    "body": "Would be great to have a dark mode option for the analytics dashboard. Several team members have requested this for late-night monitoring sessions.",
    "customer": "wayne-enterprises"
  }' | python3 -m json.tool
echo ""

sleep 2

# Ticket 5: CRITICAL - Security breach
echo "5/5 - Critical: Security incident"
curl -s -X POST "$API/tickets" \
  -H "Content-Type: application/json" \
  -d '{
    "channel": "email",
    "subject": "Unauthorized access detected in production",
    "body": "Our monitoring detected 3 unauthorized API calls from unknown IP addresses targeting the user database. Potential data breach in progress. Need immediate investigation and possible system lockdown.",
    "customer": "stark-industries"
  }' | python3 -m json.tool
echo ""

echo "=== All 5 tickets submitted ==="
echo ""
echo "Wait ~2-3 minutes, then check results:"
echo ""
echo "  curl $API/tickets"
echo "  curl $API/tickets/stats"
echo "  curl $API/tickets/sla-breaches"
echo ""
echo "Check your email for notifications!"