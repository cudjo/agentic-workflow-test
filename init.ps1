# init.ps1 — bootstrap environment for "Notes Service" (Planner, session 0).
# Windows variant of init.sh (PowerShell). Idempotent and safe on an empty repo.
# Run:  powershell -ExecutionPolicy Bypass -File init.ps1

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

function Step($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Warn($m) { Write-Host "    [skip] $m" -ForegroundColor Yellow }
function Ok($m)   { Write-Host "    [ok]   $m" -ForegroundColor Green }

Step "Tool check"
$node = Get-Command node -ErrorAction SilentlyContinue
$npm  = Get-Command npm  -ErrorAction SilentlyContinue
if (-not $node) { Write-Error "ERROR: node not found. Install Node.js >= 22."; exit 1 }
if (-not $npm)  { Write-Error "ERROR: npm not found."; exit 1 }

$nodeVer = (node -v).TrimStart('v')
$major = [int]($nodeVer.Split('.')[0])
if ($major -lt 22) { Write-Error "ERROR: Node >= 22 required (node:sqlite). Current: $(node -v)"; exit 1 }
Ok "node $(node -v), npm $(npm -v)"

node -e "require('node:sqlite');" 2>$null
if ($LASTEXITCODE -eq 0) { Ok "node:sqlite available" }
else { Write-Error "ERROR: node:sqlite unavailable (Node >= 22 required)."; exit 1 }

function Install-IfPresent($dir) {
  if (Test-Path "$dir/package.json") {
    Step "Install dependencies: $dir"
    Push-Location $dir
    npm install --no-audit --no-fund
    Pop-Location
    Ok "dependencies installed: $dir"
  } else {
    Warn "$dir/package.json missing - scaffold not created yet (T-02/T-06); step skipped"
  }
}

Install-IfPresent "server"
Install-IfPresent "web"

$hasMigrate = (Test-Path "server/package.json") -and (Select-String -Path "server/package.json" -Pattern '"migrate"' -Quiet)
if ($hasMigrate) {
  Step "Apply DB migrations (server)"
  Push-Location server; npm run migrate; Pop-Location
  Ok "migrations applied"
} else {
  Warn "migrate script not found - DB created on first run/migration (T-01)"
}

Step "Build check (if available)"
$hasBuild = (Test-Path "web/package.json") -and (Select-String -Path "web/package.json" -Pattern '"build"' -Quiet)
if ($hasBuild) {
  Push-Location web; npm run build; Pop-Location
  Ok "web built"
} else {
  Warn "web/package.json without build - build not verified"
}

Step "Done"
Write-Host ""
Write-Host "Environment ready. Dev run (two terminals):"
Write-Host "  cd server; npm run dev      # backend  http://localhost:3000"
Write-Host "  cd web; npm run dev         # frontend http://localhost:5173  (proxy /api -> :3000)"
Write-Host "E2E smoke (after T-12):  node server/scripts/e2e-smoke.mjs"
