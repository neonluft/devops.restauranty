# Security

This document summarizes how Restauranty handles secrets, authentication, network exposure,
TLS, access to AWS, and user data, plus the known limitations.

## Secrets and environment variables

- Each backend reads its configuration from environment variables: `SECRET` (JWT), `MONGODB_URI`,
  `CLOUD_NAME`, `CLOUD_API_KEY`, `CLOUD_API_SECRET`, `PORT`.
- **Local development:** values live in a per-service `.env` file that is listed in `.gitignore`
  and `.dockerignore`, so it is neither committed nor copied into images.
- **Kubernetes:** values live in the Secret `restauranty-secrets` and are injected with
  `secretKeyRef`. The Secret is created outside the repository (`kubectl create secret ...`);
  only a placeholder template is versioned.
- **CI/CD:** the Docker Hub token is a GitHub Actions secret. AWS access uses no stored keys (see IAM).
- The JWT `SECRET` is generated randomly (`openssl rand -base64 48`) and is identical across the
  three backends. Rotating it invalidates existing tokens.
- Docker images contain no secrets; they are supplied at runtime.

## Authentication and token validation

- The `auth` service handles sign up and login and issues JWTs signed with `SECRET`.
- `discounts` and `items` read the token from the request headers and verify it with the same
  secret before serving protected routes (middleware based on `express-jwt`). Requests without a
  valid token are rejected with `401`.
- Containers run as a non-root user (`USER node` in the backend images).

## Network security

- **Only the ingress is public.** All Services are `ClusterIP`; MongoDB is only reachable inside
  the cluster. The single public entry point is the NLB in front of ingress-nginx.
- Grafana is not exposed; it is accessed with `kubectl port-forward`.
- Path-based routing at the ingress means the frontend needs only one origin.
- NetworkPolicies (default-deny, allow ingress controller to services, allow only the three
  backends to MongoDB) are **not implemented yet**; see limitations.

## TLS / HTTPS

- HTTPS is terminated at ingress-nginx with a certificate issued and renewed automatically by
  **cert-manager** (Let's Encrypt, HTTP-01 challenge). HTTP is redirected to HTTPS.
- The domain is managed in Route 53 and updated to the new load balancer by `bootstrap.sh`.
- Traffic between the ingress and the pods, and between services and MongoDB, is plain HTTP/TCP
  inside the cluster network.

## IAM and access control

- **GitHub Actions to AWS:** OIDC federation. The workflow assumes an IAM role with short-lived
  credentials; the role's trust policy is restricted to this repository (and branch/environment).
- **Role to cluster:** the role is mapped into EKS with an **access entry** managed in Terraform,
  so it can deploy manifests. It can be scoped down to the `default` namespace with the
  `AmazonEKSEditPolicy` access policy.
- The EBS CSI driver and the nodes use their own IAM roles with AWS managed policies.

## Data and compliance

- The auth service stores user account data (such as name/email and credentials) in MongoDB, so
  the application handles personal data and GDPR considerations apply.
- **Encryption in transit:** HTTPS from the browser to the ingress.
- **Encryption at rest:** MongoDB data is stored on an EBS volume; encryption is provided by
  EBS (set `encrypted: "true"` in the StorageClass, or enable default EBS encryption for the account).
- **Data location:** a single AWS region (`us-east-1`). Images are stored on Cloudinary.
- **Retention:** application logs are kept for 7 days in Loki and should not contain secrets or
  personal data; services must not log credentials or tokens.

## Known limitations and next steps

- No NetworkPolicies yet (requires enabling network policy support in the VPC CNI add-on).
- MongoDB runs without authentication; access is limited by the cluster network only.
- Kubernetes Secrets are base64-encoded, not encrypted, unless EKS envelope encryption is enabled.
- TLS ends at the ingress; in-cluster traffic is unencrypted.
- The pipeline role has broad access to the cluster; it can be restricted to a single namespace.
- No automated database backups (manual `mongodump`); a managed database (e.g. MongoDB Atlas)
  would remove that gap.
- Test coverage is minimal and there is no alerting.