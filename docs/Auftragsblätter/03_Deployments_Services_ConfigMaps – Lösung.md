---
tags:
  - vsc
  - kubernetes
block: "03"
---

# 03 – Deployments, Services, ConfigMaps – Lösung

## Aufgabe 1) Foundation übernehmen und Systemgrenze verstehen

### a) Eigenes Repository aus dem GitHub-Template, Release `v1.0.0`

Projekt-Repository: `C:\dev\Projects\vsc-dispatch-city`

```bash
git clone --depth 1 --branch v1.0.0 https://github.com/SwitzerChees/vsc-dispatch-city-03-foundation.git C:\dev\Projects\vsc-dispatch-city
```

Danach wurde die Template-Historie entfernt und eine eigene, fortlaufende Projekt-Historie gestartet
(entspricht dem, was GitHub bei "Use this template" macht: Dateien übernehmen, Commits nicht):

```bash
rm -rf .git
git init -b main
git add -A
git commit -m "Initial commit from template vsc-dispatch-city-03-foundation v1.0.0"
```

Stand: Tag `v1.0.0` des Templates, 39 Dateien, ein Initial-Commit auf `main`.

Das Repository bleibt vorerst rein lokal. Anbindung an GitHub später:

```bash
git remote add origin https://github.com/<user>/vsc-dispatch-city.git
git push -u origin main
```

### b) Kontext und Nodes des Clusters «teko-k8s» prüfen

```bash
k3d cluster list
k3d cluster start teko-k8s
kubectl config use-context k3d-teko-k8s
kubectl get nodes -o wide
```

Befund vor dem Start: Docker läuft, `kubectl` v1.32.2 ist vorhanden, aber

- `k3d` war nicht installiert (weder im Windows-PATH noch in WSL – es existiert nur die
  `docker-desktop`-Distro, keine echte Linux-Distro),
- `kubectl config get-contexts` lieferte eine leere Liste, `current-context is not set`,
- `docker ps` zeigte keine `k3d-teko-k8s-*`-Container.

Der Cluster aus Block 2 existierte also nicht mehr und musste neu erstellt werden.

**k3d installiert** (kein winget/choco/scoop vorhanden, daher Binary direkt vom offiziellen Release):
`k3d v5.9.0` nach `C:\Users\Noah\bin\k3d.exe`, Verzeichnis im User-`PATH`.

**Stolperstein cgroup v1:** Der erste Versuch mit dem k3d-Default-Image (k3s v1.35.5) schlug fehl.
Server-Container liefen, aber der Cluster wurde nie fertig. Ursache im Log von
`k3d-teko-k8s-server-0`:

```
Error: failed to validate kubelet configuration, error: kubelet is configured to not run
on a host using cgroup v1
```

`docker info` bestätigt: `CgroupVersion=1`, Kernel `5.15.167.4-microsoft-standard-WSL2`. Die
WSL2-VM dieser Docker-Desktop-Installation läuft noch auf cgroup v1, neuere k3s-/Kubernetes-Versionen
verlangen cgroup v2. Lösung ohne Docker-Desktop-Update: k3s-Image auf eine Version pinnen, die cgroup
v1 noch unterstützt.

```bash
k3d cluster delete teko-k8s
docker pull rancher/k3s:v1.31.5-k3s1
k3d cluster create teko-k8s --agents 2 --image rancher/k3s:v1.31.5-k3s1 --wait
kubectl config use-context k3d-teko-k8s
kubectl get nodes -o wide
```

Ergebnis:

```
NAME                    STATUS  ROLES                 AGE  VERSION       INTERNAL-IP
k3d-teko-k8s-server-0   Ready   control-plane,master  18s  v1.31.5+k3s1  172.19.0.3
k3d-teko-k8s-agent-0    Ready   <none>                15s  v1.31.5+k3s1  172.19.0.5
k3d-teko-k8s-agent-1    Ready   <none>                16s  v1.31.5+k3s1  172.19.0.4
```

`k3d cluster list` → `teko-k8s  1/1 Server  2/2 Agents  LoadBalancer true`,
aktiver Kontext `k3d-teko-k8s`. Ein Server-Node (Control Plane) und zwei Agent-Nodes, alle `Ready`.

### c) Rollen von «dashboard» und «control-api», Grund für genau eine Control-API-Replik

**control-api** (`cmd/control-api`, Go, Port 8080) ist das Backend und der Motor des Systems: Sie
betreibt die Simulation der Stadt (Restaurants, Kunden, Kuriere, Bestellungen) in einer Tick-Schleife
(`TICK_MS`) und stellt die REST-Endpunkte `/api/v1/snapshot`, `/api/v1/orders`,
`/api/v1/simulation/{start,pause,reset}`, den SSE-Stream `/api/v1/events` sowie `/health/live`,
`/health/ready` und `/metrics` bereit. Sie ist die einzige Quelle der Wahrheit.

**dashboard** (`apps/dashboard`, Nuxt 4 + PixiJS, Port 3000) ist das Frontend: Es hält keinen
fachlichen Zustand, sondern holt den Snapshot von der Control API, abonniert deren Event-Stream und
rendert daraus die 21×21-Tile-Stadt mit den animierten Fahrtrouten. Fällt das Dashboard aus, läuft
die Simulation weiter; fällt die Control API aus, hat das Dashboard nichts mehr anzuzeigen.

**Warum genau eine Replik?** Der Zustand der Simulation liegt ausschliesslich im Prozessspeicher der
Control API – `simulation.Engine` hält Restaurants, Kunden, Kuriere, Bestellungen und die
SSE-Subscriber in Maps hinter einem Mutex, es gibt weder Datenbank noch Messaging. Zwei Repliken
wären damit zwei voneinander unabhängige Städte: Der Service würde die Requests per Round-Robin
verteilen, ein `POST /api/v1/orders` landete auf Pod A, der nächste `GET /api/v1/snapshot` auf Pod B,
und der SSE-Stream zeigte einen dritten, wieder anderen Verlauf. Das Ergebnis wäre kein skaliertes
System, sondern ein inkonsistentes.

Das ist die bewusst gesetzte Architekturgrenze von Block 3 (`deploy/base/control-api.yaml`:
`replicas: 1`, `docs/architecture.md`): Horizontal skalierbar ist nur ein zustandsloser Dienst –
das Dashboard könnte man jederzeit hochskalieren. Aufgelöst wird die Grenze erst durch externen,
geteilten Zustand in späteren Blöcken (Persistenz per Datenbank, Verteilung per Messaging/Broker),
danach ist auch die Control API zustandslos genug für mehrere Repliken.

---

## Aufgabe 2) Images bauen und Kustomize-Ausgabe lesen

### a) Image → Dockerfile → Tag

| Image | Dockerfile | Tag | Grösse |
| --- | --- | --- | --- |
| `food-delivery-control-api` | `build/go-service.Dockerfile` (Build-Arg `SERVICE=control-api`) | `local` | 14.7 MB |
| `food-delivery-dashboard` | `apps/dashboard/Dockerfile` | `local` | 240 MB |

```bash
docker build -t food-delivery-control-api:local --build-arg SERVICE=control-api -f ./build/go-service.Dockerfile .
docker build -t food-delivery-dashboard:local ./apps/dashboard
```

Beide sind Multi-Stage-Builds. Der Grössenunterschied erklärt das Prinzip: Go kompiliert zu einer
statischen Binary, die in ein minimales Runtime-Image kopiert wird; Nuxt braucht im Runtime-Image
weiterhin Node plus den `.output`-Server.

### b) Import in den Cluster und `imagePullPolicy: IfNotPresent`

```bash
k3d image import -c teko-k8s food-delivery-control-api:local food-delivery-dashboard:local
```

k3d packt beide Images in ein Tarball und importiert es in die containerd-Instanz **jedes** Nodes
(server-0, agent-0, agent-1). Nötig ist das, weil der Cluster nicht auf den Docker-Daemon des Hosts
zugreift – die Nodes sind eigene Container mit eigenem Image-Store.

`imagePullPolicy: IfNotPresent` heisst: Der kubelet zieht das Image nur, wenn es lokal nicht liegt.
Genau das ist hier zwingend, denn `food-delivery-*:local` existiert in keiner Registry. Mit
`Always` (dem Default bei Tag `:latest`) würde der Pod mit `ErrImagePull` / `ImagePullBackOff`
scheitern. Kehrseite: Baut man das Image mit demselben Tag neu, merkt Kubernetes den Unterschied
nicht – nach jedem Rebuild braucht es `k3d image import` **und** einen `rollout restart`.

### c) `kubectl kustomize deploy/overlays/block-03-standalone`

Rendert den Zielzustand, ohne etwas am Cluster zu ändern. Es entstehen **6 Ressourcen**, alle aus der
Base (`deploy/base/kustomization.yaml`):

| Kind | Name |
| --- | --- |
| Namespace | `food-delivery` |
| ConfigMap | `simulation-config` |
| Service | `control-api` |
| Service | `dashboard` |
| Deployment | `control-api` |
| Deployment | `dashboard` |

Das Overlay selbst fügt **keine** neue Ressource hinzu. Es setzt nur ein zusätzliches Label:

```yaml
labels:
  - pairs:
      course.teko.ch/block: "03"
    includeSelectors: false
```

`includeSelectors: false` ist dabei das Entscheidende: Das Label landet auf den Objekten und
Pod-Templates, aber **nicht** in den Selektoren von Deployment und Service. Würde es in die
Selektoren wandern, wäre `spec.selector` eines bestehenden Deployments verändert – und das Feld ist
immutable, ein späteres `apply` würde fehlschlagen.

---

## Aufgabe 3) Manifeste als Vertrag deployen

### a) Service-Selector → Pod-Labels, `targetPort` → benannter Container-Port

Für beide Anwendungen ist die Kette identisch aufgebaut:

```
Service.spec.selector: app.kubernetes.io/name=control-api
        ↓ matcht
Pod-Label:              app.kubernetes.io/name=control-api
        ↓
Service.ports.targetPort: http
        ↓ löst auf zu
containers[].ports: name=http, containerPort=8080
```

Beim Dashboard genauso, nur mit `name=dashboard` und Port 3000. Der Service kennt die Pods also nicht
namentlich, sondern nur über Labels – deshalb funktioniert er auch nach einem Rollout mit komplett
neuen Pod-Namen weiter. Der benannte Port (`targetPort: http` statt `8080`) ist die zweite Entkopplung:
Ändert der Container seinen Port, muss nur das Deployment angefasst werden, der Service bleibt gleich.

### b) `envFrom` → ConfigMap und Probes der Control API

```yaml
envFrom:
  - configMapRef:
      name: simulation-config     # liefert APP_MODE und TICK_MS als Umgebungsvariablen
env:
  - name: POD_NAME
    valueFrom:
      fieldRef:
        fieldPath: metadata.name  # Downward API -> Pod-Name landet im Dashboard-Header
readinessProbe:  GET /health/ready  port http  initialDelay 2s  period 5s
livenessProbe:   GET /health/live   port http  initialDelay 5s  period 10s
```

`envFrom` übernimmt **alle** Schlüssel der ConfigMap auf einmal als Env-Variablen – die Namen der
Variablen sind die Schlüssel der ConfigMap. Das Image bleibt dadurch unverändert, wenn sich die
Konfiguration ändert.

### c) Deployment und Nachweis

```bash
kubectl apply -k deploy/overlays/block-03-standalone
kubectl -n food-delivery rollout status deployment/control-api
kubectl -n food-delivery rollout status deployment/dashboard
```

```
namespace/food-delivery created        deployment "control-api" successfully rolled out
configmap/simulation-config created    deployment "dashboard"   successfully rolled out
service/control-api created
service/dashboard created
deployment.apps/control-api created
deployment.apps/dashboard created
```

```
NAME                          READY  UP-TO-DATE  AVAILABLE  IMAGES
deployment.apps/control-api   1/1    1           1          food-delivery-control-api:local
deployment.apps/dashboard     1/1    1           1          food-delivery-dashboard:local

NAME                               READY  STATUS   IP         NODE
pod/control-api-7c8987bf5b-b5vtx   1/1    Running  10.42.0.5  k3d-teko-k8s-agent-0
pod/dashboard-854cff68d6-rbbpp     1/1    Running  10.42.2.5  k3d-teko-k8s-server-0

NAME                  TYPE       CLUSTER-IP     PORT(S)
service/control-api   ClusterIP  10.43.75.147   8080/TCP
service/dashboard     ClusterIP  10.43.20.11    3000/TCP
```

Die beiden Pods liegen auf verschiedenen Nodes – der Scheduler hat frei entschieden. Genau deshalb
mussten die Images auf **alle** Nodes importiert werden.

---

## Aufgabe 4) Service, EndpointSlice und DNS als Kette prüfen

### a) Selector, Labels, EndpointSlice

```
Service control-api    selector: app.kubernetes.io/name=control-api
Pod control-api-...    labels:   app.kubernetes.io/name=control-api,
                                 app.kubernetes.io/part-of=food-delivery,
                                 pod-template-hash=7c8987bf5b
EndpointSlice control-api-7hsdn   IPv4  8080  ENDPOINTS 10.42.0.5   <- Pod-IP
EndpointSlice dashboard-8hb6r     IPv4  3000  ENDPOINTS 10.42.2.5
```

Die EndpointSlice ist der eigentliche Beweis. Ein Service existiert auch dann, wenn er ins Leere
zeigt; erst der Eintrag der Pod-IP in der EndpointSlice belegt, dass der Endpoint-Controller einen
passenden **und bereiten** Pod gefunden hat. Der `pod-template-hash` ist übrigens nicht im Selector –
sonst würde jeder Rollout den Service ins Leere laufen lassen.

### b) `/health/ready` aus einem temporären Pod

```bash
kubectl run dns-test --image=curlimages/curl:8.8.0 -n food-delivery --restart=Never --rm -i -- \
  sh -c "curl -fsS http://control-api:8080/health/ready; curl -fsS http://control-api.food-delivery.svc.cluster.local:8080/health/ready"
```

Beide Aufrufe liefern `{"status":"ok"}` – Kurzname und FQDN.

### c) Warum der DNS-Name auf dem Host nicht funktioniert

`control-api.food-delivery.svc.cluster.local` ist ein reiner Cluster-Name. Aufgelöst wird er von
CoreDNS, und in den Pods steht CoreDNS über die eingehängte `/etc/resolv.conf` als Nameserver drin –
inklusive der Search-Domains, die den Kurznamen `control-api` überhaupt erst funktionieren lassen.
Der Windows-Host benutzt seinen eigenen DNS-Resolver, kennt CoreDNS nicht und könnte mit der
ClusterIP `10.43.75.147` auch nichts anfangen: Das Cluster-Netz ist ein virtuelles Netz innerhalb der
k3d-Container. Vom Host führt der Weg deshalb nur über `port-forward`, NodePort oder Ingress.

**Wirkung einer fehlgeschlagenen Readiness Probe:** Der Pod läuft weiter und wird **nicht** neu
gestartet – aber der Endpoint-Controller nimmt seine IP aus der EndpointSlice heraus. Der Service
schickt also keinen Traffic mehr dorthin. Bei nur einer Replik heisst das: Der Service existiert
noch, hat aber keine Endpoints, und jeder Aufruf läuft in einen Connection-Fehler. Die **Liveness**
Probe wäre der andere Fall – dort startet der kubelet den Container neu.

---

## Aufgabe 5) ConfigMap, Probes und Rollout nachvollziehen

### a) `APP_MODE`, `TICK_MS`, Readiness, Liveness

- `APP_MODE=standalone` – Betriebsmodus der Engine (`simulation.NewEngine(mode, instance)`). In
  Block 3 gibt es nur den Standalone-Modus mit In-Memory-Zustand.
- `TICK_MS=500` – Taktrate der Simulationsschleife. `main.go` liest den Wert und rechnet ihn in eine
  Dauer um: `time.Duration(envInt("TICK_MS", 500)) * time.Millisecond`. Kleiner Wert = schnellere
  Stadt, mehr Events.
- **Readiness** (`/health/ready`, alle 5 s): "Darf dieser Pod Traffic bekommen?" Steuert die
  Zugehörigkeit zur EndpointSlice.
- **Liveness** (`/health/live`, alle 10 s): "Lebt dieser Container noch?" Steuert den Neustart des
  Containers.

Beide zeigen im Code auf denselben Handler (`server.health`) – fachlich sind es aber zwei
verschiedene Fragen mit zwei verschiedenen Konsequenzen.

### b) `TICK_MS` ändern und erneut anwenden

`TICK_MS` in `deploy/base/configmap.yaml` von `500` auf `2000` gesetzt:

```bash
kubectl diff -k deploy/overlays/block-03-standalone
kubectl apply -k deploy/overlays/block-03-standalone
# -> configmap/simulation-config configured, alles andere unchanged
```

### c) Bestehender Pod vs. Rollout

Direkt nach dem Apply:

```
configmap simulation-config -> {"APP_MODE":"standalone","TICK_MS":"2000"}
pod control-api-7c8987bf5b-b5vtx   Running   RESTARTS 0   AGE 110s
log: "control API started" ... "interval":"500ms"
```

Die ConfigMap ist neu, der Pod ist derselbe, und er läuft weiter mit **500 ms**. Grund: Über `envFrom`
gesetzte Umgebungsvariablen werden genau einmal beim Start des Containers ausgewertet. Anders als bei
einer als Volume gemounteten ConfigMap gibt es hier keine Aktualisierung zur Laufzeit – und selbst
dann müsste die Anwendung die Datei neu lesen.

Nach dem bewussten Neustart:

```bash
kubectl -n food-delivery rollout restart deployment/control-api
kubectl -n food-delivery rollout status deployment/control-api
kubectl -n food-delivery logs deployment/control-api
```

```
pod control-api-6489dcd7c8-8bnwg   Running   (neuer Pod, neuer Hash)
pod control-api-7c8987bf5b-b5vtx   Terminating
log: "control API started" ... "interval":"2s"
```

Merksatz: **ConfigMap ändern ist kein Deploy.** `rollout restart` setzt nur eine Annotation im
Pod-Template, das reicht dem Deployment-Controller als Änderung und er ersetzt die Pods rollierend.

Danach wurde `TICK_MS` wieder auf `500` zurückgesetzt und erneut neu gestartet – Startlog belegt
`"interval":"500ms"`, das Repository ist wieder im Ausgangszustand.

---

## Aufgabe 6) Projektstand abnehmen und Architekturgrenze dokumentieren

### a) Port-Forward und sichtbarer Ablauf

```bash
# Terminal 1:
kubectl -n food-delivery port-forward service/dashboard 3000:3000
# Terminal 2:
kubectl -n food-delivery port-forward service/control-api 8081:8080
```

`http://127.0.0.1:8081/health/ready` → `{"status":"ok"}`, `http://127.0.0.1:3000` → HTTP 200.

Zwei Port-Forwards sind nötig, weil das Dashboard-Deployment `NUXT_PUBLIC_API_BASE=http://localhost:8081`
gesetzt hat: Die API-Aufrufe macht der **Browser** des Nutzers, nicht der Nuxt-Server im Cluster. Für
den Browser ist `localhost` der eigene Rechner – deshalb muss die Control API auf dem Host unter 8081
liegen.

Sichtbarer Ablauf: Die Simulation läuft nach dem Start von selbst. Kunden geben Bestellungen auf
(`Bestellung eingegangen`), ein Restaurant nimmt an (`Restaurant hat angenommen`), ein Kurier fährt
auf der Strasse zum Restaurant (`Kurier fährt zum Restaurant`), holt ab (`Bestellung abgeholt`),
fährt zum Kunden (`Unterwegs`, laufend `Position aktualisiert`) und liefert (`Geliefert`). Danach
bleibt der Kurier als freie Flotteneinheit an seiner letzten Position stehen. Die Kopfzeile zählt
AKTIV / GELIEFERT / EVENTS mit, der Event-Stream läuft per SSE live durch, und unter FLOTTENLAGE
steht der Pod-Name der Control API (`control-api-5cc8fd4cc-wz5k8`) – der Wert aus der Downward API.

### b) Evidenzen

| Bereich | Evidenz |
| --- | --- |
| Image / Deployment | `docker images` zeigt `food-delivery-control-api:local` (14.7 MB) und `food-delivery-dashboard:local` (240 MB); `k3d image import` meldet "Successfully imported 2 image(s)"; `kubectl get deploy -o wide` zeigt beide Deployments `1/1 AVAILABLE` mit genau diesen Images |
| Service / DNS | `EndpointSlice control-api-7hsdn` enthält die Pod-IP `10.42.0.5:8080`; Curl-Pod erreicht `/health/ready` über Kurzname **und** FQDN, beide `{"status":"ok"}` |
| ConfigMap / Probes / Rollout | ConfigMap auf `TICK_MS=2000` geändert → Pod bleibt bei `interval:"500ms"`; nach `rollout restart` neuer Pod mit `interval:"2s"`; Readiness/Liveness in `describe deployment/control-api` sichtbar |

### c) Architekturgrenze

Die Control API bleibt bei einer Replik, weil ihr gesamter Zustand im Prozessspeicher liegt (siehe
Aufgabe 1c). Eine zweite Replik wäre keine Skalierung, sondern eine zweite, abweichende Stadt: Der
Service verteilt Requests per Round-Robin, und der SSE-Stream hinge fest an genau einem Pod.

Auflösen lässt sich das nur, indem der Zustand aus dem Pod herauswandert:

- **Persistenz** (Datenbank): gemeinsamer Zustand statt In-Memory-Maps; Pods werden austauschbar.
- **Messaging / Event-Broker**: Events werden nicht mehr pro Pod an lokale Subscriber verteilt,
  sondern über ein Topic – jeder Pod kann jeden Client bedienen.
- **Ingress / Gateway**: löst das Port-Forward-Provisorium ab und macht `localhost:8081` im Dashboard
  überflüssig.

Erst mit diesen Bausteinen ist die Control API zustandslos genug für `replicas: n` und ein
HorizontalPodAutoscaler.

---

## Aufräumen (erst nach der Abnahme)

```bash
kubectl delete namespace food-delivery
# Cluster teko-k8s bleibt fuer Block 4 bestehen.
```
