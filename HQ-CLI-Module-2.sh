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
log_and_echo "║      ПРОВЕРКА КОНФИГУРАЦИИ HQ-CLI (МОДУЛЬ 2)                 ║"
log_and_echo "║      Дата: $(date '+%Y-%m-%d %H:%M:%S')                            ║"
log_and_echo "╚══════════════════════════════════════════════════════════════╝"
log_and_echo ""

# ==================== КРИТЕРИЙ 12: YANDEX BROWSER И NTP ====================
log_and_echo "┌──────────────────────────────────────────────────────────────┐"
log_and_echo "│ КРИТЕРИЙ 12: Проверка Yandex Browser и NTP                   │"
log_and_echo "│ Описание: Yandex Browser должен быть установлен              │"
log_and_echo "│           Системное время должно быть синхронизировано       │"
log_and_echo "└──────────────────────────────────────────────────────────────┘"

execute_check "Установлен Yandex Browser" "command -v yandex-browser-stable"
execute_check "Синхронизация системного времени (NTP)" "timedatectl | grep 'System clock synchronized: yes'"

# ==================== КРИТЕРИЙ 14: ДОМЕННЫЕ ПРАВА ====================
log_and_echo "┌──────────────────────────────────────────────────────────────┐"
log_and_echo "│ КРИТЕРИЙ 14: Проверка прав доменных пользователей            │"
log_and_echo "│ Описание: Пользователь hquser1 должен иметь право            │"
log_and_echo "│           выполнять команду /usr/bin/id через sudo           │"
log_and_echo "└──────────────────────────────────────────────────────────────┘"

execute_check "Права sudo для hquser1 (команда id)" "sudo -l -U hquser1 | grep '/usr/bin/id'"

# ==================== КРИТЕРИЙ 15: KERBEROS АУТЕНТИФИКАЦИЯ ====================
log_and_echo "┌──────────────────────────────────────────────────────────────┐"
log_and_echo "│ КРИТЕРИЙ 15: Проверка Kerberos и членства в домене           │"
log_and_echo "│ Описание: Машина должна быть в домене AU-TEAM.IRPO           │"
log_and_echo "│           Должны быть получены билеты Kerberos               │"
log_and_echo "└──────────────────────────────────────────────────────────────┘"

execute_check "Пользователь administrator существует" "id administrator"

# Проверка и получение билета Kerberos
log_and_echo ""
log_and_echo "═══ Проверка билетов Kerberos ═══"

if ! klist 2>/dev/null | grep -q "administrator@AU-TEAM.IRPO"; then
    log_and_echo "Получение билета Kerberos для administrator..."
    echo "P@ssw0rd" | kinit administrator 2>/dev/null
fi

execute_check "Билеты Kerberos" "klist"

# ==================== КРИТЕРИЙ 16/18: ВЕБ-СЕРВИСЫ ====================
log_and_echo "┌──────────────────────────────────────────────────────────────┐"
log_and_echo "│ КРИТЕРИЙ 16/18: Проверка веб-сервисов и прокси               │"
log_and_echo "│ Описание: Веб-сервисы должны быть доступны напрямую          │"
log_and_echo "│           и через прокси-сервер                              │"
log_and_echo "└──────────────────────────────────────────────────────────────┘"

# Проверка и установка curl
if ! command -v curl > /dev/null; then
    log_and_echo "Установка curl..."
    apt-get update -qq && apt-get install curl -y -qq
fi

execute_check "Веб-сервис на BR-SRV (порт 8080)" "timeout 10 curl -I http://172.16.2.10:8080 | grep -i uvicorn"
execute_check "Веб-сервис на HQ-SRV с авторизацией (порт 8080)" "timeout 10 curl -u WEB:P@ssw0rd http://172.16.1.10:8080"
execute_check "Веб-сервис HQ-SRV через прокси (web.au-team.irpo)" "timeout 10 curl -u WEB:P@ssw0rd -s -f http://web.au-team.irpo"
execute_check "Веб-сервис BR-SRV через прокси (docker.au-team.irpo)" "timeout 10 curl http://docker.au-team.irpo"

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
echo "  Критерий 12 (Yandex):       $(command -v yandex-browser-stable &>/dev/null && echo '✓ OK' || echo '✗ FAIL')"
echo "  Критерий 12 (NTP sync):     $(timedatectl | grep -q 'System clock synchronized: yes' && echo '✓ OK' || echo '✗ FAIL')"
echo "  Критерий 14 (sudo hquser1): $(sudo -l -U hquser1 2>/dev/null | grep -q '/usr/bin/id' && echo '✓ OK' || echo '✗ FAIL')"
echo "  Критерий 15 (Kerberos):     $(klist 2>/dev/null | grep -q 'AU-TEAM.IRPO' && echo '✓ OK' || echo '✗ FAIL')"
echo "  Критерий 16 (Прокси web):   $(timeout 5 curl -s -f http://web.au-team.irpo &>/dev/null && echo '✓ OK' || echo '✗ FAIL')"
echo "  Критерий 18 (Docker web):   $(timeout 5 curl -s http://docker.au-team.irpo &>/dev/null && echo '✓ OK' || echo '✗ FAIL')"
echo ""

echo "Для просмотра полных результатов: cat $LOG_FILE"
