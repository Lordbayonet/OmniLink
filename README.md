# Omni Link from backend and frontend
Project Report: Omnicare Diagnostic Pipeline Integration (v4.1)
Status: Integration Layer Ready / Processing Blocked by Backend Logic Errors
1. System Architecture & Data Workflow
The pipeline is designed as a secure, automated bridge between the Frontend and the ML Models. The core storage is MinIO (S3-compatible).

    Data Ingest: The Frontend is responsible for uploading raw user data into the S3 bucket.
    Organizational Standard (v2.0): Data must be stored in a segmented directory structure: /storage_root/{user_id}/.
    Trigger Mechanism: Each folder must contain two files: data_report.csv (raw data) and data_report.json (manifest). The pipeline uses the JSON manifest as a signal that the dataset is complete and ready for processing.

2. Controller Logic (run_pipeline.sh)
The controller script follows a strictly defined operational sequence:

    Queue Sync: The script mirrors the S3 bucket to a secure local temporary directory. It automatically excludes existing .pdf reports to optimize performance.
    Manifest Validation: It scans for data_report.json files, extracts metadata, and validates the upload_timestamp (24-hour window).
    Dynamic Dispatching: Based on the subscription_type (FREE_TRIAL, STANDARD, PREMIUM), it assigns the task to the correct model (model1 or model3).
    Fail-Safe Mechanism (Data Protection):
        On Success: If the PDF is generated, it is uploaded to S3, and the raw input files (CSV/JSON) are deleted from the queue.
        On Failure: If the backend fails, the source files are preserved in S3 for manual review.

3. Automation & Scheduling
To ensure stable operation and efficient resource usage, the system is configured as a daily batch process.

    Frequency: Once every 24 hours.
    Recommended Time: 02:00 AM UTC (Off-peak hours).
    Automation: Managed via Cron under the restricted service user minio.

4. Deployment & Execution Guide
Prerequisites:

    User: Service user minio with access to /home/minio/Omnivis/.
    Environment: Python 3.12+ Virtual Environment with dependencies from requirements.txt.
    Dependencies: jq (JSON processor) and mcli (MinIO client).

Manual Execution Command:
sudo -u minio HOME=/home/minio bash /home/minio/Omnivis/run_pipeline.sh

Используйте код с осторожностью.
Cron Configuration (Nightly Run):
0 2 * * * bash /home/minio/Omnivis/run_pipeline.sh

