#!/usr/bin/env bash
set -euo pipefail

helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-type"=nlb \
  --wait --timeout=5m

kubectl apply -f ./k8s_infra/secrets.yaml
kubectl apply -f ./k8s_infra/mongo_service.yaml -f ./k8s_infra/mongo_statefulset.yaml
kubectl rollout status statefulset/mongo
kubectl apply -f ./k8s_infra/auth_deployment.yaml -f ./k8s_infra/auth_service.yaml \
              -f ./k8s_infra/discount_deployment.yaml -f ./k8s_infra/discount_service.yaml \
              -f ./k8s_infra/items_deployment.yaml -f ./k8s_infra/items_service.yaml \
              -f ./k8s_infra/client_deployment.yaml -f ./k8s_infra/client_service.yaml \
              -f ./k8s_infra/ingress.yaml

