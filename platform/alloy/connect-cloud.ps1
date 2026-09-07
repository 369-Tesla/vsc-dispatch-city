param([string]$Context = 'k3d-teko-k8s', [switch]$ReuseExistingSecret)
. (Join-Path $PSScriptRoot 'common.ps1')
$helmPath = Resolve-Helm
kubectl --context $Context get namespace monitoring
Assert-NativeSuccess 'Checking the monitoring namespace'

function Assert-Endpoint([string]$value, [string]$Suffix) {
    $uri = $null
    if (-not [uri]::TryCreate($value, [UriKind]::Absolute, [ref]$uri) -or
        $uri.Scheme -ne 'https' -or -not $uri.Host.EndsWith('.grafana.net') -or
        $uri.AbsolutePath -ne $Suffix -or $uri.UserInfo -or $uri.Query -or $uri.Fragment) {
        throw "Expected a Grafana Cloud HTTPS endpoint ending in $Suffix."
    }
    return $value
}
$endpoints = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'cloud-endpoints.json') | ConvertFrom-Json
$metricsUrl = Assert-Endpoint $endpoints.metricsUrl '/api/prom/push'
$metricsUser = $endpoints.metricsUser
$logsUrl = Assert-Endpoint $endpoints.logsUrl '/loki/api/v1/push'
$logsUser = $endpoints.logsUser
if ($metricsUser -notmatch '^\d+$' -or $logsUser -notmatch '^\d+$') {
    throw 'Instance IDs must be numeric; do not enter your account email.'
}
if ($ReuseExistingSecret) {
    kubectl --context $Context -n monitoring get secret grafana-cloud -o name
    Assert-NativeSuccess 'Checking the existing credentials secret'
} else {
$secureToken = Read-Host 'Access-policy token (metrics:write and logs:write)' -AsSecureString
$tokenPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureToken)
try {
    $plainToken = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($tokenPointer)
    if ([string]::IsNullOrWhiteSpace($plainToken)) { throw 'Token is empty.' }
    # Send the secret through stdin; never store it in the repository or CLI arguments.
    $secret = @{
        apiVersion = 'v1'; kind = 'Secret'
        metadata = @{name = 'grafana-cloud'; namespace = 'monitoring'}
        type = 'Opaque'
        stringData = @{
            GC_METRICS_URL = $metricsUrl; GC_METRICS_USER = $metricsUser
            GC_LOGS_URL = $logsUrl; GC_LOGS_USER = $logsUser; GC_TOKEN = $plainToken
        }
    }
    $secret | ConvertTo-Json -Depth 6 -Compress | kubectl --context $Context apply --server-side --field-manager=alloy-cloud-setup -f -
    Assert-NativeSuccess 'Creating the credentials secret'
} finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($tokenPointer)
    $plainToken = $null
    $secret = $null
    $secureToken.Dispose()
}
}

kubectl --context $Context apply -f (Join-Path $PSScriptRoot 'log-rbac.yaml')
Assert-NativeSuccess 'Applying namespace-scoped log permissions'
& $helmPath repo add grafana https://grafana.github.io/helm-charts --force-update
Assert-NativeSuccess 'Adding the Grafana chart repository'
# Helm's --set-file parser treats backslashes as escapes, including on Windows.
$configPath = (Join-Path $PSScriptRoot 'config.alloy').Replace('\', '/')
& $helmPath upgrade --install alloy grafana/alloy --version 1.12.1 --kube-context $Context --namespace monitoring --values (Join-Path $PSScriptRoot 'values.yaml') --set-file "alloy.configMap.content=$configPath" --wait --timeout 10m
Assert-NativeSuccess 'Installing Alloy'
# Restart on repeated setup so updated secret environment variables are loaded.
kubectl --context $Context -n monitoring rollout restart statefulset/alloy
Assert-NativeSuccess 'Refreshing Alloy credentials'
kubectl --context $Context -n monitoring rollout status statefulset/alloy --timeout=180s
Assert-NativeSuccess 'Waiting for Alloy'
Write-Host 'Alloy is running. Verify metrics and logs in Grafana Cloud before completing migration.'
Write-Host 'Then run: ./platform/alloy/complete-migration.ps1 -CloudVerified'
