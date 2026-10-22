#!/usr/bin/env bash
set -uo pipefail
PASS=0; FAIL=0
check() {
 local desc="$1" expected="$2" actual="$3"
 if [[ "$actual" == "$expected" ]]; then
 echo " [OK] $desc"; ((PASS++))
 else
 echo " [FAIL] $desc (ожидалось: '$expected', получено: '$actual')";
((FAIL++))
 fi
}
echo "Аудит конфигурации: $(hostname -f), $(date '+%Y-%m-%d %H:%M')"
echo "[1] Служба SSH"
check "Вход от имени root запрещён" "no" "$(sudo sshd -T | awk '/^permitrootlogin/{print $2}')"
check "Парольная аутентификация отключена" "no" "$(sudo sshd -T | awk '/^passwordauthentication/{print $2}')"

# TODO 1: проверьте, что значение параметра port отлично от 22
PORT_ACTUAL="$(sudo sshd -T | awk '/^port/{print $2}')"
if [[ "$PORT_ACTUAL" != "22" && -n "$PORT_ACTUAL" ]]; then
    echo " [OK] Порт SSH изменен (ожидалось: не 22, получено: '$PORT_ACTUAL')"; ((PASS++))
else
    echo " [FAIL] Порт SSH изменен (ожидалось: не 22, получено: '$PORT_ACTUAL')"; ((FAIL++))
fi

# TODO 2: проверьте, что значение параметра maxauthtries равно 3
check "Количество попыток авторизации равно 3" "3" "$(sudo sshd -T | awk '/^maxauthtries/{print $2}')"

echo "[2] Межсетевой экран"
check "Межсетевой экран активен" "active" "$(sudo ufw status | awk '/^Status:/{print $2}')"

# TODO 3: проверьте, что политика по умолчанию для входящего трафика равна deny
check "Политика по умолчанию для входящего трафика — deny" "deny" "$(sudo ufw status verbose | awk '/^Default:/{print $2}')"

echo "[3] Учётные записи"
awk -F: '$3>=1000 && $3<65534 {printf " %s (uid=%s)\n",$1,$3}' /etc/passwd
echo "Пройдено: $PASS, не пройдено: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1

echo "[4] Веб-сервер"

# а) Служба nginx активна
check "Служба nginx активна" "active" "$(systemctl is-active nginx)"

# б) Конфигурация nginx синтаксически корректна
if sudo nginx -t > /dev/null 2>&1; then
    echo " [OK]  Конфигурация nginx корректна"; ((PASS++))
else
    echo " [FAIL] Конфигурация nginx содержит ошибки"; ((FAIL++))
fi

# в) Сертификат истекает не ранее чем через 30 дней
# openssl -checkend 2592000 возвращает 0, если сертификат действителен более 30 дней (30*24*60*60)
if openssl x509 -checkend 2592000 -noout -in /etc/ssl/certs/devops.crt > /dev/null 2>&1; then
    echo " [OK]  Сертификат действителен более 30 дней"; ((PASS++))
else
    echo " [FAIL] Сертификат истекает менее чем через 30 дней или отсутствует"; ((FAIL++))
fi

# г) Нет файлов с правом записи для всех И права ключа 600
WWW_PERMS=$(find /var/www/devops-site -perm -o+w)
KEY_PERMS=$(sudo stat -c '%a' /etc/ssl/private/devops.key 2>/dev/null || echo "error")

if [[ -z "$WWW_PERMS" && "$KEY_PERMS" == "600" ]]; then
    echo " [OK]  Права на файлы ресурса и ключ безопасны"; ((PASS++))
else
    if [[ -n "$WWW_PERMS" ]]; then
        echo " [FAIL] Найдены файлы с правом записи для всех: $WWW_PERMS"; 
    fi
    if [[ "$KEY_PERMS" != "600" ]]; then
        echo " [FAIL] Права на ключ не равны 600 (текущие: $KEY_PERMS)"; 
    fi
    ((FAIL++))
fi