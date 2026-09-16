# Lokale Uebungsumgebung - keine Cloud, keine Kosten.
# Nutzung:  make up | make status | make load | make down

CLUSTER := demo

# Der Namespace erzwingt den Pod Security Standard "restricted".
# Auch der Lastgenerator muss ihn erfuellen, sonst lehnt der
# Admission-Controller den Pod ab.
LOADGEN_OVERRIDES := {"apiVersion":"v1","spec":{"securityContext":{"runAsNonRoot":true,"runAsUser":65534,"seccompProfile":{"type":"RuntimeDefault"}},"containers":[{"name":"loadgen","image":"busybox:1.36","command":["sh","-c","while true; do wget -q -O- http://demo-app.demo.svc.cluster.local >/dev/null; done"],"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}}]}}

.PHONY: help up cluster deploy status watch load load-stop logs down clean

help:
	@echo "make up      - Cluster erzeugen und Workload ausrollen"
	@echo "make status  - Zustand aller Objekte anzeigen"
	@echo "make watch   - Zustand laufend beobachten (Strg+C beendet)"
	@echo "make load    - Last erzeugen, um den HPA hochskalieren zu sehen"
	@echo "make load-stop - Lastgenerator wieder entfernen"
	@echo "make logs    - Logs des Workloads folgen"
	@echo "make down    - Workload und Cluster entfernen"

up: cluster deploy status

cluster:
	@kind get clusters 2>/dev/null | grep -qx "$(CLUSTER)" \
	  && echo "Cluster '$(CLUSTER)' laeuft bereits." \
	  || kind create cluster --config kind-cluster.yaml
	@kubectl cluster-info --context kind-$(CLUSTER)

deploy:
	terraform init -input=false
	terraform apply -auto-approve
	@echo "Warte, bis alle Pods bereit sind..."
	@kubectl wait --for=condition=available --timeout=180s \
	  deployment/demo-app -n demo

status:
	@echo "--- Knoten ---"
	@kubectl get nodes -L workload
	@echo
	@echo "--- Workload ---"
	@kubectl get pods,svc,hpa,pdb,ingress -n demo
	@echo
	@echo "Im Browser:  http://localhost:8080"

# kubectl get -w beherrscht nur einen Ressourcentyp,
# deshalb watch mit einer kombinierten Abfrage.
watch:
	watch -n 2 kubectl get hpa,pods -n demo

load:
	@echo "Startet den Lastgenerator im Hintergrund."
	@echo "Beobachten: make watch   ·   Stoppen: make load-stop"
	kubectl run loadgen --restart=Never -n demo \
	  --image=busybox:1.36 \
	  --overrides='$(LOADGEN_OVERRIDES)'

load-stop:
	kubectl delete pod loadgen -n demo --ignore-not-found

logs:
	kubectl logs -n demo -l app=demo-app -f --tail=50

down:
	-terraform destroy -auto-approve
	kind delete cluster --name $(CLUSTER)

clean: down
	rm -rf .terraform terraform.tfstate*
