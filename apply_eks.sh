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
              -f ./k8s_infra/client_deployment.yaml -f ./k8s_infra/client_service.yaml 


helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace

helm repo add grafana-community https://grafana-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

helm upgrade --install loki grafana-community/loki -n monitoring \
  -f monitoring/loki-values.yaml --wait --timeout 5m

helm upgrade --install alloy grafana/alloy -n monitoring \
  -f monitoring/alloy-values.yaml

kubectl apply -f monitoring/loki-datasource.yaml

helm repo add jetstack https://charts.jetstack.io && helm repo update
helm upgrade --install cert-manager jetstack/cert-manager \
     -n cert-manager --create-namespace --set crds.enabled=true --wait

kubectl apply -f ./k8s_infra_not_for_pipeline/cluster-issuer.yaml \
              -f ./k8s_infra/ingress-tls.yaml