# Lokale Übungsumgebung

Derselbe Terraform-Workflow wie in `envs/dev`, nur gegen einen
[kind](https://kind.sigs.k8s.io/)-Cluster in Docker statt gegen Azure.
**Kosten: keine.** Der Cluster läuft auf deinem Rechner.

## Wozu

Der Azure-Teil des Projekts braucht ein Abonnement mit ausreichendem
VM-Kontingent. Der Kubernetes-Teil braucht das nicht — Deployments, Probes,
Autoscaling, Disruption Budgets und Troubleshooting lassen sich lokal
genauso üben und vorführen.

## Was der Cluster nachbildet

| AKS | Hier |
|---|---|
| System-Node-Pool | Control-Plane-Knoten |
| User-Pool `apps` | zwei Worker mit Label `workload=apps` |
| Azure Load Balancer | ingress-nginx auf Port 8080 |
| Metrics (vorinstalliert) | metrics-server per Helm |

Die `nodeSelector`-Regeln des Workloads sind identisch — der Code wandert
ohne Änderung zwischen beiden Welten.

## Voraussetzungen

- Docker (Docker Desktop mit aktivierter WSL-Integration oder Docker Engine)
- `kind`, `kubectl`, `terraform`, `helm`

## Nutzung

```bash
make up        # Cluster erzeugen und Workload ausrollen  (~3 Minuten)
make status    # Zustand aller Objekte
make load      # Last erzeugen und den HPA hochskalieren sehen
make down      # alles wieder entfernen
```

Danach erreichbar unter <http://localhost:8080>.

## Den Autoscaler beobachten

In einem Terminal Last erzeugen:

```bash
make load
```

In einem zweiten zusehen:

```bash
kubectl get hpa,pods -n demo -w
```

Bei über 70 % CPU-Auslastung erhöht der HPA die Replicas bis maximal zehn.
Das ist der sichtbare Beweis, dass Requests, Metrics-Server und HPA
zusammenspielen.

## Troubleshooting üben

```bash
kubectl describe pod <name> -n demo      # Abschnitt "Events" lesen
kubectl logs -n demo -l app=demo-app     # Logs aller Replicas
kubectl get events -n demo --sort-by=.lastTimestamp
```

Ein Pod auf `Pending` bedeutet fast immer: kein Knoten erfüllt die
Bedingungen — falscher `nodeSelector`, zu hohe Requests oder ein Taint
ohne passende Toleration.
