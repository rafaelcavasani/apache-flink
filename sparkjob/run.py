#!/usr/bin/env python3
"""
Script de execução do Spark Job
"""

import os
import sys
import subprocess
from pathlib import Path

# Get script directory
SCRIPT_DIR = Path(__file__).parent.absolute()
CONFIG_PATH = SCRIPT_DIR / "config" / "application.json"

# Spark packages needed
SPARK_PACKAGES = [
    "org.apache.spark:spark-sql-kafka-0-10_2.12:3.5.0",
    "org.elasticsearch:elasticsearch-spark-30_2.12:8.11.0"
]

# AWS configuration for DynamoDB Local
os.environ["AWS_ACCESS_KEY_ID"] = "dummy"
os.environ["AWS_SECRET_ACCESS_KEY"] = "dummy"
os.environ["AWS_DEFAULT_REGION"] = "us-east-1"

def main():
    print("=" * 60)
    print("Starting Spark Receivable Aggregator Job")
    print("=" * 60)
    print()
    
    # Check if config exists
    if not CONFIG_PATH.exists():
        print(f"❌ Configuration file not found: {CONFIG_PATH}")
        sys.exit(1)
    
    print(f"✅ Configuration file: {CONFIG_PATH}")
    print(f"✅ Spark packages: {', '.join(SPARK_PACKAGES)}")
    print()
    
    # Build spark-submit command
    cmd = [
        "spark-submit",
        "--packages", ",".join(SPARK_PACKAGES),
        "--conf", "spark.sql.streaming.checkpointLocation=/tmp/spark-checkpoints",
        "--conf", "spark.sql.shuffle.partitions=10",
        str(SCRIPT_DIR / "src" / "receivable_aggregator.py")
    ]
    
    print("🚀 Executing command:")
    print(" ".join(cmd))
    print()
    print("=" * 60)
    print()
    
    try:
        # Execute spark-submit
        subprocess.run(cmd, check=True)
    except subprocess.CalledProcessError as e:
        print(f"\n❌ Error executing Spark job: {e}")
        sys.exit(1)
    except KeyboardInterrupt:
        print("\n⚠️  Job interrupted by user")
        sys.exit(0)

if __name__ == "__main__":
    main()
