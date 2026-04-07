# Storage Upload Documentation (v2.0)

## 1. Directory Structure
Files must be organized in a segmented directory tree. Each user has a dedicated subfolder named after their unique `user_id`.

**Path Scheme:**
`/storage_root/{user_id}/`

**Example:**
- `/storage_root/user_12345/data_report.csv`
- `/storage_root/user_12345/data_report.json`

---

## 2. Manifest Format (JSON)
The manifest file must be a valid JSON object located in the same directory as the data file.

**Required Fields:**
*   `user_id`: (String) Unique user identifier. Must match the parent folder name.
*   `user_email`: (String) User's contact email for processing status/results.
*   `subscription_type`: (Enum) Must be exactly one of: `FREE_TRIAL`, `STANDARD`, `PREMIUM`.
*   `file_name`: (String) The exact name of the CSV file (including extension) located in the same folder.
*   `upload_timestamp`: (Integer) Upload time in **Unix Timestamp** format (seconds since Jan 01 1970, UTC).

**Example `data_report.json`:**
```json
{
  "user_id": "user_12345",
  "user_email": "client@example.com",
  "subscription_type": "STANDARD",
  "file_name": "data_report.csv",
  "upload_timestamp": 1712512500
}
```

## 3. Processing Rules & Business Logic
The backend automation script follows these validation rules:

1.  **Time Window:** Only files with an `upload_timestamp` within the **last 24 hours** (86,400 seconds) from the current server time will be processed.
2.  **Model Mapping:**
    *   `FREE_TRIAL` triggers **RandomForest** model.
    *   `STANDARD` triggers **LGBM** model.
    *   `PREMIUM` triggers **Model_3**.
3.  **File Integrity:** The script will ignore the entry if the `file_name` specified in the JSON does not exist in the user's folder.

---

## 4. Constraints
*   **Encoding:** Use UTF-8 for JSON files.
*   **Case Sensitivity:** File names and folder names are case-sensitive.
*   **Timestamp:** Ensure the `upload_timestamp` is generated in **UTC** to avoid timezone mismatches with the server.