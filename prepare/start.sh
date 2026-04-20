#!/bin/bash

# --- Настройки ---
S3_ALIAS="myminio";
BUCKET_NAME="omnilink";
export HOME=/home/minio;
NOW=$(date +%s);

# Функция подготовки
prepare_task() {
    local U_ID="$1";    # Идентификатор (BobGas, JohnDig, KimBas)
    local EMAIL="$2";
    local SUB="$3";
    local SRC_CSV="$4"; # Исходный файл (например, BobGas.csv)

    echo "[TEST] Подготовка пакета для $U_ID...";

    # Константы имен из манифеста
    local TARGET_CSV="data_report.csv";
    local TARGET_JSON="data_report.json";

    # 1. Создаем JSON манифест
    cat <<EOF > "$TARGET_JSON"
{
  "user_id": "$U_ID",
  "user_email": "$EMAIL",
  "subscription_type": "$SUB",
  "file_name": "$TARGET_CSV",
  "upload_timestamp": $NOW
}
EOF

    # 2. Загружаем в S3 по пути: /omnilink/user_id/data_report...
    mcli cp "$SRC_CSV" "$S3_ALIAS/$BUCKET_NAME/$U_ID/$TARGET_CSV";
    mcli cp "$TARGET_JSON" "$S3_ALIAS/$BUCKET_NAME/$U_ID/$TARGET_JSON";

    # Очистка локального временного JSON
    rm "$TARGET_JSON";
}

# --- Запуск (используем твои исходные файлы) ---

# BobGas -> FREE_TRIAL
prepare_task "BobGas" "bob@gas.com" "FREE_TRIAL" "BobGas.csv";

# JohnDig -> STANDARD
prepare_task "JohnDig" "john@dig.com" "STANDARD" "JohnDig.csv";

# KimBas -> PREMIUM
prepare_task "KimBas" "kim@bas.com" "PREMIUM" "KimBas.csv";

echo "[DONE] Данные загружены в S3.";
mcli ls -r "$S3_ALIAS/$BUCKET_NAME";