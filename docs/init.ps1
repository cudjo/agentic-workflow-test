# init.ps1 — подъём окружения «Пепельный Бастион» (Godot 4.x). Planner, сессия 0.
# Зеркало docs/init.sh для Windows (PowerShell).
#
# Идемпотентно: проверяет рантайм Godot (GODOT_PATH / PATH / стандартные пути),
# создаёт каталог game/, при наличии project.godot импортирует ресурсы, делает headless
# smoke-проверку и прогоняет GUT-тесты. Отсутствие Godot — предупреждение, не ошибка.
#
# Запуск: powershell -ExecutionPolicy Bypass -File docs/init.ps1
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = (Resolve-Path (Join-Path $ScriptDir '..')).Path
Set-Location $Root

$GameDir = 'game'
$MinGodotMajor = 4

function Step($m) { Write-Host ''; Write-Host "==> $m" }
function Ok($m)   { Write-Host "    [ok]   $m" }
function Warn($m) { Write-Host "    [warn] $m" }
function Info($m) { Write-Host "    [info] $m" }

function Find-Godot {
    if ($env:GODOT_PATH -and (Test-Path $env:GODOT_PATH)) { return $env:GODOT_PATH }
    foreach ($c in @('godot4', 'godot', 'godot4.4')) {
        $cmd = Get-Command $c -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
    }
    $candidates = @(
        'C:\Program Files\Godot\Godot.exe',
        'C:\Program Files (x86)\Godot\Godot.exe',
        (Join-Path $env:LOCALAPPDATA 'Godot\Godot.exe'),
        (Join-Path $env:USERPROFILE 'Godot\Godot.exe')
    )
    foreach ($p in $candidates) { if (Test-Path $p) { return $p } }
    return $null
}

Step "Проверка рантайма Godot (>= $MinGodotMajor.x)"
$GodotBin = Find-Godot
if (-not $GodotBin) {
    Warn "Godot не найден. Установите Godot 4.4+ и задайте GODOT_PATH, либо добавьте в PATH."
    Warn "Проверенные пути: GODOT_PATH, godot4/godot, 'C:\Program Files\Godot\Godot.exe'."
    Warn "Скрипт продолжит подготовку каталогов; импорт/тесты будут пропущены."
} else {
    $ver = (& $GodotBin --version) 2>$null
    Info "Godot: $ver ($GodotBin)"
    $major = 0
    if ($ver -match '^(\d+)') { $major = [int]$Matches[1] }
    if ($major -lt $MinGodotMajor) {
        Warn "Ожидается Godot >= $MinGodotMajor.x, найден $ver."
    } else {
        Ok "версия подходит"
    }
}

Step "Подготовка каталога проекта"
if (Test-Path $GameDir) {
    Ok "$GameDir/ уже существует"
} else {
    New-Item -ItemType Directory -Path $GameDir | Out-Null
    Ok "создан $GameDir/"
}

$projectFile = Join-Path $GameDir 'project.godot'
$projectReady = Test-Path $projectFile
if ($projectReady) {
    Ok "$GameDir/project.godot найден"
} else {
    Warn "$GameDir/project.godot отсутствует — каркас проекта ещё не создан (задача T-01)"
}

if ($GodotBin -and $projectReady) {
    Step "Импорт ресурсов Godot"
    & $GodotBin --headless --path $GameDir --import
    if ($LASTEXITCODE -ne 0) { throw "Импорт завершился с кодом $LASTEXITCODE" }
    Ok "импорт завершён"

    Step "Headless smoke-проверка (загрузка проекта)"
    & $GodotBin --headless --path $GameDir --quit
    if ($LASTEXITCODE -ne 0) { throw "Smoke-проверка завершилась с кодом $LASTEXITCODE" }
    Ok "проект загружается без ошибок"

    $gutCmd = Join-Path $GameDir 'addons/gut/gut_cmdln.gd'
    if ((Test-Path (Join-Path $GameDir 'tests')) -and (Test-Path $gutCmd)) {
        Step "Прогон тестов (GUT, headless)"
        & $GodotBin --headless --path $GameDir -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
        if ($LASTEXITCODE -ne 0) { throw "Тесты завершились с кодом $LASTEXITCODE" }
        Ok "тесты выполнены"
    } else {
        Warn "тесты GUT не найдены (game/tests или addons/gut) — шаг пропущен"
    }
} elseif ($GodotBin) {
    Warn "Импорт пропущен: нет $GameDir/project.godot (сначала T-01)."
}

Step "Готово"
Ok "Окружение подготовлено (ROOT: $Root)"
Info "Следующие шаги: реализовать T-01 (каркас проекта), затем 'powershell -File docs/init.ps1' для импорта и тестов."
