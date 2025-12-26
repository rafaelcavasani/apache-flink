"""
Elasticsearch Writer - Writes enriched data to Elasticsearch
Equivalent to ElasticsearchSink.java
"""

import logging
from typing import Dict, Any
from pyspark.sql import DataFrame
from pyspark.sql.functions import col, to_json, struct

logger = logging.getLogger(__name__)


def write_to_elasticsearch(enriched_df: DataFrame, config: Dict[str, Any]):
    """
    Write enriched CicloVidaRecebivel data to Elasticsearch using Spark native connector
    Equivalent to ElasticsearchSink.invoke()
    """
    from pyspark.sql.functions import current_timestamp, date_format
    
    es_config = config["elasticsearch"]
    index_name = es_config["index.name"]
    
    logger.info(f"Writing to Elasticsearch index: {index_name}")
    
    # Check if DataFrame is empty
    count = enriched_df.count()
    if count == 0:
        logger.info("No records to write to Elasticsearch")
        return
    
    logger.info(f"Writing {count} records to Elasticsearch using Spark connector")
    
    # Add ultima_atualizacao timestamp
    df_with_timestamp = enriched_df.withColumn(
        "ultima_atualizacao",
        date_format(current_timestamp(), "yyyy-MM-dd'T'HH:mm:ss'Z'")
    )
    
    # Log a sample record for debugging
    logger.info("Sample record to be written:")
    sample = df_with_timestamp.take(1)
    if sample:
        logger.info(f"  Sample: {sample[0].asDict()}")
    
    try:
        # Write using Spark Elasticsearch connector
        # The connector handles distributed writing automatically
        df_with_timestamp.write \
            .format("org.elasticsearch.spark.sql") \
            .option("es.nodes", "elasticsearch") \
            .option("es.port", "9200") \
            .option("es.resource", index_name) \
            .option("es.mapping.id", "id_recebivel") \
            .option("es.write.operation", "upsert") \
            .option("es.nodes.wan.only", "true") \
            .mode("append") \
            .save()
        
        logger.info(f"Successfully wrote {count} records to Elasticsearch index: {index_name}")
        
    except Exception as e:
        logger.error(f"Error writing to Elasticsearch: {str(e)}", exc_info=True)
        raise
