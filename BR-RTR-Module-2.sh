#!/bin/bash

# Файл для записи результатов
LOG_FILE="/var/log/system_check_m2.log"

# Путь к конфигурации iptables
IPTABLES_CONF="/etc/sysconfig/iptables"

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

# Функция проверки наличия строки в файле
check_iptables_rule() {
    local pattern="$1"
    local description="$2"
    
    if [ ! -f "$IPTABLES_CONF" ]; then
        log_and_echo "  ✗ Файл $IPTABLES_CONF не найден"
        return 1
    fi
    
    if grep -qF "$pattern" "$IPTABLES_CONF" 2>/dev/null; then
        log_and_echo "  ✓ $description"
        return 0
    else
        log_and_echo "  ✗ $description - НЕ НАЙДЕНО"
        return 1
    fi
}

# ============================================================================
# НАЧАЛО ПРОВЕРКИ
# ============================================================================

clear
log_and_echo "╔══════════════════════════════════════════════════════════════╗"
log_and_echo "║      ПРОВЕРКА КОНФИГУРАЦИИ BR-RTR (МОДУЛЬ 2)                 ║"
log_and_echo "║      Дата: $(date '+%Y-%m-%d %H:%M:%S')                            ║"
log_and_echo "╚══════════════════════════════════════════════════════════════╝"
log_and_echo ""

# ==================== КРИТЕРИЙ 16: ТРАНСЛЯЦИЯ ПОРТОВ (IPTABLES) ====================
log_and_echo "┌──────────────────────────────────────────────────────────────┐"
log_and_echo "│ КРИТЕРИЙ 16: Проверка трансляции портов (iptables)           │"
log_and_echo "│ Описание: Настроен DNAT для перенаправления трафика          │"
log_and_echo "│           на BR-SRV (192.168.3.10) для портов 8080 и 2026    │"
log_and_echo "└──────────────────────────────────────────────────────────────┘"

log_and_echo ""
log_and_echo "Файл: $IPTABLES_CONF"

if [ -f "$IPTABLES_CONF" ]; then
    log_and_echo "✓ Файл конфигурации существует"
    log_and_echo ""
    
    log_and_echo "═══ Правила FORWARD ═══"
    check_iptables_rule "-A FORWARD -d 192.168.3.10/32 -p tcp -m tcp --dport 8080 -j ACCEPT" "FORWARD разрешён для 192.168.3.10:8080"
    check_iptables_rule "-A FORWARD -d 192.168.3.10/32 -p tcp -m tcp --dport 2026 -j ACCEPT" "FORWARD разрешён для 192.168.3.10:2026"
    check_iptables_rule "-A FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT" "FORWARD RELATED,ESTABLISHED разрешён"
    
    log_and_echo ""
    log_and_echo "═══ Правила PREROUTING (DNAT) ═══"
    check_iptables_rule "-A PREROUTING -i enp7s1 -p tcp -m tcp --dport 8080 -j DNAT --to-destination 192.168.3.10:8080" "DNAT порт 8080 → 192.168.3.10:8080"
    check_iptables_rule "-A PREROUTING -i enp7s1 -p tcp -m tcp --dport 2026 -j DNAT --to-destination 192.168.3.10:2026" "DNAT порт 2026 → 192.168.3.10:2026"
else
    log_and_echo "✗ Файл $IPTABLES_CONF не найден"
fi
log_and_echo ""

# ==================== ДОПОЛНИТЕЛЬНАЯ ИНФОРМАЦИЯ ====================
log_and_echo "┌──────────────────────────────────────────────────────────────┐"
log_and_echo "│ ДОПОЛНИТЕЛЬНО: Статус служб и текущие правила               │"
log_and_echo "└──────────────────────────────────────────────────────────────┘"

execute_check "Статус службы iptables" "systemctl is-active iptables"

log_and_echo ""
log_and_echo "═══ Текущие правила iptables (NAT таблица) ═══"
log_and_echo "Команда: iptables -t nat -L -n -v"
iptables -t nat -L -n -v 2>&1 | tee -a "$LOG_FILE"
log_and_echo ""

log_and_echo "═══ Текущие правила iptables (FORWARD chain) ═══"
log_and_echo "Команда: iptables -L FORWARD -n -v"
iptables -L FORWARD -n -v 2>&1 | tee -a "$LOG_FILE"
log_and_echo ""

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
echo "  Критерий 16 (FORWARD 8080):   $(grep -qF 'FORWARD -d 192.168.3.10/32 -p tcp -m tcp --dport 8080 -j ACCEPT' $IPTABLES_CONF 2>/dev/null && echo '✓ OK' || echo '✗ FAIL')"
echo "  Критерий 16 (FORWARD 2026):   $(grep -qF 'FORWARD -d 192.168.3.10/32 -p tcp -m tcp --dport 2026 -j ACCEPT' $IPTABLES_CONF 2>/dev/null && echo '✓ OK' || echo '✗ FAIL')"
echo "  Критерий 16 (FORWARD STATE):  $(grep -qF 'FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT' $IPTABLES_CONF 2>/dev/null && echo '✓ OK' || echo '✗ FAIL')"
echo "  Критерий 16 (DNAT 8080):      $(grep -qF 'PREROUTING -i enp7s1 -p tcp -m tcp --dport 8080 -j DNAT --to-destination 192.168.3.10:8080' $IPTABLES_CONF 2>/dev/null && echo '✓ OK' || echo '✗ FAIL')"
echo "  Критерий 16 (DNAT 2026):      $(grep -qF 'PREROUTING -i enp7s1 -p tcp -m tcp --dport 2026 -j DNAT --to-destination 192.168.3.10:2026' $IPTABLES_CONF 2>/dev/null && echo '✓ OK' || echo '✗ FAIL')"
echo ""

echo "Для просмотра полных результатов: cat $LOG_FILE"
