#!/usr/bin/env bash
# init.sh — подъём окружения «Пепельный Бастион» (Godot 4.x). Planner, сессия 0.
#
# Идемпотентно и безопасно на любом этапе:
#   * проверяет доступность рантайма Godot (GODOT_PATH / PATH / стандартные пути);
#   * создаёт каталог проекта game/, если его ещё нет;
#   * если game/project.godot существует — импортирует ресурсы и делает headless smoke-проверку;
#   * если есть тесты — прогоняет GUT headless.
# Отсутствие Godot — предупреждение, не ошибка (скрипт пригоден до установки рантайма).
#
# Запуск (Linux/macOS/Git Bash):  bash docs/init.sh
# Windows без bash:               powershell -ExecutionPolicy Bypass -File docs/init.ps1
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

GAME_DIR="game"
MIN_GODOT_MAJOR=4

step() { printf '\n==> %s\n' "$*"; }
ok()   { printf '    [ok]   %s\n' "$*"; }
warn() { printf '    [warn] %s\n' "$*"; }
info() { printf '    [info] %s\n' "$*"; }

find_godot() {
  if [ -n "${GODOT_PATH:-}" ] && [ -x "${GODOT_PATH}" ]; then
    printf '%s' "$GODOT_PATH"; return 0
  fi
  local c
  for c in godot4 godot godot4.4 godot4.3; do
    if command -v "$c" >/dev/null 2>&1; then command -v "$c"; return 0; fi
  done
  local p
  for p in \
    "/c/Program Files/Godot/Godot.exe" \
    "/c/Program Files (x86)/Godot/Godot.exe" \
    "$HOME/Godot/Godot.exe" \
    "/usr/local/bin/godot" \
    "/usr/bin/godot"; do
    if [ -x "$p" ]; then printf '%s' "$p"; return 0; fi
  done
  return 1
}

step "Проверка рантайма Godot (>= ${MIN_GODOT_MAJOR}.x)"
GODOT_BIN="$(find_godot || true)"
if [ -z "$GODOT_BIN" ]; then
  warn "Godot не найден. Установите Godot 4.4+ и задайте GODOT_PATH, либо добавьте в PATH."
  warn "Проверенные пути: \$GODOT_PATH, godot4/godot, 'C:\\Program Files\\Godot\\Godot.exe'."
  warn "Скрипт продолжит подготовку каталогов; импорт/тесты будут пропущены."
else
  VER="$("$GODOT_BIN" --version 2>/dev/null || echo "unknown")"
  MAJOR="${VER%%.*}"
  info "Godot: $VER ($GODOT_BIN)"
  if [ "$MAJOR" != "$MIN_GODOT_MAJOR" ] && [ "$MAJOR" -lt "$MIN_GODOT_MAJOR" ] 2>/dev/null; then
    warn "Ожидается Godot >= ${MIN_GODOT_MAJOR}.x, найден $VER."
  else
    ok "версия подходит"
  fi
fi

step "Подготовка каталога проекта"
if [ -d "$GAME_DIR" ]; then
  ok "$GAME_DIR/ уже существует"
else
  mkdir -p "$GAME_DIR"
  ok "создан $GAME_DIR/"
fi

if [ -f "$GAME_DIR/project.godot" ]; then
  ok "$GAME_DIR/project.godot найден"
  PROJECT_READY=1
else
  warn "$GAME_DIR/project.godot отсутствует — каркас проекта ещё не создан (задача T-01)"
  PROJECT_READY=0
fi

if [ -n "$GODOT_BIN" ] && [ "$PROJECT_READY" -eq 1 ]; then
  step "Импорт ресурсов Godot"
  "$GODOT_BIN" --headless --path "$GAME_DIR" --import
  ok "импорт завершён"

  step "Headless smoke-проверка (загрузка проекта)"
  "$GODOT_BIN" --headless --path "$GAME_DIR" --quit
  ok "проект загружается без ошибок"

  if [ -d "$GAME_DIR/tests" ] && [ -f "$GAME_DIR/addons/gut/gut_cmdln.gd" ]; then
    step "Прогон тестов (GUT, headless)"
    "$GODOT_BIN" --headless --path "$GAME_DIR" \
      -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
    ok "тесты выполнены"
  else
    warn "тесты GUT не найдены (game/tests или addons/gut) — шаг пропущен"
  fi
elif [ -n "$GODOT_BIN" ]; then
  warn "Импорт пропущен: нет $GAME_DIR/project.godot (сначала T-01)."
fi

step "Готово"
ok "Окружение подготовлено (ROOT: $ROOT)"
info "Следующие шаги: реализовать T-01 (каркас проекта), затем 'bash docs/init.sh' для импорта и тестов."
