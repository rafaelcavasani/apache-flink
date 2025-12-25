"""
Spark Structured Streaming Job para Agregação de Recebíveis
Equivalente ao GenericEventAggregator.java do Flink
"""

import json
import logging
from datetime import datetime
from typing import List, Dict, Any

from pyspark.sql import SparkSession, DataFrame
from pyspark.sql.functions import (
    from_json, col, window, collect_list, count, sum as spark_sum,
    current_timestamp, udf, struct, lit
)
from pyspark.sql.types import (
    StructType, StructField, StringType, DoubleType, IntegerType,
    ArrayType, LongType, TimestampType
)

from dynamodb_enricher import enrich_with_dynamodb
from elasticsearch_writer import write_to_elasticsearch
from dynamodb_writer import write_events_to_dynamodb

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(name)s - %(message)s'
)
logger = logging.getLogger(__name__)


def load_config(config_path: str = "config/application.json") -> Dict[str, Any]:
    """Load configuration from JSON file"""
    with open(config_path, 'r') as f:
        return json.load(f)


def get_kafka_schema() -> StructType:
    """Define schema for Kafka events"""
    return StructType([
        StructField("id_recebivel", StringType(), True),
        StructField("id_pagamento", StringType(), True),
        StructField("tipo_evento", StringType(), True),
        StructField("timestamp", StringType(), True),
        StructField("valor_original", DoubleType(), True),
        StructField("valor_cancelado", DoubleType(), True),
        StructField("valor_negociado", DoubleType(), True),
        StructField("codigo_produto", IntegerType(), True),
        StructField("codigo_produto_parceiro", IntegerType(), True),
        StructField("modalidade", IntegerType(), True),
        StructField("data_vencimento", StringType(), True),
        StructField("id_cancelamento", StringType(), True),
        StructField("data_cancelamento", StringType(), True),
        StructField("motivo", StringType(), True),
        StructField("id_negociacao", StringType(), True),
        StructField("data_negociacao", StringType(), True)
    ])


def create_spark_session(app_name: str, config: Dict[str, Any]) -> SparkSession:
    """Create and configure Spark session"""
    spark_config = config.get("spark", {})
    
    builder = SparkSession.builder.appName(app_name)
    
    # Add Kafka package
    builder = builder.config(
        "spark.jars.packages",
        "org.apache.spark:spark-sql-kafka-0-10_2.12:3.5.0,"
        "org.elasticsearch:elasticsearch-spark-30_2.12:8.11.0,"
        "software.amazon.awssdk:dynamodb:2.20.0,"
        "com.amazonaws:aws-java-sdk-dynamodb:1.12.500"
    )
    
    # Configure checkpointing
    checkpoint_dir = spark_config.get("checkpoint.location", "/tmp/spark-checkpoints")
    builder = builder.config("spark.sql.streaming.checkpointLocation", checkpoint_dir)
    
    # Configure parallelism
    shuffle_partitions = spark_config.get("shuffle.partitions", 10)
    builder = builder.config("spark.sql.shuffle.partitions", shuffle_partitions)
    
    return builder.getOrCreate()


def read_from_kafka(spark: SparkSession, config: Dict[str, Any]) -> DataFrame:
    """Read streaming data from Kafka"""
    kafka_config = config["kafka"]
    topics = ",".join(kafka_config["input.topics"])
    
    logger.info(f"Reading from Kafka topics: {topics}")
    
    df = (spark
        .readStream
        .format("kafka")
        .option("kafka.bootstrap.servers", kafka_config["bootstrap.servers"])
        .option("subscribe", topics)
        .option("startingOffsets", kafka_config.get("auto.offset.reset", "earliest"))
        .option("failOnDataLoss", "false")
        .load()
    )
    
    # Parse JSON from Kafka value
    schema = get_kafka_schema()
    
    parsed_df = (df
        .select(from_json(col("value").cast("string"), schema).alias("data"))
        .select("data.*")
    )
    
    logger.info("Kafka stream configured successfully")
    return parsed_df


def aggregate_events(df: DataFrame, config: Dict[str, Any]) -> DataFrame:
    """
    Aggregate events by id_recebivel within time windows
    Equivalent to EventAggregator.java
    """
    agg_config = config["aggregation"]
    window_duration = f"{int(agg_config['window.size.minutes'] * 60)} seconds"
    
    logger.info(f"Configuring aggregation with window duration: {window_duration}")
    
    # Add timestamp for windowing (use current timestamp for processing time)
    df_with_time = df.withColumn("event_time", current_timestamp())
    
    # Aggregate by id_recebivel and time window
    aggregated = (df_with_time
        .groupBy(
            col("id_recebivel"),
            window(col("event_time"), window_duration)
        )
        .agg(
            count("*").alias("event_count"),
            collect_list(
                struct(
                    col("tipo_evento"),
                    col("id_pagamento"),
                    col("timestamp"),
                    col("valor_original"),
                    col("valor_cancelado"),
                    col("valor_negociado"),
                    col("codigo_produto"),
                    col("codigo_produto_parceiro"),
                    col("modalidade"),
                    col("data_vencimento"),
                    col("id_cancelamento"),
                    col("data_cancelamento"),
                    col("motivo"),
                    col("id_negociacao"),
                    col("data_negociacao")
                )
            ).alias("events")
        )
        .select(
            col("id_recebivel"),
            col("window.start").alias("window_start"),
            col("window.end").alias("window_end"),
            col("event_count"),
            col("events"),
            current_timestamp().alias("processing_time")
        )
    )
    
    logger.info("Aggregation configured successfully")
    return aggregated


def process_batch(batch_df: DataFrame, batch_id: int, config: Dict[str, Any]):
    """
    Process each micro-batch:
    1. Persist events to DynamoDB
    2. Enrich with historical data from DynamoDB
    3. Write to Elasticsearch
    
    Equivalent to the Flink pipeline: DynamoDBEventWriter -> DynamoDBEnricher -> ElasticsearchSink
    """
    logger.info(f"Processing batch {batch_id} with {batch_df.count()} records")
    
    if batch_df.isEmpty():
        logger.info(f"Batch {batch_id} is empty, skipping")
        return
    
    try:
        # Step 1: Write individual events to DynamoDB
        write_events_to_dynamodb(batch_df, config)
        
        # Step 2: Enrich aggregations with DynamoDB historical data
        enriched_df = enrich_with_dynamodb(batch_df, config)
        
        # Step 3: Write enriched data to Elasticsearch
        write_to_elasticsearch(enriched_df, config)
        
        logger.info(f"Batch {batch_id} processed successfully")
        
    except Exception as e:
        logger.error(f"Error processing batch {batch_id}: {str(e)}", exc_info=True)
        raise


def main():
    """Main entry point for the Spark Streaming job"""
    logger.info("Starting Receivable Aggregator Spark Job")
    
    # Load configuration
    config = load_config()
    logger.info("Configuration loaded successfully")
    
    # Create Spark session
    spark = create_spark_session("Receivable Aggregator", config)
    spark.sparkContext.setLogLevel("WARN")
    
    try:
        # Read from Kafka
        kafka_stream = read_from_kafka(spark, config)
        
        # Aggregate events
        aggregated_stream = aggregate_events(kafka_stream, config)
        
        # Process each batch with DynamoDB and Elasticsearch operations
        query = (aggregated_stream
            .writeStream
            .foreachBatch(lambda batch_df, batch_id: process_batch(batch_df, batch_id, config))
            .outputMode("update")
            .option("checkpointLocation", config["spark"]["checkpoint.location"])
            .trigger(processingTime="15 seconds")
            .start()
        )
        
        logger.info("Streaming query started successfully")
        logger.info("Waiting for streaming query to terminate...")
        
        # Wait for termination
        query.awaitTermination()
        
    except KeyboardInterrupt:
        logger.info("Received interrupt signal, stopping gracefully...")
        spark.stop()
    except Exception as e:
        logger.error(f"Fatal error in main: {str(e)}", exc_info=True)
        spark.stop()
        raise


if __name__ == "__main__":
    main()
