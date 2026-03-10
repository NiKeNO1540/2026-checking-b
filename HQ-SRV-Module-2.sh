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
log_and_echo "║      ПРОВЕРКА КОНФИГУРАЦИИ HQ-SRV (МОДУЛЬ 2)                 ║"
log_and_echo "║      Дата: $(date '+%Y-%m-%d %H:%M:%S')                            ║"
log_and_echo "╚══════════════════════════════════════════════════════════════╝"
log_and_echo ""

# ==================== КРИТЕРИЙ 12: NTP ====================
log_and_echo "┌──────────────────────────────────────────────────────────────┐"
log_and_echo "│ КРИТЕРИЙ 12: Проверка синхронизации времени (NTP)            │"
log_and_echo "│ Описание: Системное время должно быть синхронизировано       │"
log_and_echo "│           с NTP-сервером                                     │"
log_and_echo "└──────────────────────────────────────────────────────────────┘"

execute_check "Синхронизация системного времени" "timedatectl | grep 'System clock synchronized: yes'"

# ==================== КРИТЕРИЙ 13: RAID И NFS ====================
log_and_echo "┌──────────────────────────────────────────────────────────────┐"
log_and_echo "│ КРИТЕРИЙ 13: Проверка RAID-массива и NFS-сервера             │"
log_and_echo "│ Описание: RAID-массив md0 должен существовать                │"
log_and_echo "│           NFS-директория /raid/nfs должна быть экспортирована│"
log_and_echo "└──────────────────────────────────────────────────────────────┘"

log_and_echo ""
log_and_echo "═══ Проверка RAID-массива ═══"
execute_check "Существование RAID-массива md0" "lsblk | grep md0"
execute_check "Тип файловой системы RAID (ext4)" "blkid /dev/md0p1 | grep 'TYPE=\"ext4\"'"
execute_check "Конфигурация mdadm (/dev/md0)" "cat /etc/mdadm.conf | grep '/dev/md0'"
execute_check "Состояние RAID-массива" "cat /proc/mdstat"

log_and_echo ""
log_and_echo "═══ Проверка NFS-сервера ═══"
execute_check "Файлы в NFS-директории" "ls /raid/nfs"
execute_check "NFS-экспорты (/raid/nfs)" "exportfs -v | grep '/raid/nfs'"
execute_check "Монтирование /raid" "df -h | grep /raid"
execute_check "Статус службы NFS" "systemctl status nfs-server | grep 'Active: active'"

# ==================== ДОПОЛНИТЕЛЬНЫЕ ПРОВЕРКИ ====================
log_and_echo "┌──────────────────────────────────────────────────────────────┐"
log_and_echo "│ ДОПОЛНИТЕЛЬНО: Проверка веб-сервиса и ресурсов               │"
log_and_echo "└──────────────────────────────────────────────────────────────┘"

# Проверка и установка curl
if ! command -v curl > /dev/null; then
    log_and_echo "Установка curl..."
    apt-get update -qq && apt-get install curl -y -qq
fi

execute_check "Доступность веб-сервиса (localhost)" "curl -s -f http://localhost > /dev/null"

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
echo "  Критерий 12 (NTP sync):     $(timedatectl | grep -q 'System clock synchronized: yes' && echo '✓ OK' || echo '✗ FAIL')"
echo "  Критерий 13 (RAID md0):     $(lsblk | grep -q md0 && echo '✓ OK' || echo '✗ FAIL')"
echo "  Критерий 13 (NFS export):   $(exportfs -v 2>/dev/null | grep -q '/raid/nfs' && echo '✓ OK' || echo '✗ FAIL')"
echo "  Критерий 13 (NFS service):  $(systemctl is-active nfs-server &>/dev/null && echo '✓ OK' || echo '✗ FAIL')"
echo ""

echo "Для просмотра полных результатов: cat $LOG_FILE"
