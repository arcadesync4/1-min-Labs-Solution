
#!/bin/bash

# Exit on error
set -e

# Set project ID and number (replace manually if known)
PROJECT_ID=$(gcloud config get-value project)
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format="value(projectNumber)")
SERVICE_ACCOUNT="$PROJECT_NUMBER-compute@developer.gserviceaccount.com"

# Create BigQuery dataset and table
bq mk --dataset "$PROJECT_ID:lab_625"
bq mk --table --schema=gs://cloud-training/gsp323/lab.schema "$PROJECT_ID:lab_625.customers_363"

# Create GCS bucket
BUCKET_NAME=qwiklabs-gcp-00-06125bcc9b0c-marking
gsutil mb -p "$PROJECT_ID" -l us-central1 "gs://$BUCKET_NAME"

# IAM: Grant roles to default compute service account
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$SERVICE_ACCOUNT" \
  --role="roles/editor"

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$SERVICE_ACCOUNT" \
  --role="roles/storage.admin"

# Start Dataflow job
gcloud dataflow jobs run text-to-bq-job \
  --gcs-location=gs://dataflow-templates/latest/TextIOToBigQuery \
  --region=us-central1 \
  --parameters \
inputFilePattern=gs://cloud-training/gsp323/lab.csv,\
JSONPath=gs://cloud-training/gsp323/lab.schema,\
outputTable="$PROJECT_ID:lab_625.customers_363",\
bigQueryLoadingTemporaryDirectory=gs://$BUCKET_NAME/bigquery_temp,\
javascriptTextTransformGcsPath=gs://cloud-training/gsp323/lab.js,\
javascriptTextTransformFunctionName=transform,\
tempLocation=gs://$BUCKET_NAME/temp,\
outputDeadletterTable="$PROJECT_ID:lab_625.deadletter" \
  --max-workers=2 \
  --worker-machine-type=e2-standard-2

# Create Dataproc cluster
gcloud dataproc clusters create compute-engine \
  --region=us-central1 \
  --zone=us-central1-a \
  --master-machine-type=e2-standard-2 \
  --worker-machine-type=e2-standard-2 \
  --max-workers=2 \
  --image-version=2.0-debian10 \
  --master-boot-disk-size=100 \
  --worker-boot-disk-size=100 \
  --no-address

# Copy file into HDFS on Dataproc
gcloud compute ssh compute-engine-m --zone=us-central1-a --command "hdfs dfs -cp gs://cloud-training/gsp323/data.txt /data.txt"

# Run Dataproc Spark job
gcloud dataproc jobs submit spark \
  --cluster=compute-engine \
  --region=us-central1 \
  --class=org.apache.spark.examples.SparkPageRank \
  --jars=file:///usr/lib/spark/examples/jars/spark-examples.jar \
  -- "$@"

# Speech-to-Text API
gcloud ml speech recognize-long-running "gs://cloud-training/gsp323/task3.flac" \
  --language-code='en-US' > speech_result.json

gsutil cp speech_result.json "gs://$BUCKET_NAME/task3-gcs-976.result"

# Cloud Natural Language API
echo "Old Norse texts portray Odin as one-eyed and long-bearded, frequently wielding a spear named Gungnir and wearing a cloak and a broad hat." > odin.txt

gcloud ml language analyze-entities --content-file=odin.txt > odin_result.json

gsutil cp odin_result.json "gs://$BUCKET_NAME/task4-cnl-892.result"

echo "✅ Lab tasks completed successfully!"
