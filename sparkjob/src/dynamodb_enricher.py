"""
DynamoDB Enricher - Enriches aggregations with historical data from DynamoDB
Equivalent to DynamoDBEnricher.java
"""

import logging
from typing import Dict, Any, List
import boto3
from decimal import Decimal
from pyspark.sql import DataFrame
from pyspark.sql.functions import udf, col
from pyspark.sql.types import (
    StructType, StructField, StringType, DoubleType, IntegerType,
    ArrayType, LongType
)

logger = logging.getLogger(__name__)


def get_enriched_schema() -> StructType:
    """Define schema for enriched CicloVidaRecebivel"""
    cancelamento_schema = StructType([
        StructField("id_cancelamento", StringType(), True),
        StructField("data_cancelamento", StringType(), True),
        StructField("valor_cancelado", DoubleType(), True),
        StructField("motivo", StringType(), True)
    ])
    
    negociacao_schema = StructType([
        StructField("id_negociacao", StringType(), True),
        StructField("data_negociacao", StringType(), True),
        StructField("valor_negociado", DoubleType(), True)
    ])
    
    return StructType([
        StructField("id_recebivel", StringType(), False),
        StructField("id_pagamento", StringType(), True),
        StructField("codigo_produto", IntegerType(), True),
        StructField("codigo_produto_parceiro", IntegerType(), True),
        StructField("modalidade", IntegerType(), True),
        StructField("valor_original", DoubleType(), True),
        StructField("data_vencimento", StringType(), True),
        StructField("cancelamentos", ArrayType(cancelamento_schema), True),
        StructField("negociacoes", ArrayType(negociacao_schema), True),
        StructField("valor_disponivel", DoubleType(), True),
        StructField("valor_total_cancelado", DoubleType(), True),
        StructField("valor_total_negociado", DoubleType(), True),
        StructField("quantidade_eventos", IntegerType(), True),
        StructField("quantidade_cancelamentos", IntegerType(), True),
        StructField("quantidade_negociacoes", IntegerType(), True),
        StructField("timestamp", StringType(), True),
        StructField("window_start", LongType(), True),
        StructField("window_end", LongType(), True)
    ])


def decimal_to_float(value):
    """Convert DynamoDB Decimal to float"""
    if isinstance(value, Decimal):
        return float(value)
    return value


def enrich_receivable(
    id_recebivel: str,
    window_start: int,
    window_end: int,
    event_count: int,
    endpoint: str,
    region: str,
    table_name: str
) -> Dict[str, Any]:
    """
    Enrich a single receivable by querying all its events from DynamoDB
    Equivalent to DynamoDBEnricher.map() method
    """
    logger.info(f"[ENRICH] Starting enrichment for id_recebivel: {id_recebivel}")
    
    # Initialize DynamoDB client
    dynamodb = boto3.resource(
        'dynamodb',
        endpoint_url=endpoint,
        region_name=region
    )
    table = dynamodb.Table(table_name)
    
    # Query all events for this receivable
    try:
        response = table.query(
            KeyConditionExpression="id_recebivel = :pk",
            ExpressionAttributeValues={
                ':pk': id_recebivel
            }
        )
        
        items = response.get('Items', [])
        logger.info(f"[ENRICH] Retrieved {len(items)} events from DynamoDB for id_recebivel: {id_recebivel}")
        
    except Exception as e:
        logger.error(f"[ENRICH] Error querying DynamoDB for {id_recebivel}: {str(e)}")
        items = []
    
    # Initialize aggregation variables
    valor_original = None
    id_pagamento = None
    codigo_produto = None
    codigo_produto_parceiro = None
    modalidade = None
    data_vencimento = None
    timestamp = None
    
    cancelamentos = []
    negociacoes = []
    total_cancelado = 0.0
    total_negociado = 0.0
    
    # Process all events
    for item in items:
        tipo_evento = item.get('tipo_evento', '')
        logger.debug(f"  [ENRICH] Processing event type: {tipo_evento} for id: {id_recebivel}")
        
        # Extract common fields from agendado event
        if tipo_evento == 'agendado':
            if valor_original is None and 'valor_original' in item:
                valor_original = decimal_to_float(item['valor_original'])
                # Ensure it's a float, not a string
                if isinstance(valor_original, str):
                    try:
                        valor_original = float(valor_original)
                    except (ValueError, TypeError):
                        valor_original = 0.0
                logger.info(f"  [ENRICH] Extracted valor_original: {valor_original} for id: {id_recebivel}")
            
            if id_pagamento is None and 'id_pagamento' in item:
                id_pagamento = item['id_pagamento']
            
            if codigo_produto is None and 'codigo_produto' in item:
                try:
                    codigo_produto = int(decimal_to_float(item['codigo_produto']))
                except (ValueError, TypeError):
                    pass
            
            if codigo_produto_parceiro is None and 'codigo_produto_parceiro' in item:
                try:
                    codigo_produto_parceiro = int(decimal_to_float(item['codigo_produto_parceiro']))
                except (ValueError, TypeError):
                    pass
            
            if modalidade is None and 'modalidade' in item:
                try:
                    modalidade = int(decimal_to_float(item['modalidade']))
                except (ValueError, TypeError):
                    pass
            
            if data_vencimento is None and 'data_vencimento' in item:
                data_vencimento = item['data_vencimento']
            
            if timestamp is None and 'timestamp' in item:
                timestamp = item['timestamp']
        
        # Process cancelamentos
        if tipo_evento == 'cancelado':
            cancelamento = {}
            
            if 'id_cancelamento' in item:
                cancelamento['id_cancelamento'] = item['id_cancelamento']
            
            if 'data_cancelamento' in item:
                cancelamento['data_cancelamento'] = item['data_cancelamento']
            
            if 'valor_cancelado' in item:
                valor = decimal_to_float(item['valor_cancelado'])
                # Ensure it's a float, not a string
                if isinstance(valor, str):
                    try:
                        valor = float(valor)
                    except (ValueError, TypeError):
                        valor = 0.0
                cancelamento['valor_cancelado'] = valor
                total_cancelado += valor
                logger.info(f"  [ENRICH] Added cancelamento with value: {valor} for id: {id_recebivel}")
            
            if 'motivo' in item:
                cancelamento['motivo'] = item['motivo']
            
            cancelamentos.append(cancelamento)
        
        # Process negociacoes
        if tipo_evento == 'negociado':
            negociacao = {}
            
            if 'id_negociacao' in item:
                negociacao['id_negociacao'] = item['id_negociacao']
            
            if 'data_negociacao' in item:
                negociacao['data_negociacao'] = item['data_negociacao']
            
            if 'valor_negociado' in item:
                valor = decimal_to_float(item['valor_negociado'])
                # Ensure it's a float, not a string
                if isinstance(valor, str):
                    try:
                        valor = float(valor)
                    except (ValueError, TypeError):
                        valor = 0.0
                negociacao['valor_negociado'] = valor
                total_negociado += valor
                logger.info(f"  [ENRICH] Added negociacao with value: {valor} for id: {id_recebivel}")
            
            negociacoes.append(negociacao)
    
    # Calculate valor_disponivel
    valor_disponivel = (valor_original or 0.0) - total_cancelado - total_negociado
    
    logger.info(
        f"[ENRICH] Completed enrichment for id: {id_recebivel} - "
        f"valor_original: {valor_original}, cancelamentos: {len(cancelamentos)}, "
        f"negociacoes: {len(negociacoes)}, total_cancelado: {total_cancelado}, "
        f"total_negociado: {total_negociado}, valor_disponivel: {valor_disponivel}"
    )
    
    # Return enriched data with proper defaults for None values
    return {
        "id_recebivel": id_recebivel,
        "id_pagamento": id_pagamento if id_pagamento else "",
        "codigo_produto": codigo_produto if codigo_produto is not None else 0,
        "codigo_produto_parceiro": codigo_produto_parceiro if codigo_produto_parceiro is not None else 0,
        "modalidade": modalidade if modalidade is not None else 0,
        "valor_original": valor_original if valor_original is not None else 0.0,
        "data_vencimento": data_vencimento if data_vencimento else "",
        "cancelamentos": cancelamentos,
        "negociacoes": negociacoes,
        "valor_disponivel": valor_disponivel,
        "valor_total_cancelado": total_cancelado,
        "valor_total_negociado": total_negociado,
        "quantidade_eventos": event_count,
        "quantidade_cancelamentos": len(cancelamentos),
        "quantidade_negociacoes": len(negociacoes),
        "timestamp": timestamp if timestamp else "",
        "window_start": window_start,
        "window_end": window_end
    }


def enrich_with_dynamodb(batch_df: DataFrame, config: Dict[str, Any]) -> DataFrame:
    """
    Enrich aggregated data with historical events from DynamoDB
    Collects aggregated data and enriches each receivable by querying DynamoDB
    """
    dynamodb_config = config["dynamodb"]
    endpoint = dynamodb_config["endpoint"]
    region = dynamodb_config["region"]
    table_name = dynamodb_config["table.name"]
    
    logger.info("Starting DynamoDB enrichment")
    
    # Collect rows to driver for enrichment (batch is already small after aggregation)
    rows = batch_df.collect()
    enriched_records = []
    
    for row in rows:
        enriched_data = enrich_receivable(
            id_recebivel=row.id_recebivel,
            window_start=int(row.window_start.timestamp()) if row.window_start else 0,
            window_end=int(row.window_end.timestamp()) if row.window_end else 0,
            event_count=row.event_count,
            endpoint=endpoint,
            region=region,
            table_name=table_name
        )
        enriched_records.append(enriched_data)
    
    # Create DataFrame from enriched records
    spark = batch_df.sparkSession
    enriched_df = spark.createDataFrame(enriched_records, schema=get_enriched_schema())
    
    logger.info("DynamoDB enrichment completed")
    return enriched_df
