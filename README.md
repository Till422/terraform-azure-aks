# Azure AKS Platform — Terraform

Infrastructure für eine containerisierte Plattform auf Azure. Zwei Umgebungen, wiederverwendbare Module, vollständige CI/CD-Automatisierung.

---




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


