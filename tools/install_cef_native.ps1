param([Parameter(Mandatory=$true)][string]$GameDirectory)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$game = (Resolve-Path -LiteralPath $GameDirectory).Path
if (-not (Test-Path -LiteralPath (Join-Path $game 'gta_sa.exe'))) { throw 'gta_sa.exe not found' }
if (Get-Process gta_sa -ErrorAction SilentlyContinue) { throw 'Close GTA before replacing the bridge and script.' }
$bridgeDir = Join-Path $game 'moonloader\X-TOOL\cef-bridge'
$transport = Get-Content -LiteralPath (Join-Path $bridgeDir 'transport.json') -Raw | ConvertFrom-Json
if ($transport.token -cnotmatch '^[0-9a-f]{48}$') { throw 'Existing CEF adapter token is missing or invalid.' }
if ($transport.port -and $transport.port -ne 18766) { throw 'Game adapter expects port 18766.' }
$pairs = @(
 @{ Source=(Join-Path $repo 'artifacts\cef-native\XToolsBridge.asi'); Target=(Join-Path $game 'XToolsBridge.asi') },
 @{ Source=(Join-Path $repo 'artifacts\cef-family-dev\X-TOOL.lua'); Target=(Join-Path $game 'moonloader\X-TOOL.lua') }
)
foreach ($pair in $pairs) { if (-not (Test-Path -LiteralPath $pair.Source)) { throw "Missing build: $($pair.Source)" } }
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$changed = @()
try {
 foreach ($pair in $pairs) {
  $backup = $null
  if (Test-Path -LiteralPath $pair.Target) { $backup = "$($pair.Target).before-native-$stamp.bak"; Copy-Item -LiteralPath $pair.Target -Destination $backup }
  $changed += @{Target=$pair.Target;Backup=$backup}
  Copy-Item -LiteralPath $pair.Source -Destination $pair.Target -Force
  if ((Get-FileHash -LiteralPath $pair.Source).Hash -ne (Get-FileHash -LiteralPath $pair.Target).Hash) { throw 'Installed hash mismatch' }
 }
 # Disable only the retired helper launcher configuration; preserve it for rollback.
 $old = Join-Path $bridgeDir 'launcher.json'
 if (Test-Path -LiteralPath $old) { Move-Item -LiteralPath $old -Destination "$old.before-native-$stamp.bak" }
} catch {
 foreach ($item in $changed) {
  if ($item.Backup) { Copy-Item -LiteralPath $item.Backup -Destination $item.Target -Force }
  else { Remove-Item -LiteralPath $item.Target -Force }
 }
 throw
}
Write-Output "Native CEF bridge installed in $game; hashes verified; backups: before-native-$stamp.bak"
