# AI Support Ticket Automator

Serverless AI-powered customer support ticket processing system using 13 AWS services and Claude AI. Automatically classifies incoming tickets by urgency and category, generates AI draft responses, tracks SLA compliance, detects stuck tickets, and alerts on critical issues.

Built with **AWS Lambda**, **Kinesis Data Streams**, **Kinesis Data Firehose**, **SQS**, **Step Functions**, **DynamoDB**, **SNS**, **API Gateway**, **EventBridge**, **CloudWatch**, **S3**, **IAM** and deployed via **Terraform** (Infrastructure as Code).

## Overview

This project automatically:
- Ingests support tickets from multiple channels via REST API
- Streams tickets through **Kinesis Data Streams** with automatic S3 archival via **Firehose**
- Decouples processing with **SQS** (with Dead Letter Queue for failed messages)
- Orchestrates multi-step AI processing via **AWS Step Functions**
- Classifies ticket urgency and category using **Claude AI**
- Generates professional draft responses using **Claude AI**
- Routes critical tickets for **immediate parallel alerting**
- Stores all results in **DynamoDB** with SLA deadline tracking
- Monitors SLA compliance and detects stuck tickets via **EventBridge** scheduled checks
- Provides a **REST Dashboard API** for real-time statistics and ticket queries
- Monitors entire pipeline via **CloudWatch Dashboard** (9 metrics)

## Architecture

``` diagram
POST /tickets (API Gateway)
        |
        v
Lambda: Ingest ────────────> DynamoDB (status: submitted)
        |
        v
Kinesis Data Streams ──────> Kinesis Data Firehose ──> S3 (raw archive)
        |                    (automatic fan-out)
        v
Lambda: Stream Processor
        |
        v
SQS Queue ─────────────────> SQS Dead Letter Queue (after 3 retries)
        |
        v
Lambda: Workflow Trigger
        |
        v
┌─────────────────── Step Functions Workflow ───────────────────┐
│                                                               │
│  ClassifyTicket (Lambda → Claude AI)                          │
│       |                                                       │
│       v                                                       │
│      CheckUrgency (Choice State)                              │
│       |                        |                              │
│       v                        v                              │
│  [CRITICAL]               [DEFAULT]                           │
│       |                        |                              │
│       v                        v                              │
│  Parallel State:          GenerateResponse (Claude AI)        │
│   ├─ SendCriticalAlert         |                              │
│   └─ GenerateResponse          |                              │
│       |                        |                              │
│       v                        |                              │
│  MergeCriticalResults          |                              │
│       |                        |                              │
│       └────────┬───────────────┘                              │
│                v                                              │
│          StoreResult ────────> DynamoDB (status: processed)   │
│                |                                              │
│                v                                              │
│          NotifyCustomer ─────> SNS (email confirmation)       │
│                                                               │
│  ANY ERROR ──> HandleError ──> DynamoDB (status: failed)      │
└───────────────────────────────────────────────────────────────┘

EventBridge (every 5 min)
        |
        v
Lambda: SLA Checker
        ├── Find processed tickets past SLA deadline
        ├── Find stuck tickets (submitted > 5 min)
        └── SNS alert

Dashboard API (API Gateway):
        ├── GET  /tickets              List all tickets
        ├── GET  /tickets/{id}         Ticket details
        ├── GET  /tickets/stats        Statistics
        ├── GET  /tickets/sla-breaches SLA breach report
        └── PUT  /tickets/{id}/resolve Resolve a ticket
```

## Tech Stack

- **Cloud**: AWS (Lambda, Kinesis Data Streams, Kinesis Data Firehose, SQS, Step Functions, DynamoDB, SNS, API Gateway, EventBridge, CloudWatch, S3, IAM)
- **AI**: Claude Sonnet 4 (Anthropic)
- **Language**: Python 3.12
- **IaC**: Terraform (~1000 lines, 46 resources)
- **Libraries**: anthropic, boto3

## Step Functions Workflow

The core AI processing is orchestrated by AWS Step Functions with the following patterns:

| Pattern | Where | What it demonstrates |
|---------|-------|---------------------|
| **Choice State** | CheckUrgency | Conditional branching based on AI classification |
| **Parallel State** | CriticalPath | Concurrent execution (alert + response simultaneously) |
| **Retry** | ClassifyTicket, GenerateResponse, StoreResult | Automatic retry with exponential backoff |
| **Catch** | All steps → HandleError | Graceful error handling, failed tickets stored in DynamoDB |
| **Pass State** | MergeCriticalResults | Data transformation between parallel branches |

### Ticket Lifecycle

``` diagram
submitted ──> processed ──> resolved
  |
  ├──> sla_breached (SLA checker marks if deadline passed)
  |
  ├──> stuck (SLA checker marks if not processed within 5 min)
  |
  └──> failed (Step Functions error handler)
```

### SLA Deadlines (Demo Settings)

| Urgency | SLA Deadline | Production Recommended |
|---------|-------------|----------------------|
| Critical | 5 minutes | 1 hour |
| High | 15 minutes | 4 hours |
| Medium | 30 minutes | 24 hours |
| Low | 60 minutes | 72 hours |

A ticket is marked as **SLA breached** if it is not **resolved** (via `PUT /tickets/{id}/resolve`) before the deadline. The SLA checker runs every 5 minutes and also detects **stuck tickets** — tickets that remain in `submitted` status for more than 5 minutes, indicating a pipeline failure.

## Project Structure

``` diagram
ai-support-automator/
├── lambda/
│ ├── ingest/ # API Gateway → validate → Kinesis
│ │ └── handler.py
│ ├── stream_processor/ # Kinesis → decode → SQS
│ │ └── handler.py
│ ├── workflow_trigger/ # SQS → start Step Functions
│ │ └── handler.py
│ ├── ai_processor/ # Claude AI: classify + generate response
│ │ ├── handler.py
│ │ └── (anthropic libraries)
│ ├── ticket_operations/ # DynamoDB write, SNS alerts, error handler
│ │ └── handler.py
│ ├── dashboard_api/ # REST API: list, stats, SLA breaches, resolve
│ │ └── handler.py
│ └── sla_checker/ # EventBridge cron → SLA breach detection
│   └── handler.py
├── terraform/
│ ├── main.tf # S3, Kinesis, SQS, DynamoDB, SNS, IAM
│ ├── lambda.tf # 11 Lambda functions + event source mappings
│ ├── step_functions.tf # State machine definition (7 states)
│ ├── api_gateway.tf # HTTP API + 6 routes
│ ├── monitoring.tf # EventBridge SLA cron + CloudWatch Dashboard
│ ├── variables.tf # Configuration variables
│ ├── outputs.tf # Deploy outputs + demo instructions
│ └── terraform.tfvars.example # Example variable values
├── sample-tickets/
│ └── tickets.sh # Script to submit 5 sample tickets
├── README.md
└── .gitignore
```

## Quick Start

### Prerequisites

- AWS Account with CLI configured
- Terraform >= 1.0
- Anthropic API key
- Email address for SNS notifications

### Deployment

1. Clone repository

```bash
git clone https://github.com/marand85/ai-support-automator
cd ai-support-automator
```

2. Configure variables

``` bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars
```

Edit terraform.tfvars with your values:

``` text
aws_region         = "eu-west-2"
anthropic_api_key  = "sk-ant-your-key-here"
project_name       = "ai-support-automator"
notification_email = "your-email@example.com"
```

3. Deploy infrastructure

``` bash
terraform init
terraform apply
```

4. Confirm SNS subscriptions

Check your email and click "Confirm subscription" on both emails from AWS (alerts + critical-alerts).

5. Get API endpoint

``` bash
terraform output api_endpoint
```

## Usage

### Submit a ticket

```bash
curl -X POST https://YOUR-API-ENDPOINT/tickets \
  -H "Content-Type: application/json" \
  -d '{
    "channel": "email",
    "subject": "Payment system DOWN",
    "body": "No customers can make payments since 10:00",
    "customer": "acme-corp"
  }'
```

### Submit sample tickets (5 tickets with different priorities)

```bash
cd sample-tickets
./tickets.sh https://YOUR-API-ENDPOINT
```

### Demo Timeline

| Time | Event |
|------|-------|
| 0 min | Submit tickets via curl or tickets.sh |
| ~30 sec | Tickets flow through Kinesis → SQS → Step Functions |
| ~1 min | Claude AI classifies urgency and generates responses |
| ~2 min | Results stored in DynamoDB, email notifications sent |
| ~2 min | Critical tickets trigger immediate alert email |
| ~5 min | SLA checker runs, marks unresolved tickets as breached |

Total demo time: **~2-3 minutes** (from submission to full results)

### Check results

```bash
# List all tickets
curl https://YOUR-API-ENDPOINT/tickets

# Filter by status, urgency, or both
curl "https://YOUR-API-ENDPOINT/tickets?status=processed"
curl "https://YOUR-API-ENDPOINT/tickets?urgency=critical"
curl "https://YOUR-API-ENDPOINT/tickets?status=processed&urgency=critical"

# Get single ticket details
curl https://YOUR-API-ENDPOINT/tickets/TICKET_ID

# View statistics
curl https://YOUR-API-ENDPOINT/tickets/stats

# Check SLA breaches
curl https://YOUR-API-ENDPOINT/tickets/sla-breaches
```

### Resolve a ticket

Resolve a ticket before SLA deadline to avoid breach:

```bash
curl -X PUT https://YOUR-API-ENDPOINT/tickets/TICKET_ID/resolve
```

Response:

```json
{
  "message": "Ticket abc12345 resolved",
  "resolved_at": "2025-03-26T10:05:00+00:00",
  "resolved_within_sla": true
}
```

### View CloudWatch Dashboard

```bash
terraform output cloudwatch_dashboard_url
```

## API Reference

### Endpoints

| Method | Path | Description |
|--------|------|-------------|
| POST | /tickets | Submit a new support ticket |
| GET | /tickets | List all tickets (with optional filters) |
| GET | /tickets/{id} | Get single ticket details |
| GET | /tickets/stats | Aggregate statistics |
| GET | /tickets/sla-breaches | Tickets that exceeded SLA deadline |
| PUT | /tickets/{id}/resolve | Mark ticket as resolved |

### POST /tickets — Request Body

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| subject | string | Yes | Ticket subject line |
| body | string | Yes | Detailed description |
| customer | string | Yes | Customer identifier |
| channel | string | No | Source channel (default: "web") |

### GET /tickets — Query Parameters

| Parameter | Values | Description |
|-----------|--------|-------------|
| status | submitted, processed, resolved, stuck, failed | Filter by status |
| urgency | critical, high, medium, low | Filter by urgency |

### GET /tickets/stats — Response Example

```json
{
  "total": 7,
  "by_status": {
    "processed": 5,
    "resolved": 2
  },
  "by_urgency": {
    "critical": 3,
    "high": 2,
    "low": 2
  },
  "by_category": {
    "billing": 2,
    "technical": 3,
    "security": 1,
    "other": 1
  },
  "sla_breach_count": 6,
  "avg_processing_time_seconds": 15.9
}
```

## Key Features

- **Real-time Streaming** — Kinesis Data Streams with fan-out to processing and archival
- **Automatic Archival** — Kinesis Data Firehose delivers raw tickets to S3 with Hive-style date partitioning
- **Decoupled Processing** — SQS queue with Dead Letter Queue for failed messages (3 retries)
- **AI Orchestration** — Step Functions with branching, parallel execution, retry, and error handling
- **Dual AI Analysis** — Claude classifies urgency/category AND generates professional responses
- **Critical Path** — Critical tickets trigger parallel alert + response generation simultaneously
- **SLA Monitoring** — EventBridge scheduled checks with automatic breach detection
- **Stuck Detection** — Identifies tickets trapped in pipeline (not just slow responses)
- **Full Lifecycle** — submitted → processed → resolved (with SLA tracking at every stage)
- **Dashboard API** — REST endpoints for statistics, filtering, and SLA breach reports
- **Infrastructure as Code** — 100% Terraform deployment (~1000 lines, 46 AWS resources)
- **Observability** — CloudWatch Dashboard with 9 metrics across all services

## Security

- **Least Privilege IAM** — Separate roles for Lambda, Step Functions, and Firehose with minimal permissions
- **Encrypted Secrets** — Anthropic API key stored as encrypted Lambda environment variable
- **Private Storage** — S3 bucket blocks public access by default
- **SQS Dead Letter Queue** — Failed messages preserved for investigation (14 day retention)
- **No Authentication on API** — Add API Gateway Authorizer for production use

## Cost Estimate

| Service | Usage | Estimated Cost |
|---------|-------|---------------|
| Kinesis Data Streams | 1 shard, 24h retention | ~$0.36/day |
| Kinesis Data Firehose | < 1 GB/month | ~$0.03 |
| AWS Lambda | ~1000 invocations/month | ~$0.01 (Free Tier) |
| SQS | ~500 messages/month | $0 (Free Tier) |
| Step Functions | ~200 executions/month | $0 (Free Tier) |
| DynamoDB | < 1 GB, on-demand | $0 (Free Tier) |
| API Gateway | ~1000 requests/month | $0 (Free Tier) |
| SNS | ~100 emails/month | $0 (Free Tier) |
| S3 | < 1 GB storage | $0 (Free Tier) |
| CloudWatch | Dashboard + logs | $0 (Free Tier) |
| Claude API | ~200 requests | ~$1.00 |
| **Total** | | **~$1.40/day active, ~$0.36/day idle** |

> **Important:** Kinesis Data Streams is not included in AWS Free Tier and charges ~$0.36/day even when idle. Always run `terraform destroy` when done testing to avoid unexpected charges.

## Future Enhancements

- **Authentication** — Add API Gateway Authorizer (API keys or Cognito)
- **Ticket Updates** — PUT /tickets/{id} endpoint for editing ticket details
- **WebSocket Notifications** — Real-time dashboard updates via API Gateway WebSocket
- **Multi-language Support** — Claude auto-detects language and responds accordingly
- **Attachment Support** — S3 presigned URLs for file uploads with tickets
- **Analytics Pipeline** — Athena queries on Firehose S3 archive (Hive partitioned)
- **Auto-escalation** — Step Functions timer: if not resolved within SLA, auto-escalate to manager
- **Slack Integration** — SNS → Lambda → Slack webhook for critical alerts
- **Batch Reprocessing** — Kinesis replay capability to reprocess failed tickets
- **Custom SLA Profiles** — Per-customer SLA configuration stored in DynamoDB

## ⚠️ Clean Up (Important)

Always destroy infrastructure when done testing to avoid unexpected charges:

```bash
# 1. Empty S3 archive bucket (Firehose creates files automatically)
aws s3 rm s3://YOUR-BUCKET-NAME --recursive --region YOUR-REGION

# 2. Destroy all infrastructure
cd terraform
terraform destroy
```

Kinesis Data Streams costs ~$0.36/day even when idle.

To redeploy later, simply run `terraform apply` again — entire infrastructure recreates in ~2 minutes.

## Author

Mariusz Andrzejewski  
AI Platform Engineer  
GitHub: https://github.com/marand85

## License

MIT License