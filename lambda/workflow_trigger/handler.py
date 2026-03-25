import json
import boto3
import os

sfn = boto3.client('stepfunctions')


def lambda_handler(event, context):
    """
    Workflow trigger: reads ticket from SQS, starts Step Functions execution.
    Triggered automatically by SQS event source mapping.
    """

    state_machine_arn = os.environ['STATE_MACHINE_ARN']
    records = event.get('Records', [])

    print(f"Received {len(records)} messages from SQS")

    for record in records:
        try:
            ticket = json.loads(record['body'])
            ticket_id = ticket.get('ticket_id', 'unknown')

            print(f"Starting workflow for ticket {ticket_id}")

            # Start Step Functions execution
            sfn.start_execution(
                stateMachineArn=state_machine_arn,
                name=f"ticket-{ticket_id}",
                input=json.dumps({'ticket': ticket})
            )

            print(f"Workflow started for ticket {ticket_id}")

        except Exception as e:
            print(f"Error starting workflow: {str(e)}")
            raise  # Re-raise so SQS retries (and eventually sends to DLQ)

    return {'statusCode': 200, 'started': len(records)}