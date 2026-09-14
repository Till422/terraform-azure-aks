# Lokale Uebungsumgebung - keine Cloud, keine Kosten.
# Nutzung:  make up | make status | make load | make down

CLUSTER := demo

.PHONY: help up cluster deploy status load logs down clean

help:
	@echo "make up      - Cluster erzeugen und Workload ausrollen"
	@echo "make status  - Zustand aller Objekte anzeigen"
	@echo "make load    - Last erzeugen, um den HPA hochskalieren zu sehen"
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
	@kubectl get pods,svc,hpa,pdb,ingress -n demo -o wide
	@echo
	@echo "Im Browser:  http://localhost:8080"

load:
	@echo "Erzeugt Last. Mit Strg+C beenden, dann HPA beobachten:"
	@echo "  kubectl get hpa -n demo -w"
	kubectl run loadgen --rm -it --restart=Never --image=busybox:1.36 -n demo -- \
	  sh -c "while true; do wget -q -O- http://demo-app.demo.svc.cluster.local >/dev/null; done"

logs:
	kubectl logs -n demo -l app=demo-app -f --tail=50

down:
	-terraform destroy -auto-approve
	kind delete cluster --name $(CLUSTER)

clean: down
	rm -rf .terraform terraform.tfstate*
