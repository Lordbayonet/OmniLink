#!/bin/bash
##############################################################
## Script for link backend and frontend Omnicare diagnostic ##
## Author Vladimir Shumeyko(from.fmp@gmail.com)             ##
##############################################################

# --- Окружение и Безопасность ---
export HOME=/home/minio;
S3_ALIAS="myminio";
BUCKET_NAME="omnilink";
LOCAL_TMP="/tmp/pipeline_sync";
LOG_FILE="/var/log/Omnicare.log";
PROJECT_DIR="/home/minio/Omnivis";
VENV_PATH="$PROJECT_DIR/venv/bin/activate";

log_message() {
    local TYPE="$1";
    local MESSAGE="$2";
    echo "[$(date "+%Y%m%d-%H%M%S")] [$TYPE] $MESSAGE" >> "$LOG_FILE";
};

# 1. Подготовка локальной среды
mkdir -p "$LOCAL_TMP";
log_message "INFO" "--- Старт сессии обработки очереди ---";

# 2. Синхронизация из S3 (Исключаем PDF, чтобы не качать готовые отчеты)
log_message "INFO" "Синхронизация входящих данных из S3...";
mcli mirror --exclude "*.pdf" "$S3_ALIAS/$BUCKET_NAME" "$LOCAL_TMP";

# 3. Основной цикл (обход папок пользователей по наличию манифеста)
find "$LOCAL_TMP" -mindepth 2 -maxdepth 2 -type f -name "data_report.json" | while read -r json_path; do
    
    USER_DIR=$(dirname "$json_path");
    REL_PATH=${USER_DIR#$LOCAL_TMP/}; # Относительный путь (UserID)
    U_ID=$(basename "$USER_DIR");    # Идентификатор пользователя

    # Парсинг параметров манифеста
    SUB_TYPE=$(jq -r '.subscription_type' "$json_path" 2>/dev/null);
    CSV_NAME=$(jq -r '.file_name' "$json_path" 2>/dev/null);
    USER_EMAIL=$(jq -r '.user_email' "$json_path" 2>/dev/null);
    CSV_PATH="$USER_DIR/$CSV_NAME";

    # Проверка целостности данных
    if [ ! -f "$CSV_PATH" ]; then
        log_message "ERROR" "[$U_ID] CSV-файл $CSV_NAME не найден. Пропуск.";
        rm -rf "$USER_DIR";
        continue;
    fi;

    # 4. Логика выбора модели (согласно API predictions.py)
    case "$SUB_TYPE" in
        "FREE_TRIAL") 
            MODEL_PARAM="model1"; 
            SUB_PARAM="randomforest"; 
            ;;
        "STANDARD")   
            MODEL_PARAM="model1"; 
            SUB_PARAM="lgbm"; 
            ;;
        "PREMIUM")    
            MODEL_PARAM="model3"; 
            SUB_PARAM="xgboost"; # Игнорируется для model3, но требуется позиционно
            ;;
        *)
            log_message "ERROR" "[$U_ID] Неизвестная подписка: $SUB_TYPE. Пропуск.";
            rm -rf "$USER_DIR";
            continue;
            ;;
    esac;

    # 5. Выполнение обработки
    log_message "INFO" "[$U_ID] Запуск: $MODEL_PARAM ($SUB_PARAM) для $USER_EMAIL";
    
    cd "$PROJECT_DIR" || { log_message "ERROR" "Не удалось войти в $PROJECT_DIR"; continue; };
    source venv/bin/activate;
    
    OUTPUT_PDF="${U_ID}_result.pdf";

    # Запуск бэкенда
    python3 predictions.py \
        "$CSV_PATH" \
        "$USER_DIR/output.csv" \
        --model "$MODEL_PARAM" \
        --submodel "$SUB_PARAM" \
        --target "Protein_Number" \
        --pdf "$USER_DIR/$OUTPUT_PDF";
    
    STATUS=$?;
    deactivate;
    cd - > /dev/null;

    # 6. Обработка результата и Исключений
    if [ $STATUS -eq 0 ]; then
        log_message "INFO" "[$U_ID] Успех. Загрузка отчета и очистка S3.";
        
        # Загружаем PDF в S3
        mcli cp "$USER_DIR/$OUTPUT_PDF" "$S3_ALIAS/$BUCKET_NAME/$REL_PATH/";
        
        # Удаляем JSON и CSV из S3 (очередь очищена)
        mcli rm "$S3_ALIAS/$BUCKET_NAME/$REL_PATH/data_report.json";
        mcli rm "$S3_ALIAS/$BUCKET_NAME/$REL_PATH/data_report.csv";
    else
        # В случае падения бэкенда:
        log_message "ERROR" "[$U_ID] Бэкенд упал с кодом $STATUS. Исходники сохранены в S3.";
        # Исходники в S3 НЕ удаляем, чтобы можно было перезапустить после фикса.
    fi;

    # В ЛЮБОМ СЛУЧАЕ удаляем локальную копию данных, чтобы не забивать /tmp
    rm -rf "$USER_DIR";

done;

# 7. Финальная очистка временной директории
rm -rf "${LOCAL_TMP:?}"/*;
log_message "INFO" "--- Сессия завершена ---";