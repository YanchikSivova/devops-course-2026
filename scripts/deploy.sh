#!/usr/bin/env bash
# Доставка статического ресурса на devops-vm
# Использование: scripts/deploy.sh [--dry-run]

set -euo pipefail

REMOTE="devops"
REMOTE_DIR="/var/www/devops-site"
SITE_URL="https://devops.local"
CA_CERT="${HOME}/devops.crt"
LOCAL_DIR="$(git rev-parse --show-toplevel)/site/"

# 1. Разбор аргумента --dry-run
DRY_RUN=0
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=1
fi

# 2. Проверки по требованиям 4 и 5 (на хосте)
# Проверка наличия файла index.html (Требование 4)
if [[ ! -f "${LOCAL_DIR}index.html" ]]; then
    echo "Ошибка: файл site/index.html отсутствует!" >&2
    exit 1
fi

# Проверка незафиксированных изменений (Требование 5)
if [[ -n "$(git status --porcelain)" ]]; then
    echo "Ошибка: в репозитории есть незафиксированные изменения. Закоммитьте их перед деплоем." >&2
    exit 1
fi

# 3. Синхронизация каталога (Требования 3 и 8)
# -e "ssh -o BatchMode=yes" запрещает интерактивный ввод пароля (Требование 9)
RSYNC_CMD=(rsync -avz --delete --chmod=D755,F644 -e "ssh -o BatchMode=yes -o ConnectTimeout=5")

if [[ "${DRY_RUN}" -eq 1 ]]; then
    "${RSYNC_CMD[@]}" --dry-run "${LOCAL_DIR}" "${REMOTE}:${REMOTE_DIR}/"
    echo "Dry-run успешно завершен. Изменения не вносились."
    exit 0
fi

# Выполнение реальной синхронизации
"${RSYNC_CMD[@]}" "${LOCAL_DIR}" "${REMOTE}:${REMOTE_DIR}/"

# 5. Проверка доступности ресурса (Требование 6)
# curl -f заставляет curl вернуть ошибку (код 22) при HTTP-статусах 4xx и 5xx
if ! curl -fsS --cacert "${CA_CERT}" "${SITE_URL}" > /dev/null; then
    echo "Ошибка: ресурс ${SITE_URL} недоступен после деплоя!" >&2
    exit 1
fi

# 7. Вывод короткого хеша коммита (Требование 7)
SHORT_HASH=$(git rev-parse --short HEAD)
echo "Деплой успешно завершен. Доставлен коммит: ${SHORT_HASH}"
exit 0
