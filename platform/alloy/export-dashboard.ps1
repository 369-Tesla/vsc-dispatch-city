$ErrorActionPreference = 'Stop'
$source = Join-Path $PSScriptRoot '../../deploy/overlays/block-07-observability/grafana-dashboard.yaml'
# The course ConfigMap is JSON (also valid YAML).
$configMap = Get-Content -Raw -LiteralPath $source | ConvertFrom-Json
$dashboard = $configMap.data.'food-delivery.json' | ConvertFrom-Json
$dashboard.uid = 'dispatch-city-cloud'
$dashboard.title = 'Dispatch City - Betrieb (Cloud)'
$dashboard | Add-Member -Force NoteProperty '__inputs' @(@{
    name = 'DS_PROMETHEUS'; label = 'Grafana Cloud Metrics'; type = 'datasource'
    pluginId = 'prometheus'; pluginName = 'Prometheus'
})
foreach ($panel in $dashboard.panels) {
    $panel.datasource.uid = '${DS_PROMETHEUS}'
    foreach ($target in $panel.targets) {
        $target.datasource.uid = '${DS_PROMETHEUS}'
        if ($target.expr.Contains('{')) {
            $target.expr = $target.expr.Replace('{', '{cluster="teko-k8s",')
        } else {
            $target.expr = $target.expr -replace '(food_delivery_[a-z_]+)', '$1{cluster="teko-k8s"}'
        }
    }
}
$dashboard | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'dispatch-city-cloud.json') -Encoding utf8
Write-Host 'Cloud dashboard exported with a selectable Prometheus data source.'
