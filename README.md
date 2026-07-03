# backend-gitops

Desired-state repo for the `backend` platform. ArgoCD watches this repo; nothing here is applied
by hand except the one-time bootstrap steps below.

## Layout

- `charts/service/` — one generic Helm chart reused by all 4 Node services.
- `charts/<service>/values.yaml` — per-service overrides (image, port, env, ingress). Not a chart
  itself; applied against `charts/service` via ArgoCD's multi-source `$values` reference.
- `infra/postgres`, `infra/rabbitmq`, `infra/ingress-nginx` — thin wrapper charts around the
  upstream Bitnami / ingress-nginx charts.
- `argocd/root-app.yaml` — app-of-apps root; apply this once, it manages everything else.
- `argocd/apps/*.yaml` — one ArgoCD `Application` per service + per infra component.
- `kind/kind-config.yaml` — local cluster definition (ingress-ready node, hostPort 80/443).
- `scripts/create-secrets.sh` — one-time Secret creation, never committed to git.

## Before first use

Replace `<github-user>` in `argocd/root-app.yaml` and every file under `argocd/apps/` with this
repo's actual GitHub owner/name once it's pushed. Replace `<dockerhub-user>` in
`charts/*/values.yaml` with the real Docker Hub namespace the CI pipeline pushes images to.

## Bootstrap order

```bash
# 1. Local cluster
kind create cluster --config kind/kind-config.yaml --name backend

# 2. Secrets (before anything tries to start)
./scripts/create-secrets.sh

# 3. Manual bring-up first (validates the charts before ArgoCD enters the picture)
helm dependency build infra/postgres && helm install postgres infra/postgres -n backend --create-namespace
helm dependency build infra/rabbitmq && helm install rabbitmq infra/rabbitmq -n backend
helm dependency build infra/ingress-nginx && helm install ingress-nginx infra/ingress-nginx -n ingress-nginx --create-namespace
helm install api-gateway charts/service -n backend -f charts/api-gateway/values.yaml
helm install auth-service charts/service -n backend -f charts/auth-service/values.yaml
helm install product-service charts/service -n backend -f charts/product-service/values.yaml
helm install orders-service charts/service -n backend -f charts/orders-service/values.yaml

# 4. Verify
echo "127.0.0.1 api.local.test" | sudo tee -a /etc/hosts
curl http://api.local.test/health/ready

# 5. Once confirmed, hand it to ArgoCD instead
helm uninstall api-gateway auth-service product-service orders-service postgres rabbitmq -n backend
helm uninstall ingress-nginx -n ingress-nginx
kubectl apply -f argocd/root-app.yaml
```

## Notes

- Postgres's in-cluster service name is `postgres-postgresql` (Bitnami chart doesn't collapse the
  release name), RabbitMQ's is just `rabbitmq` (it does). `scripts/create-secrets.sh` already
  accounts for this when building `DATABASE_URL`/`RABBITMQ_URL`.
- All charts here were `helm lint`ed and `helm template`d successfully, including dependency builds
  against the live Bitnami/ingress-nginx chart repos.

## Image tags

CI (`backend` repo's `cd.yml`) bumps `image.tag` in `charts/<service>/values.yaml` on every push to
`main` and pushes the commit here directly. ArgoCD's automated sync (`prune: true, selfHeal: true`)
picks it up and rolls the Deployment. No manual `kubectl` needed after bootstrap.
