#!/bin/bash

# Файл для записи результатов
LOG_FILE="/var/log/system_check_m2.log"

# Очистка лог-файла
> "$LOG_FILE"

# Функция для логирования и вывода
log_and_echo() {
    echo "$1"
    echo "$1" >> "$LOG_FILE"
}

# Функция выполнения проверки
execute_check() {
    local description="$1"
    local command="$2"
    
    log_and_echo "Проверка: $description"
    log_and_echo "Команда: $command"
    
    local output
    output=$(eval "$command" 2>&1)
    local exit_code=$?
    
    echo "$output" >> "$LOG_FILE"
    echo "$output"
    
    if [ $exit_code -eq 0 ]; then
        log_and_echo "✓ УСПЕХ"
    else
        log_and_echo "✗ ОШИБКА (код: $exit_code)"
    fi
    
    log_and_echo ""
    return $exit_code
}

# ============================================================================
# НАЧАЛО ПРОВЕРКИ
# ============================================================================

clear
log_and_echo "╔══════════════════════════════════════════════════════════════╗"
log_and_echo "║      ПРОВЕРКА КОНФИГУРАЦИИ HQ-RTR (МОДУЛЬ 2)                 ║"
log_and_echo "║      Дата: $(date '+%Y-%m-%d %H:%M:%S')                               ║"
log_and_echo "╚══════════════════════════════════════════════════════════════╝"
log_and_echo ""

# ==================== КРИТЕРИЙ 12: NTP И ВЕБ-СЕРВИСЫ ====================
log_and_echo "┌──────────────────────────────────────────────────────────────┐"
log_and_echo "│ КРИТЕРИЙ 12: Проверка NTP-сервера и веб-сервисов             │"
log_and_echo "│ Описание: NTP-сервер должен синхронизировать время           │"
log_and_echo "│           с клиентами HQ-RTR (172.16.1.10) и BR-RTR          │"
log_and_echo "│           (172.16.2.10). Веб-сервисы должны быть доступны.   │"
log_and_echo "└──────────────────────────────────────────────────────────────┘"

log_and_echo ""
log_and_echo "═══ Проверка NTP-клиентов (chrony) ═══"
execute_check "NTP-клиенты HQ-RTR и BR-RTR" "chronyc clients | grep -E '172.16.1.10|172.16.2.10'"

log_and_echo ""
log_and_echo "═══ Проверка доступности веб-сервисов ═══"

# Проверка и установка curl
if ! command -v curl > /dev/null; then
    log_and_echo "Установка curl..."
    apt-get update -qq && apt-get install curl -y -qq
fi

execute_check "Веб-сервис на HQ-SRV (http://172.16.1.1)" "timeout 10 curl -I http://172.16.1.1"
execute_check "Веб-сервис на BR-SRV (http://172.16.2.1)" "timeout 10 curl -I http://172.16.2.1"

# ==================== ДОПОЛНИТЕЛЬНАЯ ИНФОРМАЦИЯ ====================
log_and_echo "┌──────────────────────────────────────────────────────────────┐"
log_and_echo "│ ДОПОЛНИТЕЛЬНО: Статус служб                                  │"
log_and_echo "└──────────────────────────────────────────────────────────────┘"

execute_check "Статус службы chronyd" "systemctl is-active chronyd"
execute_check "Список NTP-источников" "chronyc sources"

# ==================== ИТОГИ ====================
log_and_echo ""
log_and_echo "╔══════════════════════════════════════════════════════════════╗"
log_and_echo "║                    ПРОВЕРКА ЗАВЕРШЕНА                        ║"
log_and_echo "║         Результаты сохранены в: $LOG_FILE          ║"
log_and_echo "╚══════════════════════════════════════════════════════════════╝"

echo ""
echo "┌──────────────────────────────────────────────────────────────┐"
echo "│                    СВОДКА РЕЗУЛЬТАТОВ                        │"
echo "└──────────────────────────────────────────────────────────────┘"
echo ""

success_count=$(grep -c "✓" "$LOG_FILE")
fail_count=$(grep -c "✗" "$LOG_FILE")

echo "  ✓ Успешных проверок:    $success_count"
echo "  ✗ Неуспешных проверок:  $fail_count"
echo ""

echo "┌──────────────────────────────────────────────────────────────┐"
echo "│                  СТАТУС ПО КРИТЕРИЯМ                         │"
echo "└──────────────────────────────────────────────────────────────┘"
echo ""
echo "  Критерий 12 (NTP):          $(chronyc clients 2>/dev/null | grep -qE '172.16.1.10|172.16.2.10' && echo '✓ OK' || echo '✗ FAIL')"
echo "  Критерий 12 (Web HQ-SRV):   $(timeout 5 curl -s -I http://172.16.1.1 &>/dev/null && echo '✓ OK' || echo '✗ FAIL')"
echo "  Критерий 12 (Web BR-SRV):   $(timeout 5 curl -s -I http://172.16.2.1 &>/dev/null && echo '✓ OK' || echo '✗ FAIL')"
echo ""

echo "Для просмотра полных результатов: cat $LOG_FILE"
