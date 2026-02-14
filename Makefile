# ====================================================================================
# Killer Queen (KQ)
# ====================================================================================

KUBE_NAMESPACE 		?= kq
BACKUP_FILE     	:= db-dump.sql.gz

.PHONY: help
help:
	@echo "------------------------------------------------------------------"
	@echo " Killer Queen (KQ) - Available Commands"
	@echo "------------------------------------------------------------------"
	@echo "Setup Commands:"
	@echo "  make setup             - (One-Time) Create namespace and secrets."
	@echo "  make create-secrets    - (One-Time) Interactively create K8s secrets."
	@echo ""
	@echo "Core Pipeline:"
	@echo "  make deploy            - Deploy all services via Kustomize."
	@echo "  make dry-run           - Render and validate manifests without applying."
	@echo ""
	@echo "Operational Commands:"
	@echo "  make restart           - Perform a rolling restart of all deployments."
	@echo "  make backup-db         - Create a compressed SQL dump of PostgreSQL."
	@echo "  make status            - Show current status of all resources."
	@echo "  make cleanup           - Remove all deployed resources."
	@echo "------------------------------------------------------------------"

.PHONY: setup
setup:
	@kubectl create namespace $(KUBE_NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -

.PHONY: create-secrets
create-secrets: setup
	@echo "Creating KQ secrets..."
	@echo "Enter PostgreSQL password:"
	@read -s PG_PASS; \
	kubectl create secret generic kq-postgres-credentials \
		--from-literal=POSTGRES_PASSWORD=$$PG_PASS \
		--namespace=$(KUBE_NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
	@echo ""
	@echo "Enter Penpot secrets (DB password, secret key, websockets key, SMTP password):"
	@read -s PP_DB; read -s PP_SEC; read -s PP_WS; read -s PP_SMTP; \
	kubectl create secret generic kq-penpot-secrets \
		--from-literal=PENPOT_DATABASE_PASSWORD=$$PP_DB \
		--from-literal=PENPOT_SECRET_KEY=$$PP_SEC \
		--from-literal=PENPOT_WEBSOCKETS_SECRET_KEY=$$PP_WS \
		--from-literal=PENPOT_SMTP_PASSWORD=$$PP_SMTP \
		--namespace=$(KUBE_NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
	@echo ""
	@echo "Enter Huly secrets (server secret, MinIO root password, CockroachDB password, Redpanda password):"
	@read -s H_SEC; read -s H_MINIO; read -s H_CR; read -s H_RP; \
	kubectl create secret generic kq-huly-secrets \
		--from-literal=SECRET=$$H_SEC \
		--from-literal=MINIO_ROOT_PASSWORD=$$H_MINIO \
		--from-literal=COCKROACH_PASSWORD=$$H_CR \
		--from-literal=REDPANDA_PASSWORD=$$H_RP \
		--namespace=$(KUBE_NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
	@echo "All secrets created."

.PHONY: deploy
deploy:
	@echo "Deploying application to Kubernetes namespace [$(KUBE_NAMESPACE)]"
	kustomize build k8s/ | kubectl apply -f -
	@echo "Deployment complete."

.PHONY: dry-run
dry-run:
	@echo "Validating manifests..."
	kustomize build k8s/ | kubectl apply --dry-run=client -f -

.PHONY: restart
restart:
	@echo "Performing rolling restart of all deployments in namespace [$(KUBE_NAMESPACE)]"
	@kubectl get deployments -n $(KUBE_NAMESPACE) -o name | while read deploy; do \
		echo "--> Restarting $$deploy"; \
		kubectl rollout restart $$deploy --namespace=$(KUBE_NAMESPACE); \
	done
	@echo "All deployments restarted."

.PHONY: backup-db
backup-db:
	@echo "Backing up postgres database to [$(BACKUP_FILE)]"
	@POSTGRES_POD=$$(kubectl get pods -n $(KUBE_NAMESPACE) -l app=postgres -o jsonpath='{.items[0].metadata.name}'); \
	if [ -z "$$POSTGRES_POD" ]; then \
		echo "Error: Could not find a running postgres pod."; \
		exit 1; \
	fi; \
	echo "--> Creating database dump inside pod: $$POSTGRES_POD"; \
	kubectl exec -n $(KUBE_NAMESPACE) $$POSTGRES_POD -- \
		sh -c "pg_dumpall -U bs | gzip > /tmp/dump.sql.gz"; \
	echo "--> Copying dump file to local machine"; \
	kubectl cp $(KUBE_NAMESPACE)/$$POSTGRES_POD:/tmp/dump.sql.gz $(BACKUP_FILE); \
	echo "--> Cleaning up dump file inside pod"; \
	kubectl exec -n $(KUBE_NAMESPACE) $$POSTGRES_POD -- rm /tmp/dump.sql.gz; \
	echo "Database backup complete: $(BACKUP_FILE)"

.PHONY: status
status:
	@echo "========================================="
	@echo "Status of namespace [$(KUBE_NAMESPACE)]"
	@echo "========================================="
	@echo ""
	@echo "DEPLOYMENTS & PODS:"
	@kubectl get deployments,pods -n $(KUBE_NAMESPACE) -o wide
	@echo ""
	@echo "SERVICES:"
	@kubectl get services -n $(KUBE_NAMESPACE) -o wide
	@echo ""
	@echo "INGRESS:"
	@kubectl get ingress -n $(KUBE_NAMESPACE) -o wide
	@echo ""
	@echo "PVCs:"
	@kubectl get pvc -n $(KUBE_NAMESPACE)
	@echo ""
	@echo "SECRETS:"
	@kubectl get secrets -n $(KUBE_NAMESPACE) | grep -v "default-token"
	@echo "========================================="

.PHONY: cleanup
cleanup:
	@echo "Cleaning up all resources in namespace [$(KUBE_NAMESPACE)]"
	kustomize build k8s/ | kubectl delete -f - --ignore-not-found=true
