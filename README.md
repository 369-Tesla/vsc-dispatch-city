# Dispatch City

Kursprojekt mit Nuxt-/PixiJS-Dashboard, Go-Services, RabbitMQ und CloudNativePG.
Die Ausbaustufen 3–7 liegen unter `deploy/overlays`, die Arbeitsnachweise unter
`docs/Auftragsblätter`. Siehe auch [Architektur](docs/architecture.md).
Der Wechsel von Prometheus zu Grafana Alloy mit Grafana Cloud wurde abgesprochen.

## Voraussetzungen

Docker Desktop mit laufender Linux-Engine, Git, k3d, kubectl und Helm im PATH.
Unter Windows PowerShell verwenden; unter macOS die Shell-Skripte und für Alloy
zusätzlich PowerShell 7 (`pwsh`). Für Grafana Cloud werden ein eigener Stack und
Schreibzugang benötigt, siehe [Alloy-Anleitung](platform/alloy/README.md).
Alle Befehle im Projektordner ausführen.

## Cluster und Images

Für einen neuen Cluster; bei vorhandenem Cluster stattdessen
`k3d cluster start teko-k8s` verwenden:

```text
k3d cluster create teko-k8s --agents 2
kubectl config use-context k3d-teko-k8s
kubectl wait --for=condition=Ready nodes --all --timeout=180s
```

Den Kontext auch beim Wiederanlauf auf `k3d-teko-k8s` setzen. Das Dashboard muss
separat gebaut werden, weil das bereitgestellte Build-Skript nur Go-Images baut:

```text
docker build -t food-delivery-dashboard:local ./apps/dashboard
```

Windows PowerShell:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
./scripts/build-images.ps1
./scripts/load-images.ps1 -Cluster teko-k8s
./platform/cloudnative-pg/install.ps1
```

macOS:

```bash
sh scripts/build-images.sh
CLUSTER=teko-k8s sh scripts/load-images.sh
sh platform/cloudnative-pg/install.sh
```

## Finalen Stand deployen

Zuerst Anwendung und Datenbank installieren und Migration abwarten:

```text
kubectl apply -k deploy/overlays/block-06-persistence
kubectl -n food-delivery wait --for=condition=Ready cluster/food-delivery-db --timeout=600s
kubectl -n food-delivery wait --for=condition=complete job/database-migrate --timeout=300s
```

Danach unter Windows `./platform/monitoring/start-course.ps1`, unter macOS
`sh platform/monitoring/start-course.sh` ausführen. Dieses vorhandene Skript baut
und importiert auch das Observer-Image und aktiviert Block 7.
Das Lab anlegen, bevor Alloy seine Zugriffsrechte für beide Namespaces erhält:

```text
kubectl apply -f labs/block-07/web.yaml
kubectl apply -f labs/block-07/hpa.yaml
kubectl -n food-delivery wait --for=condition=Ready pod --all --timeout=300s
```

Alloy unter Windows mit `./platform/alloy/connect-cloud.ps1` installieren,
unter macOS mit `pwsh -NoProfile -File platform/alloy/connect-cloud.ps1`.
Endpunkte, Token-Eingabe und Dashboard-Import sind in der
[Alloy-Anleitung](platform/alloy/README.md) beschrieben.
Der versionierte Monitoring-Override deaktiviert lokalen Prometheus bereits.
Deshalb Grafana Cloud öffnen, auch wenn das Kursskript noch auf lokales Grafana
verweist. Frische Metriken und Logs in der Cloud separat prüfen.

## Zugriff und Smoke-Test

Je einen Port-Forward in einem eigenen Terminal laufen lassen:

```text
kubectl -n kube-system port-forward service/traefik 8080:80
kubectl -n food-delivery port-forward service/rabbitmq 15672:15672
```

Dashboard: <http://localhost:8080>. RabbitMQ: <http://localhost:15672>,
Kurslogin `delivery` / `delivery`. Grafana im eigenen Cloud Stack öffnen.
Für einen kurzen Smoke-Test:

```text
kubectl -n food-delivery get pods,deployments,statefulsets
kubectl -n food-delivery get cluster food-delivery-db
kubectl -n monitoring get pods
kubectl -n betrieb-lab get hpa
```

Unter Windows `Invoke-RestMethod http://localhost:8080/health/ready` und
`Invoke-RestMethod http://localhost:8080/api/v1/snapshot` ausführen;
unter macOS entsprechend `curl --fail http://localhost:8080/health/ready` und
`curl --fail http://localhost:8080/api/v1/snapshot`.
Erwartet: bereite Workloads, zwei DB-Instanzen, HTTP-Erfolg und Modus `distributed`.
Im Dashboard eine Bestellung bis zur Lieferung verfolgen; RabbitMQ-Queues und
aktuelle Grafana-Messwerte prüfen.
Die bestehenden Arbeitsblätter 4, 6 und 7 enthalten Ausfall- und Skalierungsversuche.

## Reset und Wiederanlauf

Für einen fachlichen Reset zuerst pausieren und laufende Verarbeitung auslaufen
lassen. Unter Windows die Befehle nacheinander ausführen:

```powershell
Invoke-RestMethod -Method Post http://localhost:8080/api/v1/simulation/pause
Invoke-RestMethod -Method Post http://localhost:8080/api/v1/simulation/reset
```

Unter macOS jeweils `curl --fail -X POST` statt `Invoke-RestMethod -Method Post`
verwenden. Reset entfernt Bestellungen, behält aber Cluster, PVCs und
Idempotenzschlüssel. Die Verarbeitung erfolgt asynchron; Ergebnis im Dashboard prüfen.

Normaler Wiederanlauf: Docker Desktop starten, `k3d cluster start teko-k8s`,
Kontext setzen und Port-Forwards erneut öffnen. Für einen vollständigen Neustart
`k3d cluster delete teko-k8s` ausführen und die obigen Schritte wiederholen.
Dabei werden die lokalen Cluster-Daten gelöscht; Cloud-Zugang erneut einrichten.

## Grundlagen und Hilfsmittel

Grundlage sind die vom Dozenten bereitgestellten Kursbausteine und Arbeitsblätter.
Für die Textgestaltung und Grafana Cloud Anbindung wurde ChatGPT als Hilfsmittel verwendet.
