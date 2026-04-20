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

# PROJECT_DIR должен быть объявлен до LOG_FILE!
PROJECT_DIR="/home/minio/Omnivis";
LOG_FILE="$PROJECT_DIR/Omnicare.log";
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

# 3. Основной цикл
find "$LOCAL_TMP" -mindepth 2 -maxdepth 2 -type f -name "data_report.json" | while read -r json_path; do
    
    USER_DIR=$(dirname "$json_path");
    REL_PATH=${USER_DIR#$LOCAL_TMP/}; 
    U_ID=$(basename "$USER_DIR");    

    # Парсинг параметров
    SUB_TYPE=$(jq -r '.subscription_type' "$json_path" 2>/dev/null);
    CSV_NAME=$(jq -r '.file_name' "$json_path" 2>/dev/null);
    USER_EMAIL=$(jq -r '.user_email' "$json_path" 2>/dev/null);
    CSV_PATH="$USER_DIR/$CSV_NAME";

    if [ ! -f "$CSV_PATH" ]; then
        log_message "ERROR" "[$U_ID] CSV-файл $CSV_NAME не найден. Пропуск.";
        rm -rf "$USER_DIR";
        continue;
    fi;

    # 4. Логика выбора модели (с учетом регистра для predictions.py)
    case "$SUB_TYPE" in
        "FREE_TRIAL") 
            MODEL_PARAM="model1"; 
            SUB_PARAM="randomforest"; # Если Python хочет RandomForest — поправьте здесь
            ;;
        "STANDARD")   
            MODEL_PARAM="model1"; 
            SUB_PARAM="lgbm"; 
            ;;
        "PREMIUM")    
            MODEL_PARAM="model3"; 
            SUB_PARAM="xgboost"; 
            ;;
        *)
            log_message 

"ERROR" "[$U_ID] Неизвестная подписка: $SUB_TYPE.";
            rm -rf "$USER_DIR";
            continue;
            ;;
    esac;

    # 5. Выполнение обработки
    log_message "INFO" "[$U_ID] Запуск: $MODEL_PARAM ($SUB_PARAM)";
    
    cd "$PROJECT_DIR" || { log_message "ERROR" "Не удалось войти в $PROJECT_DIR"; continue; };
    [ -f "venv/bin/activate" ] && source venv/bin/activate;
    
    OUTPUT_PDF="${U_ID}_result.pdf";

    python3 predictions.py \
        "$CSV_PATH" \
        "$USER_DIR/output.csv" \
        --model "$MODEL_PARAM" \
        --submodel "$SUB_PARAM" \
        --target "Protein_Number" \
        --pdf "$USER_DIR/$OUTPUT_PDF";
    
    STATUS=$?;
    [ -d "venv" ] && deactivate;
    cd - > /dev/null;

    # 6. Обработка результата (КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ)
    # Удаляем из S3 только если Python вернул 0 И PDF реально создался
    if [ $STATUS -eq 0 ] && [ -f "$USER_DIR/$OUTPUT_PDF" ]; then
        log_message "INFO" "[$U_ID] Успех. Загрузка отчета и очистка S3.";
        mcli cp "$USER_DIR/$OUTPUT_PDF" "$S3_ALIAS/$BUCKET_NAME/$REL_PATH/";
        mcli rm "$S3_ALIAS/$BUCKET_NAME/$REL_PATH/data_report.json";
        mcli rm "$S3_ALIAS/$BUCKET_NAME/$REL_PATH/data_report.csv";
    else
        log_message "ERROR" "[$U_ID] Сбой обработки (Status: $STATUS) или PDF не найден. Исходники сохранены в S3.";
    fi;

    rm -rf "$USER_DIR";
done;

# 7. Финальная очистка
rm -rf "${LOCAL_TMP:?}"/*;
log_message "INFO" "--- Сессия завершена ---";