#!/usr/bin/env bash
# init.sh — подъём окружения «Сервис заметок» (Planner, сессия 0).
# Идемпотентный: проверяет инструменты, ставит зависимости, применяет миграции.
# Безопасен и на пустом репозитории (до создания server/ и web/ Tasker'ами),
# и после: пропускает шаги, для которых ещё нет package.json.
#
# Запуск (Linux/macOS/Git Bash):  bash init.sh
# На Windows без bash используйте:  powershell -File init.ps1
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

step() { printf '\n==> %s\n' "$*"; }
warn() { printf '    [skip] %s\n' "$*"; }
ok()   { printf '    [ok]   %s\n' "$*"; }

step "Проверка инструментов"
command -v node >/dev/null 2>&1 || { echo "ОШИБКА: node не найден. Установите Node.js >= 22."; exit 1; }
command -v npm  >/dev/null 2>&1 || { echo "ОШИБКА: npm не найден."; exit 1; }

NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]')"
if [ "$NODE_MAJOR" -lt 22 ]; then
  echo "ОШИБКА: нужен Node >= 22 (для node:sqlite). Сейчас: $(node -v)"
  exit 1
fi
ok "node $(node -v), npm $(npm -v)"

# Проверяем доступность встроенного node:sqlite
node -e 'require("node:sqlite");' >/dev/null 2>&1 \
  && ok "node:sqlite доступен" \
  || { echo "ОШИБКА: node:sqlite недоступен (нужен Node >= 22)."; exit 1; }

install_if_present() {
  local dir="$1"
  if [ -f "$dir/package.json" ]; then
    step "Установка зависимостей: $dir"
    ( cd "$dir" && npm install --no-audit --no-fund )
    ok "зависимости $dir установлены"
  else
    warn "$dir/package.json отсутствует — каркас ещё не создан (T-02/T-06); шаг пропущен"
  fi
}

install_if_present "server"
install_if_present "web"

if [ -f "server/package.json" ] && grep -q '"migrate"' server/package.json 2>/dev/null; then
  step "Применение миграций БД (server)"
  ( cd server && npm run migrate )
  ok "миграции применены"
else
  warn "скрипт migrate не найден — БД будет создана при первом старте/миграции (T-01)"
fi

step "Проверка сборки (если доступна)"
if [ -f "web/package.json" ] && grep -q '"build"' web/package.json 2>/dev/null; then
  ( cd web && npm run build )
  ok "web собран"
else
  warn "web/package.json без build — сборка не проверялась"
fi

step "Готово"
cat <<'EOF'

Окружение готово. Запуск в dev-режиме (два терминала):

  cd server && npm run dev      # бэкенд  http://localhost:3000
  cd web && npm run dev         # фронтенд http://localhost:5173  (proxy /api -> :3000)

E2E-смоук (после T-12):  node server/scripts/e2e-smoke.mjs
EOF
