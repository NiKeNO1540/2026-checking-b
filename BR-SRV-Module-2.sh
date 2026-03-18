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
log_and_echo "║      ПРОВЕРКА КОНФИГУРАЦИИ BR-SRV (МОДУЛЬ 2)                 ║"
log_and_echo "║      Дата: $(date '+%Y-%m-%d %H:%M:%S')                            ║"
log_and_echo "╚══════════════════════════════════════════════════════════════╝"
log_and_echo ""

# ==================== КРИТЕРИЙ 12: ANSIBLE И NTP ====================
log_and_echo "┌──────────────────────────────────────────────────────────────┐"
log_and_echo "│ КРИТЕРИЙ 12: Проверка Ansible и синхронизации времени        │"
log_and_echo "│ Описание: Ansible должен успешно пинговать все узлы          │"
log_and_echo "│           Системное время должно быть синхронизировано       │"
log_and_echo "└──────────────────────────────────────────────────────────────┘"

execute_check "Ansible ping всех узлов" "ansible all -m ping"
execute_check "Синхронизация системного времени" "timedatectl | grep 'System clock synchronized: yes'"

# ==================== КРИТЕРИЙ 14: SAMBA ПОЛЬЗОВАТЕЛИ ====================
log_and_echo "┌──────────────────────────────────────────────────────────────┐"
log_and_echo "│ КРИТЕРИЙ 14: Проверка пользователей Samba (AD)               │"
log_and_echo "│ Описание: Пользователи должны быть импортированы в Samba     │"
log_and_echo "│           Группа HQ должна содержать пользователей           │"
log_and_echo "└──────────────────────────────────────────────────────────────┘"

execute_check "Наличие пользователя hquser в Samba" "samba-tool user list | grep hquser"
execute_check "Члены группы HQ в Samba" "samba-tool group listmembers hq"

# ==================== КРИТЕРИЙ 15: СЛУЖБА SAMBA ====================
log_and_echo "┌──────────────────────────────────────────────────────────────┐"
log_and_echo "│ КРИТЕРИЙ 15: Проверка службы контроллера домена Samba        │"
log_and_echo "│ Описание: Служба samba.service должна быть активна           │"
log_and_echo "└──────────────────────────────────────────────────────────────┘"

execute_check "Статус службы Samba" "systemctl status samba.service | grep 'Active: active'"

# ==================== КРИТЕРИЙ 16/18: ВЕБ-СЕРВИСЫ ====================
log_and_echo "┌──────────────────────────────────────────────────────────────┐"
log_and_echo "│ КРИТЕРИЙ 16/18(BR-SRV): Проверка веб-сервисов и прокси       │"
log_and_echo "│ Описание: Веб-сервисы должны быть доступны напрямую          │"
log_and_echo "│           и через прокси-сервер                              │"
log_and_echo "└──────────────────────────────────────────────────────────────┘"

# Проверка и установка curl
if ! command -v curl > /dev/null; then
    log_and_echo "Установка curl..."
    apt-get update -qq && apt-get install curl -y -qq
fi

execute_check "Веб-сервис на HQ-SRV с авторизацией (порт 8080)" "timeout 10 curl -u WEB:P@ssw0rd http://172.16.1.10:8080"
execute_check "Веб-сервис HQ-SRV через прокси (web.au-team.irpo)" "timeout 10 curl -u WEB:P@ssw0rd -s -f http://web.au-team.irpo"

# ==================== КРИТЕРИЙ 18: SSH И DOCKER ====================
log_and_echo "┌──────────────────────────────────────────────────────────────┐"
log_and_echo "│ КРИТЕРИЙ 18: Проверка SSH-подключения и Docker               │"
log_and_echo "│ Описание: SSH к HQ-SRV (172.16.1.10:2026) должен работать    │"
log_and_echo "│           Docker-контейнер testapp должен быть запущен       │"
log_and_echo "└──────────────────────────────────────────────────────────────┘"

# Проверка и установка sshpass
if ! command -v sshpass > /dev/null; then
    log_and_echo "Установка sshpass..."
    apt-get update -qq && apt-get install sshpass -y -qq
fi

execute_check "SSH подключение к HQ-SRV (порт 2026)" "sshpass -p 'P@ssw0rd' ssh -p 2026 -o ConnectTimeout=10 -o StrictHostKeyChecking=no sshuser@172.16.1.10 'echo \"SSH подключение успешно\"'"
execute_check "Docker-приложение testapp (Uvicorn)" "docker compose -f site.yml logs testapp | grep 'Uvicorn running'"

# ==================== ДОПОЛНИТЕЛЬНЫЕ ПРОВЕРКИ ====================
log_and_echo "┌──────────────────────────────────────────────────────────────┐"
log_and_echo "│ ДОПОЛНИТЕЛЬНО: Проверка инфраструктуры                       │"
log_and_echo "└──────────────────────────────────────────────────────────────┘"

# Проверка и установка nc
if ! command -v nc > /dev/null; then
    log_and_echo "Установка netcat..."
    apt-get update -qq && apt-get install netcat -y -qq
fi

execute_check "Доступность SSH-порта 2026 на HQ-SRV" "timeout 10 nc -z -w 5 172.16.1.10 2026 && echo 'Порт 2026 доступен'"
execute_check "Статус Docker контейнера testapp" "docker ps | grep testapp"
execute_check "Использование диска" "df -h / | tail -1"
execute_check "Доступная память" "free -h"

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
echo "  Критерий 12 (Ansible):      $(ansible all -m ping &>/dev/null && echo '✓ OK' || echo '✗ FAIL')"
echo "  Критерий 12 (NTP sync):     $(timedatectl | grep -q 'System clock synchronized: yes' && echo '✓ OK' || echo '✗ FAIL')"
echo "  Критерий 14 (Samba users):  $(samba-tool user list 2>/dev/null | grep -q hquser && echo '✓ OK' || echo '✗ FAIL')"
echo "  Критерий 15 (Samba AD):     $(systemctl is-active samba.service &>/dev/null && echo '✓ OK' || echo '✗ FAIL')"
echo "  Критерий 18 (Docker web):   $(timeout 5 curl -s http://docker.au-team.irpo &>/dev/null && echo '✓ OK' || echo '✗ FAIL')"
echo "  Критерий 18 (Docker):       $(docker ps 2>/dev/null | grep -q testapp && echo '✓ OK' || echo '✗ FAIL')"
echo ""

echo "Для просмотра полных результатов: cat $LOG_FILE"
