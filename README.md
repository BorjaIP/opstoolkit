<h1 align="center"> OpsToolkit </h1>

<h3 align="center"> 🔮 Your all-in-one toolkit for DevOps, MLOps, and LLMOps workflows. </h3>

A personal collection of resources, tools, scripts, frameworks, libraries, or templates for DevOps and MLOps tasks.

## Table of Contents

- [Repository Structure](#repository-structure)
- [Quick Start](#quick-start)
  - [Docker Compose](#docker-compose)
  - [Devcontainers](#devcontainers)
  - [Kubernetes](#kubernetes)
  - [Istio](#istio)
  - [Scripts](#scripts)
  - [Git Hooks](#git-hooks)

## Repository Structure

```
opstoolkit/
├── devcontainer/          # VS Code dev containers
│   ├── cuda/              # CUDA GPU development
│   ├── go/                # Go development
│   ├── java/              # Java development
│   └── python/            # Python development
├── docker/                # Dockerfiles
│   ├── angular/           # Angular app
│   └── python/            # Python app (single & multi-stage)
├── docker-compose/        # Ready-to-use service stacks
│   ├── datahub/           # DataHub (Kafka, MySQL, Elasticsearch)
│   ├── firefox/           # Firefox GUI via VNC
│   ├── grafana_prometheus/# Grafana + Prometheus monitoring
│   ├── influxdb/          # InfluxDB time-series database
│   ├── jenkins_sonar/     # Jenkins CI + SonarQube
│   ├── kafka-ui/          # Redpanda Console for Kafka
│   ├── kali/              # Kali Linux + DVWA lab
│   ├── keycloak/          # Keycloak IAM + PostgreSQL
│   ├── mlflow/            # MLflow + MinIO + PostgreSQL
│   ├── n8n-postgres/      # n8n workflow automation
│   ├── open_metadata/     # OpenMetadata + OpenSearch
│   └── postgres/          # Standalone PostgreSQL 17.2
├── git/                   # Git configuration
│   └── .pre-commit-config.yaml
├── istio/                 # Istio service mesh configs
│   ├── gateway.yaml
│   ├── virtual-service.yaml
│   ├── destinationrule.yaml
│   └── service-entry.yaml
├── k8s/                   # Kubernetes utility pods
│   ├── busybox.yaml
│   └── psql-client.yaml
└── scripts/               # Shell scripts
    ├── k8s-connectivity-check.sh
    └── tunnel.sh
```

## Quick Start

### Docker Compose

Each stack under `docker-compose/` is self-contained. Pick a service and run:

```bash
# Example: start Grafana + Prometheus
cd docker-compose/grafana_prometheus
docker compose up -d

# Grafana  → http://localhost:3000
# Prometheus → http://localhost:9090
```

| Stack | Services | Main Ports |
|-------|----------|------------|
| `datahub` | Kafka, Zookeeper, MySQL, Elasticsearch, DataHub GMS & Frontend | `9002` (UI), `8090` (API) |
| `firefox` | Firefox via VNC | `3000`, `3001` |
| `grafana_prometheus` | Grafana, Prometheus | `3000`, `9090` |
| `influxdb` | InfluxDB | `8086` |
| `jenkins_sonar` | Jenkins, SonarQube | `8080` (Jenkins), `9000` (Sonar) |
| `kafka-ui` | Redpanda Console | host network |
| `kali` | Kali Linux + DVWA | `3000`, `3001` |
| `keycloak` | Keycloak, PostgreSQL | `8080` (Keycloak), `5432` |
| `mlflow` | MLflow, MinIO, PostgreSQL | `5001` (MLflow), `9001` (MinIO) |
| `n8n-postgres` | n8n, PostgreSQL | `5678` |
| `open_metadata` | OpenMetadata, OpenSearch, PostgreSQL, Airflow | `8585` (UI), `8080` (Airflow) |
| `postgres` | PostgreSQL 17.2 | `5432` |

### Devcontainers

Open any devcontainer folder in VS Code to get a pre-configured development environment:

```bash
# 1. Open the desired devcontainer config in VS Code
code devcontainer/python/

# 2. VS Code will prompt: "Reopen in Container" → click it
#    Or use the command palette: Dev Containers: Reopen in Container
```

Available environments: **CUDA**, **Go**, **Java**, **Python**.

### Kubernetes

Apply utility pods for debugging inside a cluster:

```bash
# Deploy a busybox pod for network debugging
kubectl apply -f k8s/busybox.yaml

# Deploy a psql client to connect to in-cluster databases
kubectl apply -f k8s/psql-client.yaml
```

### Istio

Apply Istio traffic management resources:

```bash
kubectl apply -f istio/gateway.yaml
kubectl apply -f istio/virtual-service.yaml
kubectl apply -f istio/destinationrule.yaml
kubectl apply -f istio/service-entry.yaml
```

### Scripts

```bash
# Check Kubernetes cluster connectivity
./scripts/k8s-connectivity-check.sh

# Set up a tunnel / port-forward
./scripts/tunnel.sh
```

### Git Hooks

Copy the pre-commit config to your project:

```bash
cp git/.pre-commit-config.yaml /path/to/your/project/
pre-commit install
```
