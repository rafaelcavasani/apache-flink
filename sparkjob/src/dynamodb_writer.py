"""
DynamoDB Writer - Persists individual events to DynamoDB
Equivalent to DynamoDBEventWriter.java
"""

import logging
import json
from typing import Dict, Any
import boto3
from pyspark.sql import DataFrame
from pyspark.sql.functions import col

logger = logging.getLogger(__name__)


def write_events_to_dynamodb(batch_df: DataFrame, config: Dict[str, Any]):
    """
    Write individual events from the batch to DynamoDB
    This replicates the DynamoDBEventWriter functionality
    """
    dynamodb_config = config["dynamodb"]
    table_name = dynamodb_config["table.name"]
    endpoint = dynamodb_config["endpoint"]
    region = dynamodb_config["region"]
    
    logger.info(f"Writing events to DynamoDB table: {table_name}")
    
    # Explode events array to get individual events
    events_df = batch_df.select(
        col("id_recebivel"),
        col("events")
    ).selectExpr(
        "id_recebivel",
        "explode(events) as event"
    ).select(
        col("id_recebivel"),
        col("event.*")
    )
    
    # Collect events and write to DynamoDB
    events = events_df.collect()
    
    if not events:
        logger.info("No events to write to DynamoDB")
        return
    
    # Initialize DynamoDB client
    dynamodb = boto3.resource(
        'dynamodb',
        endpoint_url=endpoint,
        region_name=region
    )
    table = dynamodb.Table(table_name)
    
    logger.info(f"Writing {len(events)} events to DynamoDB")
    
    with table.batch_writer() as batch:
        for event_row in events:
            try:
                # Build item for DynamoDB
                item = {
                    "id_recebivel": event_row.id_recebivel,
                    "tipo_evento": event_row.tipo_evento or "unknown"
                }
                
                # Add optional fields
                if event_row.id_pagamento:
                    item["id_pagamento"] = event_row.id_pagamento
                if event_row.timestamp:
                    item["timestamp"] = event_row.timestamp
                if event_row.valor_original is not None:
                    item["valor_original"] = str(event_row.valor_original)
                if event_row.valor_cancelado is not None:
                    item["valor_cancelado"] = str(event_row.valor_cancelado)
                if event_row.valor_negociado is not None:
                    item["valor_negociado"] = str(event_row.valor_negociado)
                if event_row.codigo_produto is not None:
                    item["codigo_produto"] = str(event_row.codigo_produto)
                if event_row.codigo_produto_parceiro is not None:
                    item["codigo_produto_parceiro"] = str(event_row.codigo_produto_parceiro)
                if event_row.modalidade is not None:
                    item["modalidade"] = str(event_row.modalidade)
                if event_row.data_vencimento:
                    item["data_vencimento"] = event_row.data_vencimento
                if event_row.id_cancelamento:
                    item["id_cancelamento"] = event_row.id_cancelamento
                if event_row.data_cancelamento:
                    item["data_cancelamento"] = event_row.data_cancelamento
                if event_row.motivo:
                    item["motivo"] = event_row.motivo
                if event_row.id_negociacao:
                    item["id_negociacao"] = event_row.id_negociacao
                if event_row.data_negociacao:
                    item["data_negociacao"] = event_row.data_negociacao
                
                batch.put_item(Item=item)
                logger.debug(f"Written event to DynamoDB: {event_row.id_recebivel} - {event_row.tipo_evento}")
                
            except Exception as e:
                logger.error(f"Error writing event to DynamoDB: {str(e)}", exc_info=True)
                # Continue with other events
    
    logger.info(f"Successfully wrote {len(events)} events to DynamoDB")
