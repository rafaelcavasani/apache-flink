"""
Script de teste para validar o job Spark
Testa componentes individualmente antes de executar o streaming completo
"""

import sys
import logging
from pathlib import Path

# Add src to path
sys.path.insert(0, str(Path(__file__).parent / "src"))

from pyspark.sql import SparkSession
from pyspark.sql.types import StructType, StructField, StringType, DoubleType, IntegerType
import json

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def test_spark_session():
    """Test Spark session creation"""
    logger.info("Testing Spark session creation...")
    
    spark = SparkSession.builder \
        .appName("Test Spark Session") \
        .master("local[*]") \
        .getOrCreate()
    
    spark.sparkContext.setLogLevel("WARN")
    logger.info("✅ Spark session created successfully")
    
    return spark


def test_dynamodb_connection():
    """Test DynamoDB connection"""
    logger.info("Testing DynamoDB connection...")
    
    try:
        import boto3
        
        dynamodb = boto3.resource(
            'dynamodb',
            endpoint_url='http://localhost:8000',
            region_name='us-east-1'
        )
        
        # List tables
        tables = list(dynamodb.tables.all())
        logger.info(f"✅ DynamoDB connected. Tables: {[t.name for t in tables]}")
        
        return True
    except Exception as e:
        logger.error(f"❌ DynamoDB connection failed: {e}")
        return False


def test_elasticsearch_connection():
    """Test Elasticsearch connection"""
    logger.info("Testing Elasticsearch connection...")
    
    try:
        from elasticsearch import Elasticsearch
        
        es = Elasticsearch(['http://localhost:9200'])
        info = es.info()
        logger.info(f"✅ Elasticsearch connected. Version: {info['version']['number']}")
        
        return True
    except Exception as e:
        logger.error(f"❌ Elasticsearch connection failed: {e}")
        return False


def test_schema():
    """Test event schema parsing"""
    logger.info("Testing event schema...")
    
    spark = test_spark_session()
    
    # Sample event
    sample_event = {
        "id_recebivel": "test-123",
        "id_pagamento": "pag-456",
        "tipo_evento": "agendado",
        "timestamp": "2024-12-24T18:00:00Z",
        "valor_original": 10000.0,
        "codigo_produto": 1,
        "codigo_produto_parceiro": 2,
        "modalidade": 1,
        "data_vencimento": "2025-01-15"
    }
    
    # Create DataFrame
    df = spark.createDataFrame([sample_event])
    
    logger.info("Sample event schema:")
    df.printSchema()
    
    logger.info("Sample data:")
    df.show(truncate=False)
    
    logger.info("✅ Schema test passed")
    
    return True


def test_config_loading():
    """Test configuration loading"""
    logger.info("Testing configuration loading...")
    
    config_path = Path(__file__).parent / "config" / "application.json"
    
    if not config_path.exists():
        logger.error(f"❌ Config file not found: {config_path}")
        return False
    
    with open(config_path, 'r') as f:
        config = json.load(f)
    
    logger.info("Configuration loaded:")
    logger.info(f"  Kafka topics: {config['kafka']['input.topics']}")
    logger.info(f"  Window size: {config['aggregation']['window.size.minutes']} minutes")
    logger.info(f"  DynamoDB table: {config['dynamodb']['table.name']}")
    logger.info(f"  Elasticsearch index: {config['elasticsearch']['index.name']}")
    
    logger.info("✅ Configuration test passed")
    
    return True


def main():
    """Run all tests"""
    print("=" * 60)
    print("Spark Job Test Suite")
    print("=" * 60)
    print()
    
    tests = [
        ("Configuration Loading", test_config_loading),
        ("Spark Session", test_spark_session),
        ("Event Schema", test_schema),
        ("DynamoDB Connection", test_dynamodb_connection),
        ("Elasticsearch Connection", test_elasticsearch_connection)
    ]
    
    results = []
    
    for test_name, test_func in tests:
        print(f"\n{'='*60}")
        print(f"Running: {test_name}")
        print('='*60)
        
        try:
            result = test_func()
            if result or result is None:
                results.append((test_name, True))
                print(f"✅ {test_name} PASSED")
            else:
                results.append((test_name, False))
                print(f"❌ {test_name} FAILED")
        except Exception as e:
            results.append((test_name, False))
            logger.error(f"❌ {test_name} FAILED with exception: {e}", exc_info=True)
    
    # Summary
    print("\n" + "=" * 60)
    print("Test Summary")
    print("=" * 60)
    
    passed = sum(1 for _, result in results if result)
    total = len(results)
    
    for test_name, result in results:
        status = "✅ PASS" if result else "❌ FAIL"
        print(f"{status} - {test_name}")
    
    print("=" * 60)
    print(f"Total: {passed}/{total} tests passed")
    print("=" * 60)
    
    if passed == total:
        print("\n🎉 All tests passed! Ready to run the Spark job.")
        return 0
    else:
        print(f"\n⚠️  {total - passed} test(s) failed. Please fix issues before running the job.")
        return 1


if __name__ == "__main__":
    sys.exit(main())
