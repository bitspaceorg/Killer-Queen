# KQ: Killer Queen

Self-hosted infrastructure for BitSpace — Penpot (design) and Huly (project management) on Kubernetes.

## Services

| Service | Host | Description |
|---------|------|-------------|
| Penpot | `design.bitspace.org.in` | Open-source design tool (frontend, backend, exporter, redis) |
| Huly | `huly.bitspace.org.in` | Project management (CockroachDB, Elasticsearch, MinIO, Redpanda + app services) |
| PostgreSQL | internal | Shared database for Penpot |

## Prerequisites

- Kubernetes cluster with `kubectl` access
- [Nix](https://nixos.org/) (provides `kubectl` and `kustomize` via `nix develop`)
- cert-manager + nginx ingress controller deployed on the cluster
- MetalLB configured (`config/metallb.yaml` applied separately)

## Quick Start

```bash
# Enter dev shell
nix develop

# First-time setup: create namespace + secrets
make setup
make deploy

# Validate manifests without applying
make dry-run
```

## Commands

```
make setup           Create the kq namespace
make create-secrets  Interactively create K8s secrets via kubectl
make deploy          Deploy all services (kustomize build k8s/ | kubectl apply)
make dry-run         Render and validate manifests without applying
make restart         Rolling restart all deployments
make backup-db       Compressed pg_dumpall dump
make status          Show deployments, pods, services, ingress, PVCs, secrets
make cleanup         Tear down all resources
```

## Directory Structure

```
k8s/
  kustomization.yaml       # Lists all resources
  namespace.yaml
  secrets.yaml             # Secret values (stringData)
  cluster/issuer.yaml      # cert-manager ClusterIssuer
  ingress/rules.yaml       # design + huly hosts, TLS
  postgres/                # deployment, service, pvc, configmap (init SQL)
  penpot/                  # frontend, backend, exporter, redis, pvc
  huly/                    # cockroachdb, elasticsearch, minio, redpanda,
                           # nginx, front, transactor, account, collaborator,
                           # workspace, fulltext, stats, kvs, rekoni
```

## Secrets

| Secret | Keys |
|--------|------|
| `kq-postgres-credentials` | POSTGRES_PASSWORD |
| `kq-penpot-secrets` | PENPOT_DATABASE_PASSWORD, PENPOT_SECRET_KEY, PENPOT_WEBSOCKETS_SECRET_KEY, PENPOT_SMTP_PASSWORD |
| `kq-huly-secrets` | SECRET, MINIO_ROOT_PASSWORD, COCKROACH_PASSWORD, REDPANDA_PASSWORD |
