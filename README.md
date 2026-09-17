# Azure AKS Platform — Terraform

Infrastructure für eine containerisierte Plattform auf Azure. Zwei Umgebungen, wiederverwendbare Module, CI/CD-Pipelines für Azure DevOps und GitLab. Dazu eine lokale Übungsumgebung auf Basis von [kind](https://kind.sigs.k8s.io/), die dieselbe Struktur ohne Cloud-Kosten nachbildet.

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
├── .gitlab-ci.yml
└── azure-pipelines.yml
```

---

## Umgesetzte Entscheidungen

| Entscheidung | Begründung |
|---|---|
| **Getrennte Ordner statt Workspaces**, ein State pro Umgebung | dev und prod unterscheiden sich strukturell. Begrenzt den Blast Radius und hält `plan` schnell. |
| **`for_each` statt `count`** | Key-basierte Adressierung. Das Entfernen eines Subnetzes zerstört nicht alle nachfolgenden. |
| **`count` nie aus Laufzeitwerten** | Terraform baut den Abhängigkeitsgraph vor dem Apply. Struktur-Schalter gehören in statisch bekannte Variablen. |
| **OIDC statt Client Secrets** | Keine langlebigen Credentials in Pipeline-Variablen. Pro Umgebung eigene Identität mit minimalen Rechten. |
| **`apply` mit gespeicherter Plan-Datei** | Angewendet wird exakt das Reviewte, nicht eine Neuberechnung. |
| **Azure CNI Overlay** | Pod-IPs außerhalb des VNet-Adressraums — spart IPs bei großen Clustern. |
| **`shared_access_key_enabled = false`** am State-Storage | Erzwingt Entra-ID-Auth. Der Provider braucht dafür `storage_use_azuread = true`. |
| **Rollenzuweisungen im Code, nicht per CLI** | Was per Klick entsteht, ist beim nächsten Aufbau weg. Entra ID braucht bis zu zwei Minuten bis zur Wirksamkeit — abgefangen über `time_sleep`. |
| **`ignore_changes` auf `node_count`** | Der Cluster Autoscaler verändert die Node-Zahl zur Laufzeit; Terraform darf das nicht zurückdrehen. |

---

## Inbetriebnahme

```bash
# 1. Backend erzeugen (einmalig). Der Output nennt den Storage-Account-Namen,
#    der in envs/*/backend.tf statt REPLACE_ME einzutragen ist.
az login && cd bootstrap && terraform init && terraform apply

# 2. Dev-Umgebung deployen (~10 Minuten, davon der Cluster 6-9)
cd ../envs/dev && terraform init && terraform plan -out=tf.plan
terraform apply tf.plan

# 3. Verbinden. Der Cluster nutzt Entra-ID-RBAC, deshalb kubelogin.
#    Die Rollenzuweisung wirkt erst nach 1-2 Minuten, bis dahin: Forbidden.
az aks get-credentials --resource-group rg-demo-dev --name aks-demo-dev
kubelogin convert-kubeconfig -l azurecli
kubectl get nodes -L workload

# 4. Workload ausrollen
kubectl apply -f ../../k8s/demo-app.yaml
kubectl get pods,svc,hpa,pdb,networkpolicy -n demo

# 5. Abbauen. Das Backend in rg-tfstate bleibt bestehen (< 2 ct/Monat).
terraform destroy
```

---

## Lokale Übungsumgebung

Derselbe Workflow gegen einen kind-Cluster in Docker — ohne Abonnement, ohne Kosten. Control-Plane als System-Pool, zwei Worker mit `workload=apps` als User-Pool, ingress-nginx statt Azure Load Balancer.

```bash
cd local
make up      # Cluster erzeugen und ausrollen (~3 Minuten)
make load    # Last erzeugen und den HPA hochskalieren sehen
make down
```

Details in [`local/README.md`](local/README.md).

---

## Verfügbarkeit in Azure prüfen

Ob eine VM-Größe nutzbar ist, entscheiden **vier unabhängige Prüfungen**. Die ersten beiden können grün sein, während die dritte das Deployment kippt.

| # | Frage | Befehl |
|---|---|---|
| 1 | Darf das Abo in dieser Region etwas anlegen? | `az account list-locations -o table` |
| 2 | Ist die VM-Größe freigegeben? | `az vm list-skus -l <region> --all` → `restrictions` |
| 3 | Gibt es Kontingent für **diese Familie**? | `az vm list-usage -l <region> -o table` |
| 4 | Reicht das regionale Gesamtkontingent? | dito, Zeile `Total Regional vCPUs` |

Verlässlich ist erst die Verknüpfung von 2 und 3 über das Feld `family`: Eine SKU ohne Restriktion nützt nichts, wenn ihre Familie null Kerne zugeteilt bekommen hat. Analog für Versionen: `az aks get-versions --location <region>`.

---

## Qualitätssicherung

`terraform fmt -check`, `terraform validate`, `tflint` und `checkov` laufen bei jedem Merge Request, bevor ein `plan` gegen Azure startet.

Ein erfolgreiches `apply` ist dabei kein Erfolgskriterium: Pod Security Standards greifen erst beim Erzeugen des Pods. Die Ressourcen können existieren, während kein einziger Pod läuft — geprüft wird deshalb immer mit `kubectl get pods`.
