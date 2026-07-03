#!/usr/bin/env bash
# One-time (or re-run-to-rotate) creation of K8s Secrets for the local kind cluster.
# Never committed to git — this script only ever talks to the cluster, and generated
# key material is cached under .secrets/ which is gitignored.
#
# Usage: ./scripts/create-secrets.sh
set -euo pipefail

NAMESPACE=backend
SECRETS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/.secrets"
mkdir -p "$SECRETS_DIR"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# ── Postgres / RabbitMQ admin passwords ─────────────────────────────────
: "${POSTGRES_PASSWORD:=$(openssl rand -base64 24)}"
: "${RABBITMQ_PASSWORD:=$(openssl rand -base64 24)}"

kubectl create secret generic postgres-secrets -n "$NAMESPACE" \
  --from-literal=postgres-password="$POSTGRES_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic rabbitmq-secrets -n "$NAMESPACE" \
  --from-literal=rabbitmq-password="$RABBITMQ_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -

DATABASE_HOST="postgres.${NAMESPACE}.svc.cluster.local"
RABBITMQ_URL="amqp://rabbit:${RABBITMQ_PASSWORD}@rabbitmq.${NAMESPACE}.svc.cluster.local:5672"

# ── JWT RS256 keypair (generated once, cached locally, never committed) ─
if [ ! -f "$SECRETS_DIR/jwt-private.pem" ]; then
  openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$SECRETS_DIR/jwt-private.pem"
  openssl rsa -pubout -in "$SECRETS_DIR/jwt-private.pem" -out "$SECRETS_DIR/jwt-public.pem"
fi
JWT_PRIVATE_KEY="$(cat "$SECRETS_DIR/jwt-private.pem")"
JWT_PUBLIC_KEY="$(cat "$SECRETS_DIR/jwt-public.pem")"

# ── Per-service secrets (DATABASE_URL, RABBITMQ_URL, JWT keys) ─────────
kubectl create secret generic auth-service-secrets -n "$NAMESPACE" \
  --from-literal=DATABASE_URL="postgresql://postgres:${POSTGRES_PASSWORD}@${DATABASE_HOST}:5432/auth_db" \
  --from-literal=RABBITMQ_URL="$RABBITMQ_URL" \
  --from-literal=JWT_PRIVATE_KEY="$JWT_PRIVATE_KEY" \
  --from-literal=JWT_PUBLIC_KEY="$JWT_PUBLIC_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic product-service-secrets -n "$NAMESPACE" \
  --from-literal=DATABASE_URL="postgresql://postgres:${POSTGRES_PASSWORD}@${DATABASE_HOST}:5432/product_db" \
  --from-literal=RABBITMQ_URL="$RABBITMQ_URL" \
  --from-literal=JWT_PUBLIC_KEY="$JWT_PUBLIC_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic orders-service-secrets -n "$NAMESPACE" \
  --from-literal=DATABASE_URL="postgresql://postgres:${POSTGRES_PASSWORD}@${DATABASE_HOST}:5432/orders_db" \
  --from-literal=RABBITMQ_URL="$RABBITMQ_URL" \
  --from-literal=JWT_PUBLIC_KEY="$JWT_PUBLIC_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic api-gateway-secrets -n "$NAMESPACE" \
  --from-literal=JWT_PUBLIC_KEY="$JWT_PUBLIC_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Secrets applied to namespace/$NAMESPACE. Postgres/RabbitMQ passwords and the JWT"
echo "keypair are cached under $SECRETS_DIR for reruns — back that directory up if you"
echo "need to reproduce this cluster later; it is gitignored and never pushed."
