# Grafana Alloy und Grafana Cloud

Der Wechsel ersetzt den lokalen Prometheus-Server durch Alloy als Collector und
Grafana Cloud als Metrikspeicher. Alloy selbst ist keine abfragbare Prometheus-Datenbank.

## 1. Cloud-Endpunkte finden

1. Unter https://grafana.com/auth/sign-in/ anmelden und das Cloud Portal öffnen.
2. Den gewünschten Stack auswählen (nicht das lokale Grafana auf localhost).
3. Auf der Karte **Prometheus** (gegebenenfalls **Metrics**) **Details** öffnen.
4. **Remote Write Endpoint** und **User / Instance ID** notieren. Die URL endet auf
   `/api/prom/push`. Die ID ist eine Zahl, nicht deine E-Mail-Adresse.
5. Zur Stack-Übersicht zurückgehen, **Loki / Logs → Details** öffnen.
6. Die URL mit `/loki/api/v1/push` sowie die dortige **User / Instance ID** notieren.
   Logs und Metrics können unterschiedliche IDs haben.

## 2. Schreib-Token erstellen

Deine Endpunkte sind bereits in `cloud-endpoints.json` hinterlegt:
Metrics-ID `3558890`, Logs-ID `1775120`. Die Logs-Basisadresse wurde um
`/loki/api/v1/push` ergänzt. Diese Datei enthält keinen Token.

1. Im Cloud Portal **Access Policies** öffnen.
2. Eine Policy `dispatch-city-writer` für genau diesen Stack erstellen.
3. Berechtigungen **metrics:write** und **logs:write** auswählen.
4. Einen Token für diese Policy erzeugen, Ablaufdatum passend wählen und kopieren.
5. Den Token nur in die verdeckte lokale Eingabe des nächsten Schritts einfügen.
   Weder Chat noch Git benötigen den Token. Das Skript speichert ihn als Secret
   `monitoring/grafana-cloud` im lokalen Kubernetes-Cluster. Kubernetes Secrets sind
   keine automatische Verschlüsselungsgarantie; Clusteradministratoren können sie lesen.

Alternativ führt **Generate now** in den Endpoint-Details zur Token-Erstellung.
Ein Grafana-Service-Account-Token ist kein Ersatz für diesen Cloud-Access-Policy-Token.

## 3. Alloy lokal verbinden

PowerShell im Projektordner öffnen:

```powershell
Set-Location C:\dev\Projects\vsc-dispatch-city
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
./platform/alloy/connect-cloud.ps1
```

Nur den Token eingeben; Endpunkte und IDs werden aus `cloud-endpoints.json` gelesen.
Die erste Installation kann wegen
des Image-Downloads mehrere Minuten dauern. Das Skript nutzt Helm aus PATH oder die
bereits vorhandene portable Kursinstallation. Docker und der Cluster müssen laufen.

Alloy startet als einzelner StatefulSet-Pod mit 1 GiB lokalem Speicher für den
Metrik-WAL und Event-Lesepositionen. Das ist ein begrenzter Puffer, kein Backup.
Bei Token-Wechsel dasselbe Skript erneut ausführen; es lädt die Secret-Werte neu.

Falls die Installation nach dem Speichern des Secrets abbricht, ohne erneute
Token-Eingabe fortsetzen:

```powershell
./platform/alloy/connect-cloud.ps1 -ReuseExistingSecret
```

Erfasst werden die bestehenden Anwendungs-, RabbitMQ- und PostgreSQL-Metriken,
Kubernetes-Objektmetriken sowie Container-CPU/Speicher für `food-delivery` und
`betrieb-lab`. Dazu kommen Pod-Logs und Kubernetes-Events dieser beiden Namespaces.
Logs können Bestell-IDs und Fehlermeldungen enthalten und werden an deinen Cloud-Stack
übertragen. Keine Traces oder Profile ohne weitere Instrumentierung.

## 4. Empfang in Grafana Cloud prüfen

Im Cloud-Stack Grafana öffnen und **Explore** auswählen. Als Datenquelle die
vorhandene Cloud-Prometheus-/Metrics-Datenquelle auswählen. Zeitraum letzte
15 Minuten; nach dem Start ein bis zwei Minuten warten.

```promql
food_delivery_active_orders{cluster="teko-k8s"}
```

```promql
kube_deployment_status_replicas_available{cluster="teko-k8s",namespace="food-delivery",deployment="restaurant-pizza"}
```

```promql
rabbitmq_queue_messages_ready{cluster="teko-k8s",namespace="food-delivery",queue=~"restaurant.*"}
```

Frische Zeitstempel und Werte prüfen. Anschliessend die Cloud-Loki-/Logs-Datenquelle
auswählen und folgende Abfragen ausführen:

```logql
{cluster="teko-k8s",namespace="food-delivery",pod=~".+"}
```

```logql
{cluster="teko-k8s",job="kubernetes-events"}
```

Events sind nur vorhanden, wenn Kubernetes Ereignisse erzeugt hat. Eine leere
Event-Abfrage allein beweist deshalb keinen Übertragungsfehler.

## 5. Kurs-Dashboard importieren

1. In Grafana Cloud **Dashboards → New → Import** öffnen.
2. `platform/alloy/dispatch-city-cloud.json` hochladen.
3. Bei **Grafana Cloud Metrics** die vorhandene Cloud-Prometheus-Datenquelle wählen.
4. Importieren und **Last 15 minutes** einstellen.

Das Dashboard behält die fünf Kursanzeigen bei und filtert auf `cluster="teko-k8s"`.
Zum späteren erneuten Export `./platform/alloy/export-dashboard.ps1` ausführen.
Im Cloud-Portal die Nutzung der aktiven Serien und des Logvolumens beobachten;
die Namespace-Filter begrenzen die Menge, garantieren aber kein bestimmtes Kontingent.

## 6. Prometheus abschalten

Erst wenn frische Metriken und Pod-Logs in der Cloud sichtbar sind:

```powershell
./platform/alloy/complete-migration.ps1 -CloudVerified
```

Das Skript prüft Alloy und deaktiviert den Prometheus-Server über Helm. Der
Prometheus Operator, seine CRDs, ServiceMonitors, PodMonitors und kube-state-metrics
bleiben für die Erfassung durch Alloy erhalten. Der Kubernetes Metrics Server und
damit der HPA bleiben unabhängig davon in Betrieb.

Der Umschalt-Override wird nach `platform/monitoring/values-cloud-active.yaml`
kopiert und von den vorhandenen Installationsskripten berücksichtigt. Diese Datei
nach erfolgreichem Wechsel mit versionieren. Alte lokale Prometheus-Messwerte werden
nicht in die Cloud migriert; mit dem Entfernen seines Pods geht die bisherige
kurzfristige Historie ohne persistenten Speicher verloren.

Das lokale Grafana bleibt installiert. Seine bisherige Datenquelle zeigt jedoch auf
den abgeschalteten Prometheus. Für Messwerte jetzt das Cloud-Dashboard verwenden.
Soll das lokale Grafana weiter anzeigen, dort eine Cloud-Prometheus-Datenquelle mit
Query-Endpoint und separatem `metrics:read`-Token einrichten und das Cloud-Dashboard
mit dieser Datenquelle importieren. Keinen Schreib-Token hierfür erweitern.

## Fehler prüfen

```powershell
kubectl --context k3d-teko-k8s -n monitoring get pods
kubectl --context k3d-teko-k8s -n monitoring logs alloy-0 --tail=80
```

`401/403`: Instance ID, Token, Stack-Zuordnung und Scopes prüfen.
`429`: Cloud-Kontingent/Senderate prüfen. `No data`: Datenquelle, Zeitraum,
Clusterfilter, Scrape-Ziele und Senderfehler prüfen. Pod-Bereitschaft alleine
beweist keine erfolgreiche Cloud-Übertragung.

Die vorhandene Kubelet-ServiceMonitor-Konfiguration verwendet für den lokalen
k3d-Cluster dessen bisherige TLS-Ausnahme; sie wird für diesen einzelnen Monitor
übernommen. Cloud-Verbindungen verwenden normales HTTPS mit Zertifikatsprüfung.

## Zurück zum lokalen Monitoring

Alloy bei Bedarf vorübergehend stoppen:

```powershell
kubectl --context k3d-teko-k8s -n monitoring scale statefulset/alloy --replicas=0
```

Die aktive Override-Datei in `platform/monitoring` umbenennen, damit der nächste
Kursstart wieder Prometheus aktiviert. Danach `platform/monitoring/install.ps1`
mit Helm in PATH ausführen. Dies rekonstruiert keine bereits verlorene Historie.

## Quellen

- [Alloy mit Helm konfigurieren](https://grafana.com/docs/alloy/latest/configure/kubernetes/)
- [ServiceMonitors übernehmen](https://grafana.com/docs/alloy/latest/reference/components/prometheus/prometheus.operator.servicemonitors/)
- [Kubernetes-Logs sammeln](https://grafana.com/docs/alloy/latest/collect/logs-in-kubernetes/)
- [Cloud-Endpunkte finden](https://grafana.com/docs/grafana-cloud/observe-and-act/send-data/metrics/metrics-prometheus/prometheus-config-examples/integration-guide/)
- [Access Policies](https://grafana.com/docs/grafana-cloud/platform/security-and-account-management/security-and-access/authentication-and-permissions/access-policies/)
