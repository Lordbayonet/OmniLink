#!/bin/bash
##############################################################
## Script for link backend and frontend Omnicare diagnostic ##
## Author Vladimir Shumeyko(from.fmp@gmail.com)             ##
##############################################################
# --- Настройки ---
TARGET_DIR="/home/lordbayonet/storage"
LOG_FILE="./processing_$(date '+%Y%m%d').log"

# Константы времени
NOW=$(date +%s)
SECONDS_IN_24H=86400
ALLOWED_DRIFT=300 # Запас 5 минут на случай рассинхрона часов

# --- Функция логирования ---
log_message() {
    local TYPE="$1"
    local MESSAGE="$2"
    local TIMESTAMP=$(date "+%Y%m%d-%H%M%S")
    echo "[$TIMESTAMP] [$TYPE] $MESSAGE" >> "$LOG_FILE"
    # Вывод в консоль для мониторинга (кроме обычных INFO)
    [[ "$TYPE" != "INFO" ]] && echo "[$TYPE] $MESSAGE"
}

# --- Проверки перед стартом ---
if ! command -v jq &> /dev/null; then
    log_message "ERROR" "Утилита 'jq' не найдена. Установите: sudo apt install jq"
    exit 1
fi

if [ ! -d "$STORAGE_ROOT" ]; then
    log_message "ERROR" "Корневая директория хранилища не найдена: $STORAGE_ROOT"
    exit 1
fi

log_message "INFO" "=== Старт сессии обработки (UTC: $(date -u)) ==="

# --- Основной цикл ---
# Ищем JSON-файлы в папках пользователей (уровень вложенности 2)
# Первичный фильтр по ФС: файлы изменены за последние 24 часа
find "$STORAGE_ROOT" -mindepth 2 -maxdepth 2 -type f -name "*.json" -mmin -1440 -print0 | while IFS= read -r -d '' json_path; do
    
    USER_DIR=$(dirname "$json_path")
    JSON_FILE=$(basename "$json_path")

    # 1. Парсинг данных манифеста
    UPLOAD_TS=$(jq -r '.upload_timestamp' "$json_path" 2>/dev/null)
    USER_EMAIL=$(jq -r '.user_email' "$json_path" 2>/dev/null)
    SUB_TYPE=$(jq -r '.subscription_type' "$json_path" 2>/dev/null)
    CSV_NAME=$(jq -r '.file_name' "$json_path" 2>/dev/null)
    U_ID=$(jq -r '.user_id' "$json_path" 2>/dev/null)

    # 2. Вторичный фильтр: Проверка Unix Timestamp из манифеста
    if [[ ! "$UPLOAD_TS" =~ ^[0-9]+$ ]]; then
        log_message "ERROR" "Ошибка формата timestamp в $JSON_FILE"
        continue
    fi

    DIFF=$(( NOW - UPLOAD_TS ))

    if [ "$DIFF" -gt "$SECONDS_IN_24H" ] || [ "$DIFF" -lt "-$ALLOWED_DRIFT" ]; then
        log_message "NOTICE" "Файл $JSON_FILE пропущен: время в манифесте ($UPLOAD_TS) вне окна 24ч (DIFF: $DIFF сек)"
        continue
    fi

    # 3. Валидация наличия CSV файла
    CSV_PATH="$USER_DIR/$CSV_NAME"
    if [ ! -f "$CSV_PATH" ]; then
        log_message "ERROR" "CSV файл не найден: $CSV_NAME в папке $USER_DIR"
        continue
    fi

    # 4. Логика выбора модели на основе подписки
    case "$SUB_TYPE" in
        "FREE_TRIAL")
            MODEL="RandomForest"
            ;;
        "STANDARD")
            MODEL="LGBM"
            ;;
        "PREMIUM")
            MODEL="Model_3"
            ;;
        *)
            log_message "ERROR" "Неизвестный тип подписки [$SUB_TYPE] для пользователя $USER_EMAIL"
            continue
            ;;
    esac

    # 5. Выполнение обработки
    log_message "INFO" "Обработка: User ID [$U_ID] | Model [$MODEL] | File [$CSV_NAME]"
    
    # Пример вызова модели:
    # python3 run_inference.py --model "$MODEL" --data "$CSV_PATH" --email "$USER_EMAIL"
    
    if [ $? -eq 0 ]; then
        log_message "INFO" "Успешно обработано: $JSON_FILE"
    else
        log_message "ERROR" "Сбой при выполнении модели $MODEL для $CSV_NAME"
    fi

done

log_message "INFO" "=== Сессия завершена ==="