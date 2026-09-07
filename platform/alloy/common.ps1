$ErrorActionPreference = 'Stop'
function Resolve-Helm {
    $command = Get-Command helm -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    $portable = Join-Path $env:TEMP 'codex-helm-v4.2.4/windows-amd64/helm.exe'
    if (Test-Path -LiteralPath $portable) { return $portable }
    throw 'Helm is missing. Install Helm and add it to PATH.'
}
function Assert-NativeSuccess([string]$Action) {
    if ($LASTEXITCODE -ne 0) { throw "$Action failed (exit $LASTEXITCODE)." }
}
