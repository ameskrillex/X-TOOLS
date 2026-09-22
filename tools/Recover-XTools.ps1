param([string]$Moonloader = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Battlefield 4\Advance Games\moonloader'))
$ErrorActionPreference = 'Stop'
if (Get-Process gta_sa -ErrorAction SilentlyContinue) { throw 'Close GTA before recovery.' }
$root = (Resolve-Path -LiteralPath $Moonloader).Path
$target = Join-Path $root 'X-TOOL.lua'
if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { throw 'X-TOOL.lua was not found.' }
$header = Get-Content -LiteralPath $target -TotalCount 1
if ($header -ne '-- CasualTool release: 3.5.203') { throw 'Recovery is only for the failed 3.5.203 transition loader; no files changed.' }
$backup = $null
foreach ($suffix in @('.pre-bridge.bak', '.bak')) {
    $candidate = $target + $suffix
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        $line = Get-Content -LiteralPath $candidate -TotalCount 1
        if ($line -match '^-- CasualTool release: (\d+\.\d+\.\d+)$' -and [version]$Matches[1] -lt [version]'3.5.203') {
            $backup = $candidate
            break
        }
    }
}
if (-not $backup) { throw 'No application backup found. No files changed.' }
$stage = $target + '.recover'
if (Test-Path -LiteralPath $stage) { throw 'Recovery staging file already exists; no files changed.' }
$hash = (Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash
Copy-Item -LiteralPath $target -Destination ($target + '.failed-203-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.bak')
Copy-Item -LiteralPath $backup -Destination $stage
if ((Get-FileHash -LiteralPath $stage -Algorithm SHA256).Hash -ne $hash) { throw 'Backup copy checksum mismatch; current script preserved.' }
Move-Item -LiteralPath $stage -Destination $target -Force
if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $hash) { throw 'Restored file checksum mismatch.' }
Write-Output 'Previous X-Tools restored. Start GTA and enter /update. Settings were not changed.'
