"""
Elasticsearch Writer - Writes enriched data to Elasticsearch
Equivalent to ElasticsearchSink.java
"""

import logging
import json
from typing import Dict, Any
from pyspark.sql import DataFrame
from elasticsearch import Elasticsearch, helpers

logger = logging.getLogger(__name__)


def write_to_elasticsearch(enriched_df: DataFrame, config: Dict[str, Any]):
    """
    Write enriched CicloVidaRecebivel data to Elasticsearch
    Equivalent to ElasticsearchSink.invoke()
    """
    es_config = config["elasticsearch"]
    hosts = es_config["hosts"]
    index_name = es_config["index.name"]
    
    logger.info(f"Writing to Elasticsearch index: {index_name}")
    
    # Collect data
    records = enriched_df.collect()
    
    if not records:
        logger.info("No records to write to Elasticsearch")
        return
    
    # Initialize Elasticsearch client
    es = Elasticsearch(hosts)
    
    logger.info(f"Writing {len(records)} records to Elasticsearch")
    
    # Prepare bulk actions
    actions = []
    for record in records:
        try:
            # Convert Row to dictionary
            doc = record.asDict(recursive=True)
            
            # Convert timestamp fields to proper format
            if doc.get('window_start'):
                doc['window_start'] = int(doc['window_start'])
            if doc.get('window_end'):
                doc['window_end'] = int(doc['window_end'])
            
            # Prepare action
            action = {
                "_index": index_name,
                "_id": doc["id_recebivel"],
                "_source": doc
            }
            actions.append(action)
            
            logger.debug(f"Prepared document for ES: {doc['id_recebivel']}")
            
        except Exception as e:
            logger.error(f"Error preparing document for Elasticsearch: {str(e)}", exc_info=True)
            continue
    
    # Bulk index
    if actions:
        try:
            success, failed = helpers.bulk(es, actions, raise_on_error=False)
            logger.info(f"Elasticsearch bulk write: {success} successful, {len(failed)} failed")
            
            if failed:
                for item in failed[:5]:  # Log first 5 failures
                    logger.error(f"Failed to index document: {item}")
                    
        except Exception as e:
            logger.error(f"Error during bulk write to Elasticsearch: {str(e)}", exc_info=True)
            # Try individual writes as fallback
            for action in actions:
                try:
                    es.index(
                        index=action["_index"],
                        id=action["_id"],
                        document=action["_source"]
                    )
                    logger.info(f"Document indexed successfully (fallback): {action['_id']}")
                except Exception as e2:
                    logger.error(f"Failed to index document {action['_id']}: {str(e2)}")
    
    logger.info(f"Successfully wrote {len(actions)} records to Elasticsearch")
