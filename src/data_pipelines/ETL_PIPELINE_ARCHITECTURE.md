# US BeforeIT.jl Serverless Data Pipeline Architecture

## Overview

This document outlines a modern, serverless data pipeline architecture for the US BeforeIT.jl economic modeling framework. The system is designed to automatically collect, transform, and load economic data from various US government sources into BigQuery for use in agent-based macroeconomic modeling.

## Architecture Design

### System Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                           Data Sources                              │
├──────────┬──────────┬──────────┬──────────┬──────────────────────┤
│   BEA    │   BLS    │   FRED   │ Treasury │    Census Bureau     │
│   API    │   API    │   API    │  Direct  │      Data API        │
└────┬─────┴────┬─────┴────┬─────┴────┬─────┴────┬─────────────────┘
     │          │          │          │          │
     ▼          ▼          ▼          ▼          ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    Cloud Scheduler (Cron Jobs)                      │
│  • Quarterly refresh: "0 9 15 */3 *"                               │
│  • Monthly refresh: "0 9 5 * *"                                    │
│  • Weekly monetary: "0 9 * * 1"                                    │
└─────────────────────────────┬───────────────────────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      Pub/Sub Message Queue                          │
│  Topics: quarterly-refresh, monthly-refresh, weekly-refresh         │
└─────────────────────────────┬───────────────────────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                     Cloud Run Services                              │
├─────────────────────────────────────────────────────────────────────┤
│  • BEA Collector     - GDP, I-O tables, sectoral data              │
│  • BLS Collector     - Employment, wages, labor market             │
│  • FRED Collector    - Interest rates, monetary data               │
│  • Treasury Collector - Government debt, fiscal operations         │
│  • Census Collector  - Trade data, government finance              │
└─────────────────────────────┬───────────────────────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                   Cloud Storage (Raw Data Lake)                     │
│  Bucket: gs://us-beforeit-raw-data                                │
│  Structure: /source/table/year/quarter/data.json                   │
└─────────────────────────────┬───────────────────────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                  Cloud Functions (Event Triggers)                   │
│  Triggered by new files in Cloud Storage                           │
└─────────────────────────────┬───────────────────────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                 Data Transformation Service                         │
│  • NAICS to BeforeIT 71-sector mapping                            │
│  • Quarterly/annual aggregation                                    │
│  • MATLAB datenum conversion                                       │
│  • Currency scaling and normalization                             │
└─────────────────────────────┬───────────────────────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                   Data Validation Service                           │
│  • Accounting identity checks (GDP = C + I + G + NX)               │
│  • Time series consistency validation                              │
│  • Cross-sectional balance verification                            │
│  • Data quality thresholds                                         │
└─────────────────────────────┬───────────────────────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                        BigQuery Dataset                             │
│  Dataset: us_beforeit_data                                         │
│  • Core economic tables (GDP, employment, interest rates)          │
│  • Sectoral tables (71 industries, I-O matrices)                   │
│  • Financial accounts (households, firms, government, banks)       │
└─────────────────────────────────────────────────────────────────────┘
```

## Key Components

### 1. Data Sources and APIs

| Source | Data Types | Update Frequency | API Limits |
|--------|------------|------------------|------------|
| BEA | GDP, National Accounts, I-O Tables | Quarterly/Annual | 1000 req/hour |
| BLS | Employment, Wages, CPI | Monthly | 25 req/day (v2) |
| FRED | Interest Rates, Money Supply | Daily/Weekly | 120 req/min |
| Treasury | Government Debt, Fiscal Data | Monthly | No explicit limit |
| Census | Trade, Government Finance | Monthly/Annual | 500 req/day |

### 2. Cloud Scheduler Configuration

```yaml
schedules:
  - name: quarterly-data-refresh
    schedule: "0 9 15 */3 *"  # 15th day of each quarter at 9 AM
    target_topic: quarterly-refresh
    message_body: |
      {
        "data_types": ["gdp", "national_accounts", "io_tables", "sectoral_output"],
        "sources": ["BEA"]
      }
    
  - name: monthly-data-refresh
    schedule: "0 9 5 * *"     # 5th of each month at 9 AM
    target_topic: monthly-refresh
    message_body: |
      {
        "data_types": ["employment", "wages", "trade", "fiscal_operations"],
        "sources": ["BLS", "CENSUS", "TREASURY"]
      }
    
  - name: weekly-monetary-data
    schedule: "0 9 * * 1"     # Every Monday at 9 AM
    target_topic: weekly-refresh
    message_body: |
      {
        "data_types": ["interest_rates", "money_supply", "fed_balance_sheet"],
        "sources": ["FRED"]
      }
```

### 3. Cloud Run Service Architecture

Each collector service follows a standardized pattern:

```
collector-service/
├── Dockerfile
├── requirements.txt
├── main.py
├── config/
│   ├── api_endpoints.yaml
│   ├── field_mappings.json
│   └── sector_mappings.json
├── src/
│   ├── collectors/
│   │   ├── base_collector.py
│   │   ├── bea_collector.py
│   │   ├── bls_collector.py
│   │   └── ...
│   ├── transformers/
│   │   ├── base_transformer.py
│   │   ├── gdp_transformer.py
│   │   └── ...
│   └── validators/
│       ├── base_validator.py
│       └── accounting_validators.py
└── tests/
    ├── test_collectors.py
    ├── test_transformers.py
    └── test_validators.py
```

### 4. Data Transformation Pipeline

Key transformations include:

1. **Sector Mapping**: Convert NAICS codes to BeforeIT 71-sector classification
2. **Time Alignment**: Standardize quarterly/annual data with MATLAB datenum compatibility
3. **Currency Normalization**: Convert to billions USD, apply appropriate scaling
4. **Missing Data**: Interpolation strategies for incomplete time series
5. **Aggregation**: Compute required aggregates from granular data

### 5. Data Validation Framework

Validation rules by table type:

| Table Type | Validation Rules |
|------------|------------------|
| GDP & National Accounts | GDP identity (C+I+G+NX), deflator consistency |
| Sectoral Data | Row/column balance, sector totals match aggregates |
| Input-Output | Intermediate consumption balance, technical coefficients |
| Financial Accounts | Balance sheet identity, flow consistency |
| Government Finance | Revenue-expenditure balance, debt dynamics |

## Implementation Guide

### Phase 1: Infrastructure Setup (Weeks 1-2)

1. **Enable GCP Services**
2. **Create Service Accounts**
```bash
# Create service accounts with appropriate roles
gcloud iam service-accounts create etl-collector \
  --display-name="ETL Data Collector"

gcloud iam service-accounts create etl-transformer \
  --display-name="ETL Data Transformer"

gcloud iam service-accounts create etl-validator \
  --display-name="ETL Data Validator"

# Grant necessary permissions
gcloud projects add-iam-policy-binding PROJECT_ID \
  --member="serviceAccount:etl-collector@PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/storage.objectCreator"
```

3. **Initialize Storage and BigQuery**
```bash
# Create raw data bucket
gsutil mb -l us-central1 gs://marketsreplica-us-raw-data

# Set up lifecycle rules for data retention
gsutil lifecycle set lifecycle.json gs://marketsreplica-us-raw-data

# Create BigQuery dataset and tables
bq mk --location=US --dataset marketsreplica-us-data
bq query --use_legacy_sql=false < initialize_bigquery_database.sql
```

### Phase 2: Core Services Development (Weeks 3-4)

1. **Collector Service Template**
```python
# main.py
import os
import json
from datetime import datetime
from flask import Flask, request
from google.cloud import storage, pubsub_v1
import requests

app = Flask(__name__)

class BaseCollector:
    def __init__(self):
        self.api_key = os.environ.get('API_KEY')
        self.bucket_name = os.environ.get('RAW_DATA_BUCKET')
        self.storage_client = storage.Client()
        self.publisher = pubsub_v1.PublisherClient()
        
    def collect_data(self, data_type, params):
        """Override in subclasses"""
        raise NotImplementedError
        
    def save_to_gcs(self, data, metadata):
        """Save collected data to Cloud Storage"""
        bucket = self.storage_client.bucket(self.bucket_name)
        blob_name = f"{metadata['source']}/{metadata['table']}/{metadata['year']}/Q{metadata['quarter']}/data.json"
        blob = bucket.blob(blob_name)
        
        blob.upload_from_string(
            json.dumps({
                'data': data,
                'metadata': metadata,
                'collected_at': datetime.utcnow().isoformat()
            }),
            content_type='application/json'
        )
        
        return blob_name

@app.route('/collect', methods=['POST'])
def handle_collection_request():
    """Main entry point for data collection requests"""
    try:
        message = request.get_json()
        collector = create_collector(message['source'])
        
        for data_type in message['data_types']:
            data = collector.collect_data(data_type, message.get('params', {}))
            blob_name = collector.save_to_gcs(data, {
                'source': message['source'],
                'table': data_type,
                'year': datetime.now().year,
                'quarter': (datetime.now().month - 1) // 3 + 1
            })
            
            # Publish completion event
            publish_completion_event(blob_name)
            
        return {'status': 'success'}, 200
        
    except Exception as e:
        logging.error(f"Collection failed: {str(e)}")
        publish_error_event(str(e), message)
        return {'status': 'error', 'message': str(e)}, 500
```

### Phase 3: Transformation & Validation (Weeks 5-6)

1. **Transformation Service**
```python
class DataTransformer:
    def __init__(self):
        self.bq_client = bigquery.Client()
        self.dataset_id = 'us_beforeit_data'
        self.sector_mapping = self.load_sector_mapping()
        
    def transform_gdp_data(self, raw_data):
        """Transform BEA GDP data to match BigQuery schema"""
        transformed = []
        
        for record in raw_data['BEAAPI']['Results']['Data']:
            # Convert to MATLAB datenum for compatibility
            date_obj = datetime.strptime(
                f"{record['Year']}Q{record['Quarter']}", 
                "%YQ%d"
            )
            matlab_datenum = self.date_to_matlab_num(date_obj)
            
            row = {
                'date_year': int(record['Year']),
                'date_quarter': int(record['Quarter']),
                'date_matlab_num': matlab_datenum,
                'frequency': 'QUARTERLY',
                'nominal_gdp': float(record['DataValue']) / 1000,  # Convert to billions
                'real_gdp': float(record['RealValue']) / 1000,
                'gdp_deflator': float(record['Deflator']),
                'data_source': 'BEA_NIPA_TABLE_1_1_5',
                'last_updated': datetime.utcnow()
            }
            transformed.append(row)
            
        return transformed
        
    def map_to_beforeit_sectors(self, naics_data):
        """Map NAICS codes to BeforeIT 71-sector classification"""
        mapped_data = []
        
        for record in naics_data:
            naics_code = record['industry_code']
            
            if naics_code in self.sector_mapping:
                beforeit_info = self.sector_mapping[naics_code]
                record['beforeit_sector_id'] = beforeit_info['sector_id']
                record['beforeit_sector_name'] = beforeit_info['sector_name']
                mapped_data.append(record)
            else:
                logging.warning(f"Unmapped NAICS code: {naics_code}")
                
        return mapped_data
```

2. **Validation Service**
```python
class DataValidator:
    def __init__(self):
        self.tolerance = 0.01  # 1% tolerance for accounting identities
        
    def validate_gdp_identity(self, data):
        """Verify GDP = C + I + G + (X - M)"""
        errors = []
        
        for row in data:
            calculated_gdp = (
                row['nominal_consumption'] +
                row['nominal_investment'] +
                row['nominal_government'] +
                row['nominal_exports'] -
                row['nominal_imports']
            )
            
            diff = abs(calculated_gdp - row['nominal_gdp'])
            if diff > row['nominal_gdp'] * self.tolerance:
                errors.append({
                    'type': 'GDP_IDENTITY_VIOLATION',
                    'period': f"{row['date_year']}Q{row['date_quarter']}",
                    'expected': row['nominal_gdp'],
                    'calculated': calculated_gdp,
                    'difference': diff
                })
                
        return errors
        
    def validate_sectoral_totals(self, sectoral_data, aggregate_data):
        """Ensure sectoral data sums match aggregates"""
        errors = []
        
        # Group by period
        by_period = defaultdict(list)
        for row in sectoral_data:
            key = (row['date_year'], row['date_quarter'])
            by_period[key].append(row)
            
        for period, sectors in by_period.items():
            sector_sum = sum(s['value_added'] for s in sectors)
            aggregate = next(
                (a for a in aggregate_data 
                 if a['date_year'] == period[0] and 
                    a['date_quarter'] == period[1]),
                None
            )
            
            if aggregate:
                diff = abs(sector_sum - aggregate['total_value_added'])
                if diff > aggregate['total_value_added'] * self.tolerance:
                    errors.append({
                        'type': 'SECTORAL_TOTAL_MISMATCH',
                        'period': f"{period[0]}Q{period[1]}",
                        'sector_sum': sector_sum,
                        'aggregate': aggregate['total_value_added']
                    })
                    
        return errors
```

### Phase 4: Orchestration & Monitoring (Weeks 7-8)

1. **Deploy Cloud Scheduler Jobs**
```bash
# Quarterly data refresh
gcloud scheduler jobs create pubsub quarterly-gdp-refresh \
  --location=us-central1 \
  --schedule="0 9 15 1,4,7,10 *" \
  --topic=quarterly-refresh \
  --message-body='{"sources":["BEA"],"data_types":["gdp","io_tables"]}'

# Monthly data refresh  
gcloud scheduler jobs create pubsub monthly-employment-refresh \
  --location=us-central1 \
  --schedule="0 9 5 * *" \
  --topic=monthly-refresh \
  --message-body='{"sources":["BLS"],"data_types":["employment","wages"]}'
```

2. **Monitoring Dashboard Configuration**
```yaml
# monitoring-dashboard.yaml
displayName: "US BeforeIT ETL Pipeline"
mosaicLayout:
  columns: 12
  tiles:
    - width: 6
      height: 4
      widget:
        title: "Pipeline Success Rate"
        xyChart:
          dataSets:
            - timeSeriesQuery:
                timeSeriesFilter:
                  filter: 'resource.type="cloud_run_revision"
                          AND metric.type="run.googleapis.com/request_count"
                          AND metric.label.response_code_class="2xx"'
                  
    - width: 6
      height: 4
      widget:
        title: "Data Freshness"
        scorecard:
          timeSeriesQuery:
            timeSeriesFilter:
              filter: 'resource.type="bigquery_table"
                      AND metric.type="bigquery.googleapis.com/table/uploaded_bytes"'
```

### Phase 5: Testing & Deployment (Weeks 9-10)

1. **Integration Tests**
```python
# tests/test_integration.py
import pytest
from unittest.mock import Mock, patch

class TestETLPipeline:
    @pytest.fixture
    def mock_bea_response(self):
        return {
            'BEAAPI': {
                'Results': {
                    'Data': [{
                        'Year': '2023',
                        'Quarter': '4',
                        'DataValue': '27000000',
                        'RealValue': '25000000',
                        'Deflator': '108.0'
                    }]
                }
            }
        }
        
    def test_end_to_end_gdp_pipeline(self, mock_bea_response):
        """Test complete pipeline from API to BigQuery"""
        with patch('requests.get') as mock_get:
            mock_get.return_value.json.return_value = mock_bea_response
            
            # Trigger collection
            collector = BEACollector()
            data = collector.collect_data('gdp', {})
            
            # Transform data
            transformer = DataTransformer()
            transformed = transformer.transform_gdp_data(data)
            
            # Validate data
            validator = DataValidator()
            errors = validator.validate_gdp_identity(transformed)
            
            assert len(errors) == 0
            assert transformed[0]['nominal_gdp'] == 27000.0  # Billions
```

2. **Deployment Script**
```bash
#!/bin/bash
# deploy.sh

PROJECT_ID="your-project-id"
REGION="us-central1"

# Build and deploy collectors
for service in bea-collector bls-collector fred-collector; do
  echo "Deploying $service..."
  
  gcloud run deploy $service \
    --source=./services/$service \
    --region=$REGION \
    --platform=managed \
    --memory=1Gi \
    --timeout=300 \
    --max-instances=10 \
    --set-env-vars="PROJECT_ID=$PROJECT_ID,RAW_DATA_BUCKET=us-beforeit-raw-data" \
    --service-account=etl-collector@$PROJECT_ID.iam.gserviceaccount.com
done

# Deploy transformation service
gcloud run deploy data-transformer \
  --source=./services/transformer \
  --region=$REGION \
  --platform=managed \
  --memory=2Gi \
  --timeout=600 \
  --set-env-vars="PROJECT_ID=$PROJECT_ID,DATASET_ID=us_beforeit_data"

echo "Deployment complete!"
```


### Julia Code Updates

```julia
# New data loading function
function load_data_from_bigquery(dataset_id, table_name, date)
    client = BigQuery.Client()
    query = """
        SELECT *
        FROM `$(dataset_id).$(table_name)`
        WHERE date_year = $(year(date))
          AND date_quarter = $(quarter(date))
    """
    
    df = client.query(query).to_dataframe()
    return DataFrame(df)
end
```

## Conclusion

This serverless architecture provides a modern, scalable, and cost-effective solution for the US BeforeIT.jl data pipeline. By leveraging Google Cloud Platform's managed services, we eliminate operational overhead while maintaining flexibility and reliability. The modular design allows for easy extension and maintenance as data requirements evolve.

### Key Benefits

1. **Cost Efficiency**: ~$80-165/month vs thousands for traditional solutions
2. **Scalability**: Automatic scaling with no infrastructure management
3. **Reliability**: Built-in retry mechanisms and error handling
4. **Flexibility**: Easy to add new data sources or modify schedules
5. **Observability**: Comprehensive monitoring and logging

### Next Steps

1. Set up GCP project and enable APIs
2. Deploy BigQuery schema
3. Implement first collector (FRED recommended)
4. Build transformation framework
5. Deploy end-to-end for one data type
6. Expand to all data sources
7. Migrate Julia code to use BigQuery