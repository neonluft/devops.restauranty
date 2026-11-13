# Restauranty

A restaurant web application made of three Node.js microservices and a React frontend, deployed
end to end with Docker, Kubernetes (AWS EKS), GitHub Actions, and a Prometheus/Grafana/Loki
observability stack. Security notes are in [SECURITY.md](SECURITY.md).

## Architecture

| Component | Path | Port | Purpose |
|---|---|---|---|
| `client` | `client/` | 3000 (dev) | React frontend |
| `auth` | `backend/auth/` | 3001 | Sign up, login, issues JWTs |
| `discounts` | `backend/discounts/` | 3002 | Campaigns and coupons |
| `items` | `backend/items/` | 3003 | Items, dietary info, orders |
| MongoDB | - | 27017 | Database (shared by the services) |
| Cloudinary | external | - | Image storage |

The browser only knows **one URL**. A reverse proxy (HAProxy locally, ingress-nginx on Kubernetes)
routes by path:

| Path | Target |
|---|---|
| `/api/auth/*` | auth |
| `/api/discounts/*` | discounts |
| `/api/items/*` | items |
| `/` | client |

The client calls relative paths (`/api/...`), so the same build works locally and in production.
The API calls are made by the browser, not by the frontend pod.

## Repository layout

```
backend/{auth,discounts,items}/   microservices (each with a Dockerfile)
client/                           React app (multi-stage Dockerfile)
haproxy.cfg                       local routing
k8s_infra/                        Kubernetes manifests (Deployments, Services, Mongo, Ingress, issuer)
monitoring/                       Helm values, Loki data source, Grafana dashboards
apply_eks.sh                      brings a fresh cluster to a working state
.github/workflows/ci-cd.yaml      CI/CD pipeline
```

## Environment variables

Never commit real values. Locally they go in a git-ignored `.env`; on Kubernetes they live in the
Secret `restauranty-secrets`.

| Variable | Used by | Description |
|---|---|---|
| `SECRET` | all backends | JWT signing/verification secret (must be identical in all three) |
| `MONGODB_URI` | all backends | e.g. `mongodb://127.0.0.1:27017/flor` locally, `mongodb://mongo:27017/flor` on Kubernetes |
| `CLOUD_NAME`, `CLOUD_API_KEY`, `CLOUD_API_SECRET` | all backends | Cloudinary credentials |
| `PORT` | all backends | 3001 / 3002 / 3003 |
| `REACT_APP_SERVER_URL` | client (build time) | Backend base URL. Empty in production (relative URLs), `http://localhost:80` for local dev |

Notes: `REACT_APP_*` values are baked into the JS bundle at build time. With `docker run --env-file`,
**do not use quotes** around values (Docker keeps them as part of the value).

## Local development (HAProxy)

```bash
# 1. MongoDB
docker run -d --name my-mongo -p 27017:27017 -v mongo-data:/data/db mongo:latest

# 2. Backends: create a .env in each service folder first, then in three terminals:
cd backend/auth      && npm install && npm start     # 3001
cd backend/discounts && npm install && npm start     # 3002
cd backend/items     && npm install && npm start     # 3003

# 3. Frontend
cd client && npm install && npm start                # 3000

# 4. Routing on port 80
haproxy -f haproxy.cfg
```

Open `http://localhost/`. HAProxy routes by path as described above.

## Tests

```bash
cd backend/<service> && npm test     # smoke test: server starts and answers HTTP (node --test)
cd client && npm test                # react-scripts test (no test files yet, passes with --passWithNoTests)
```

The same commands run in CI. Test coverage is intentionally minimal.

## Docker

```bash
docker build -t <dockerhub-user>/restauranty-auth      backend/auth
docker build -t <dockerhub-user>/restauranty-discounts backend/discounts
docker build -t <dockerhub-user>/restauranty-items     backend/items
docker build --build-arg REACT_APP_SERVER_URL="" -t <dockerhub-user>/restauranty-client client

docker run --rm -p 3001:3001 --env-file backend/auth/.env <dockerhub-user>/restauranty-auth
```

Inside a container, `127.0.0.1` is the container itself, so `MONGODB_URI` must point at a reachable
Mongo (a container name on a shared Docker network, or `host.docker.internal`). Build for
`--platform linux/amd64` if you build on an ARM machine and deploy to x86 nodes.

## Kubernetes (AWS EKS)

**Prerequisites:** an EKS cluster with the EBS CSI driver and a StorageClass, `kubectl`, `helm`,
`aws` CLI, `dig`, a Route 53 hosted zone, and access for the pipeline role (EKS access entry).

**One command for a fresh cluster:** set `DOMAIN` and `HOSTED_ZONE_ID` in `bootstrap.sh`, then:

```bash
kubectl apply -f k8s_infra/secrets.yaml   # not in git; see template below
./bootstrap.sh
```

The script installs, in order: ingress-nginx, cert-manager, the DNS record (Route 53) pointing at
the new load balancer, MongoDB, the four services, the certificate issuer and Ingress, then
Prometheus/Grafana, Loki, Alloy and the dashboards.

Create the Secret (values are examples):

```bash
kubectl create secret generic restauranty-secrets \
  --from-literal=SECRET="$(openssl rand -base64 48)" \
  --from-literal=MONGODB_URI='mongodb://mongo:27017/flor' \
  --from-literal=CLOUD_NAME=... --from-literal=CLOUD_API_KEY=... --from-literal=CLOUD_API_SECRET=...
```

Manifests: one Deployment + Service per component, a MongoDB StatefulSet with a PVC, and a single
Ingress (path routing, TLS from cert-manager and Let's Encrypt).

**Good to know**
- Rebuilding the cluster creates an **empty database**. Back up first:
  `kubectl exec mongo-0 -- mongodump --db flor --archive --gzip > backup.gz` and restore with
  `mongorestore --archive --gzip --drop`.
- If Mongo was down when the backends started, restart them:
  `kubectl rollout restart deployment/auth deployment/discounts deployment/items`.
- Let's Encrypt limits duplicate certificates; test with the staging issuer first.

## CI/CD

`.github/workflows/ci-cd.yaml` has three jobs:

| Job | Runs on | What it does |
|---|---|---|
| `ci` | every pull request and push | `npm ci`, build and test for the 4 components (in parallel) |
| `build-push` | push/merge to `main`, after CI | builds 4 images, pushes to Docker Hub (tag = commit SHA and `latest`) |
| `deploy` | after `build-push` | assumes an AWS role via OIDC, applies manifests, rolls out the new images, waits for health |

Configuration: repository **variables** `AWS_ROLE_ARN`, `AWS_REGION`, `EKS_CLUSTER_NAME`,
`DOCKERHUB_USERNAME`, and the **secret** `DOCKERHUB_TOKEN`. No AWS keys are stored.

## Viewing logs and metrics

**Logs (quick):**

```bash
kubectl logs -f deploy/auth          # also: discounts, items, client
kubectl logs -f mongo-0
```

**Grafana** (not public, use a port-forward):

```bash
kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80
kubectl get secret -n monitoring monitoring-grafana -o jsonpath='{.data.admin-password}' | base64 -d
```

Open `http://localhost:3000` and log in as `admin`. (From a remote VM, add an SSH tunnel:
`ssh -N -L 3000:localhost:3000 <user>@<vm>`.)

- **Metrics:** dashboard *Restauranty - Pods, Network, Storage & Namespaces* (CPU, network, volume
  usage, namespace load). Provided by Prometheus via kube-prometheus-stack.
- **Logs:** dashboard *Restauranty - Logging (Loki & Alloy)*, or **Explore → Loki** with queries
  such as `{app="auth"}` or `{namespace="default"} |~ "(?i)error"`.
- Dashboards are loaded automatically from ConfigMaps by `bootstrap.sh`; the JSON files are in
  `monitoring/` and can also be imported manually (Dashboards → Import).

Architecture: Alloy reads pod logs through the Kubernetes API and ships them to Loki (7-day
retention); Prometheus scrapes the kubelet and exporters; Grafana reads both.

## Troubleshooting notes

- Frontend calls `localhost` in production → `REACT_APP_SERVER_URL` was set at build time.
- `MongoParseError: Invalid scheme` with Docker → remove quotes from the `.env` values.
- `buffering timed out` in backend logs → restart the backend, Mongo was not reachable at startup.
- Pipeline: "provide credentials" → the pipeline role needs an EKS access entry on the new cluster.