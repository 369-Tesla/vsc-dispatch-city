# Demo-Nachweise vom 21.09.2026

Aufnahmen aus dem laufenden lokalen Cluster `k3d-teko-k8s`.

| Schritt | Nachweis | Sichtbares Ergebnis |
| --- | --- | --- |
| 1 | [Dashboard: Stadt](01-dashboard-stadt.jpg) | Verteilte Simulation, Bestellungen, Lieferungen und Live-Events |
| 2 | [Dashboard: System](02-dashboard-system.jpg) | Komponenten und Bereitschaft, PostgreSQL mit zwei Instanzen |
| 3 | [RabbitMQ: Übersicht](03-rabbitmq-uebersicht.jpg) | Aktive Nachrichtenübertragung und Acknowledgements |
| 4 | [RabbitMQ: Queues](04-rabbitmq-queues.jpg) | Restaurant-, Projektions- und Live-Queues sowie `food.dead` |
| 5 | [RabbitMQ: Exchanges](05-rabbitmq-exchanges.jpg) | Topic-Exchanges `food.events` und `food.dlx` |
| 6 | [CloudNativePG / PostgreSQL](06-postgresql.jpg) | Bereiter Primary/Standby-Cluster und gespeicherte Orders, Events und Idempotenzschlüssel |
| 7 | [Grafana Cloud](07-grafana-cloud.jpg) | Alle fünf Panels mit Daten: offene und gelieferte Bestellungen, bereite Pizza-Worker, Queue-Messwerte und Eventrate |

Der PostgreSQL-Screenshot zeigt die [unveränderte Befehlsausgabe](06-postgresql-ausgabe.txt)
in einer Browseransicht. Die Aufnahmen dokumentieren den laufenden Betrieb;
Failover-, Duplikat- und DLQ-Tests wurden dafür nicht erneut durchgeführt.

Das [Grafana-Cloud-Dashboard](https://bluechariot1986.grafana.net/d/dispatch-city-cloud/dispatch-city-betrieb-cloud)
zeigt die Anwendungs- und Betriebsdaten. Alloy überträgt nur die benötigten
Metriken, um die Nutzung des Free Plans zu reduzieren.

Geprüft wurden bereite Anwendungspods, Datenbankreplikation, Nachrichtenverarbeitung
und eine Bestellung bis zur Lieferung. Go-Tests, Frontend-Typecheck und
Produktionsbuild bestanden.
