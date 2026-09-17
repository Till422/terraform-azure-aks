# Azure AKS Platform — Terraform

Infrastructure für eine containerisierte Plattform auf Azure. Zwei Umgebungen, wiederverwendbare Module, vollständige CI/CD-Automatisierung. Dazu eine lokale Übungsumgebung auf Basis von [kind](https://kind.sigs.k8s.io/), die dieselbe Struktur ohne Cloud-Kosten nachbildet.

---

## Aufbau

```
.
├── bootstrap/            # Erzeugt das Remote-Backend (einmalig)
├── modules/
│   ├── network/          # VNet, Subnets, NSG
│   └── aks/              # Cluster, Node Pools, Identity, ACR-Anbindung
├── envs/
│   ├── dev/              # Free-SKU, kleine Node Pools, 30 Tage Logs
│   └── prod/             # Standard-SKU (SLA), 3+ Nodes, 90 Tage Logs
├── local/                # kind-Cluster, gleiche Struktur ohne Cloud
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
| **`count` nie aus Laufzeitwerten ableiten** | Terraform baut den Abhängigkeitsgraph vor dem Apply. Struktur-Schalter gehören in eigene, statisch bekannte Variablen. |
| **Typisierte Variablen mit `validation`** | Fehler schlagen beim `plan` fehl (Sekunden) statt beim `apply` (Minuten). |
| **OIDC statt Client Secrets** | Keine langlebigen Credentials in Pipeline-Variablen. Pro Umgebung eigene Identität mit minimalen Rechten. |
| **`apply` mit gespeicherter Plan-Datei** | Angewendet wird exakt das Reviewte, nicht eine Neuberechnung. |
| **Azure CNI Overlay** | Pod-IPs außerhalb des VNet-Adressraums — spart IPs bei großen Clustern. |
| **`shared_access_key_enabled = false`** am State-Storage | Erzwingt Entra-ID-Auth; Storage-Keys existieren gar nicht erst. Der Provider braucht dafür `storage_use_azuread = true`. |
| **Rollenzuweisungen im Code, nicht per CLI** | Was per Klick entsteht, ist beim nächsten Aufbau weg. Entra ID braucht dabei bis zu zwei Minuten bis zur Wirksamkeit — abgefangen über `time_sleep`. |
| **`prevent_destroy` auf der Prod-RG** | Schutzschalter gegen ein versehentliches `destroy`. |
| **`ignore_changes` auf `node_count`** | Der Cluster Autoscaler verändert die Node-Zahl zur Laufzeit; Terraform darf das nicht zurückdrehen. |
| **`only_critical_addons_enabled`** | System-Pool bleibt den Cluster-Komponenten vorbehalten, Workloads laufen isoliert. |
| **Spot-Node-Pools (prod)** | Bis zu 90 % Kostenersparnis für unterbrechbare Lasten, per Taint abgesichert. In dev deaktiviert, weil das Low-Priority-Kontingent des Abonnements nicht ausreicht. |

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

Dauer etwa zehn Minuten, davon der Cluster allein sechs bis neun.

### 3. Cluster verbinden

```bash
az aks get-credentials --resource-group rg-demo-dev --name aks-demo-dev
kubelogin convert-kubeconfig -l azurecli
kubectl get nodes -L workload
```

Der Cluster nutzt Entra-ID-RBAC, deshalb ist
[kubelogin](https://github.com/Azure/kubelogin) nötig. Die im Code
angelegte Rollenzuweisung wird erst nach ein bis zwei Minuten wirksam;
bis dahin antwortet der Cluster mit `Forbidden`.

### 4. Workload ausrollen

```bash
kubectl apply -f ../../k8s/demo-app.yaml
kubectl get pods,svc,hpa,pdb,networkpolicy -n demo
```

### 5. Wieder abbauen

```bash
terraform destroy
```

Das Backend in `rg-tfstate` bleibt bestehen und kostet unter zwei Cent
im Monat.

---

## Lokale Übungsumgebung

Derselbe Terraform-Workflow gegen einen kind-Cluster in Docker — ohne
Azure-Abonnement und ohne Kosten. Der Cluster bildet die AKS-Struktur
nach: ein Control-Plane-Knoten als System-Pool, zwei Worker mit dem
Label `workload=apps` als User-Pool, ingress-nginx statt Azure Load
Balancer.

```bash
cd local
make up        # Cluster erzeugen und Workload ausrollen  (~3 Minuten)
make status    # Zustand aller Objekte
make load      # Last erzeugen und den HPA hochskalieren sehen
make down      # alles wieder entfernen
```

Details in [`local/README.md`](local/README.md).

---

## Verfügbarkeit in Azure prüfen

Ob eine VM-Größe in einer Region nutzbar ist, entscheiden **vier
voneinander unabhängige Prüfungen**. Die ersten beiden können grün sein,
während die dritte das Deployment kippt.

| # | Frage | Befehl |
|---|---|---|
| 1 | Darf das Abonnement in dieser Region etwas anlegen? | `az account list-locations -o table` |
| 2 | Ist die VM-Größe für das Abonnement freigegeben? | `az vm list-skus -l <region> --all` → Feld `restrictions` |
| 3 | Gibt es vCPU-Kontingent für **diese Familie**? | `az vm list-usage -l <region> -o table` |
| 4 | Reicht das regionale Gesamtkontingent? | dito, Zeile `Total Regional vCPUs` |

Verlässlich ist erst die Verknüpfung von Schritt 2 und 3 über das Feld
`family`: Eine SKU ohne Restriktion nützt nichts, wenn ihre Familie null
Kerne zugeteilt bekommen hat.

Analog gilt für die verfügbaren Kubernetes-Versionen:

```bash
az aks get-versions --location <region> -o table
```

Gepinnte Versionen sind richtig — sie altern aber und müssen
regelmäßig nachgezogen werden.

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

Ein erfolgreiches `terraform apply` ist dabei kein Erfolgskriterium:
Pod Security Standards und Admission Controller greifen erst beim
Erzeugen des Pods. Die Ressourcen können existieren, während kein
einziger Pod läuft — geprüft wird deshalb immer mit `kubectl get pods`.
