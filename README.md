# Azure AKS Platform — Terraform Referenzprojekt

Produktionsnahe Infrastructure-as-Code-Referenz für eine containerisierte
Plattform auf Azure. Zwei Umgebungen, wiederverwendbare Module, vollständige
CI/CD-Automatisierung — ohne ein einziges langlebiges Secret.

---

## Überblick

```
┌─────────────────────────────────────────────────────────────┐
│  Git Repository                                             │
│    modules/  ──▶  wiederverwendbar, versioniert             │
│    envs/     ──▶  dev + prod, getrennte States              │
└────────────────────────┬────────────────────────────────────┘
                         │  Merge Request
                         ▼
┌─────────────────────────────────────────────────────────────┐
│  CI/CD  (GitLab CI  ·  Azure DevOps)                        │
│    fmt → validate → tflint → checkov → plan                 │
│    plan als Artefakt  ──▶  Review  ──▶  apply               │
│    Auth: OIDC / Workload Identity Federation                │
└────────────────────────┬────────────────────────────────────┘
                         │  terraform apply
                         ▼
┌─────────────────────────────────────────────────────────────┐
│  Azure                                                      │
│    VNet + Subnets + NSG (Default-Deny)                      │
│    AKS  ·  Azure CNI Overlay  ·  Cilium NetworkPolicy       │
│         ·  System-Pool + User-Pools (Spot, Autoscaling)     │
│         ·  Workload Identity (OIDC)                         │
│         ·  Key Vault CSI Driver                             │
│    ACR (RBAC-Pull, kein Admin-Passwort)                     │
│    Log Analytics + Container Insights                       │
└─────────────────────────────────────────────────────────────┘
```

---

## Aufbau

```
.
├── bootstrap/            # Erzeugt das Remote-Backend (einmalig)
├── modules/
│   ├── network/          # VNet, Subnets, NSG
│   └── aks/              # Cluster, Node Pools, Identity, ACR-Anbindung
├── envs/
│   ├── dev/              # Free-SKU, Spot-Nodes, 30 Tage Logs
│   └── prod/             # Standard-SKU (SLA), 3+ Nodes, 90 Tage Logs
├── k8s/                  # Beispiel-Workload zum Funktionsnachweis
├── .gitlab-ci.yml        # Pipeline-Variante A
└── azure-pipelines.yml   # Pipeline-Variante B
```

---

## Umgesetzte Entscheidungen

| Entscheidung | Begründung |
|---|---|
| **Getrennte Ordner statt Workspaces** | dev und prod unterscheiden sich strukturell. Ordner bleiben lesbar; Workspaces erzwingen Bedingungslogik im Code. |
| **Ein State pro Umgebung** | Begrenzt den Blast Radius und hält `plan` schnell. |
| **`for_each` statt `count`** | Key-basierte Adressierung. Das Entfernen eines Subnetzes zerstört nicht alle nachfolgenden. |
| **Typisierte Variablen mit `validation`** | Fehler schlagen beim `plan` fehl (Sekunden) statt beim `apply` (Minuten). |
| **OIDC statt Client Secrets** | Keine langlebigen Credentials in Pipeline-Variablen. Pro Umgebung eigene Identität mit minimalen Rechten. |
| **`apply` mit gespeicherter Plan-Datei** | Angewendet wird exakt das Reviewte, nicht eine Neuberechnung. |
| **Azure CNI Overlay** | Pod-IPs außerhalb des VNet-Adressraums — spart IPs bei großen Clustern. |
| **`shared_access_key_enabled = false`** am State-Storage | Erzwingt Entra-ID-Auth; Storage-Keys existieren gar nicht erst. |
| **`prevent_destroy` auf der Prod-RG** | Schutzschalter gegen ein versehentliches `destroy`. |
| **`ignore_changes` auf `node_count`** | Der Cluster Autoscaler verändert die Node-Zahl zur Laufzeit; Terraform darf das nicht zurückdrehen. |
| **`only_critical_addons_enabled`** | System-Pool bleibt den Cluster-Komponenten vorbehalten, Workloads laufen isoliert. |
| **Spot-Node-Pools** | Bis zu 90 % Kostenersparnis für unterbrechbare Lasten, per Taint abgesichert. |

---

## Inbetriebnahme

### 1. Backend erzeugen (einmalig)

```bash
az login
cd bootstrap
terraform init
terraform apply
```

Der Output enthält den fertigen Backend-Block. Den `storage_account_name`
in `envs/dev/backend.tf` und `envs/prod/backend.tf` statt `REPLACE_ME`
eintragen.

### 2. Dev-Umgebung deployen

```bash
cd envs/dev
terraform init
terraform plan -out=tf.plan
terraform apply tf.plan
```

### 3. Cluster verbinden und Workload deployen

```bash
az aks get-credentials --resource-group rg-demo-dev --name aks-demo-dev
kubectl apply -f ../../k8s/demo-app.yaml
kubectl get pods -n demo -w
```

### 4. Wieder abbauen

```bash
terraform destroy
```

---

## Kosten

Die Dev-Umgebung ist bewusst auf Minimalkosten ausgelegt: AKS Free-Tier
(Control Plane kostenlos), ein `Standard_B2s`-Node im System-Pool, Spot-Nodes
im App-Pool, ACR Basic, 30 Tage Log-Aufbewahrung.

Größenordnung: **rund 60–80 € pro Monat bei Dauerbetrieb.** Für Lernzwecke
lohnt sich `terraform destroy` nach jeder Sitzung — der Wiederaufbau dauert
etwa 8 Minuten und kostet dann nur Cent-Beträge.

Die Prod-Definition ist als Referenz gedacht und sollte nicht dauerhaft
laufen (Standard-SKU, ACR Premium, 3× D4s_v5).

---

## Qualitätssicherung

| Werkzeug | Prüft |
|---|---|
| `terraform fmt -check` | Einheitliche Formatierung |
| `terraform validate` | Syntax, Typen, Referenzen |
| `tflint` | Ungültige Instance-Typen, ungenutzte Variablen, Provider-Regeln |
| `checkov` | Security-Policies: offene NSGs, fehlende Verschlüsselung, Public Access |

Alle vier laufen bei jedem Merge Request, bevor überhaupt ein `plan`
gegen Azure gestartet wird.

---

## Bewusst nicht enthalten

Ehrlichkeit über Grenzen gehört zu einer Referenz dazu:

- **Private Endpoints / privater API-Server** — im Übungs-Setup wäre der
  Cluster dann nur noch über Bastion oder VPN erreichbar.
- **Ingress-Controller und Zertifikate** — gehören in einen eigenen
  App-State bzw. nach GitOps (ArgoCD/Flux), nicht in den Plattform-State.
- **Availability Zones** — in `germanywestcentral` verfügbar, für die
  Dev-Umgebung mit einem Node aber sinnlos.
- **Backup/Restore (Velero)** — der logische nächste Schritt für den
  Disaster-Recovery-Teil.
