param([string]$Context = 'k3d-teko-k8s', [switch]$CloudVerified)
. (Join-Path $PSScriptRoot 'common.ps1')
if (-not $CloudVerified) { throw 'Verify fresh metrics and logs in Grafana Cloud first, then pass -CloudVerified.' }
$helmPath = Resolve-Helm
kubectl --context $Context -n monitoring rollout status statefulset/alloy --timeout=120s
Assert-NativeSuccess 'Checking Alloy readiness'
$alloyState = kubectl --context $Context -n monitoring get statefulset alloy -o json | ConvertFrom-Json
Assert-NativeSuccess 'Reading Alloy state'
if ($alloyState.status.readyReplicas -ne 1) { throw 'Exactly one ready Alloy replica is required.' }
$activeValues = Join-Path $PSScriptRoot '../monitoring/values-cloud-active.yaml'
# Keep the switch reproducible after a successful Helm upgrade.
& $helmPath upgrade monitoring prometheus-community/kube-prometheus-stack --version 88.1.3 --kube-context $Context --namespace monitoring --values (Join-Path $PSScriptRoot '../monitoring/values-light.yaml') --values (Join-Path $PSScriptRoot 'values-cloud-active.yaml') --wait --timeout 8m
Assert-NativeSuccess 'Disabling the local Prometheus server'
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'values-cloud-active.yaml') -Destination $activeValues -Force
kubectl --context $Context -n monitoring get pods
Assert-NativeSuccess 'Checking the final monitoring state'
Write-Host 'Cloud migration complete. Use Grafana Cloud for dashboards and logs.'
