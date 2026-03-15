# Status-Page Infrastructure

Production-grade AWS infrastructure for the open-source [Status-Page](https://github.com/Status-Page/Status-Page) application. Built for high availability, security, and cost efficiency.

**Yosef Migirov & Aviv Hanania**

## Architecture

Multi-AZ deployment on AWS EKS with automated failover, edge security, and Scale-to-Zero cost optimization.

```
Internet --> Route 53 (DNS Failover) --> AWS WAF --> ALB (HTTPS)
                                                       |
                 +-------------------------------------+------------------------------------+
                 |            AZ-a                      |            AZ-b                    |
                 |  NAT GW    EKS Nodes (Spot/ARM)      |  NAT GW    EKS Nodes (Spot/ARM)   |
                 |            - Web Pods (HPA)           |            - Web Pods (HPA)        |
                 |            - Worker Pods              |            - Worker Pods           |
                 +-------------------------------------+------------------------------------+
                                                       |
                              RDS Proxy --> RDS PostgreSQL Multi-AZ
                              ElastiCache Redis Multi-AZ
                                                       |
                              S3 (Static Assets)    S3 (Failover Page)
```

**Key design decisions:**
- **Graviton (ARM)** processors across compute and data layers for 20% cost reduction
- **Spot Instances** with diversified types (t4g.medium, t4g.small, m6g.medium) for ~70% compute savings
- **Scale-to-Zero** via EventBridge + Lambda shuts down compute and RDS outside business hours
- **RDS Proxy** for sub-second database failover and connection pooling
- **GitOps** with GitHub Actions (CI) and Argo CD (CD) for pull-based deployments
- **DNS Failover** to a static S3 page ensures the status page is reachable even during full outages

## Repository Structure

```
terraform/          AWS infrastructure (VPC, EKS, RDS, ElastiCache, WAF, Route 53)
k8s/                Kubernetes manifests (Deployments, Services, Ingress, HPA, Secrets)
docs/               Architecture documentation and cost estimation
```

The application source code lives in a [separate repository](https://github.com/avivhananiya/status-page-aviv-yosef-app) as a fork of the upstream project.

## Tech Stack

| Layer | Technology |
|---|---|
| Orchestration | Amazon EKS (Kubernetes 1.30) |
| Compute | EC2 Spot Instances (Graviton/ARM) |
| Database | RDS PostgreSQL 15 Multi-AZ + RDS Proxy |
| Cache & Queue | ElastiCache Redis Multi-AZ |
| Networking | VPC, ALB, Dual NAT Gateways, S3 Gateway Endpoint |
| Security | AWS WAF, ACM (TLS), Secrets Manager + CSI Driver, SSM Session Manager |
| CI/CD | GitHub Actions + Argo CD (GitOps) |
| IaC | Terraform (S3 backend + DynamoDB locking) |
| Observability | CloudWatch Agent (DaemonSet with FinOps log filtering) |
| Cost Automation | EventBridge + Lambda (Scale-to-Zero) |

## Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform >= 1.3.0
- kubectl
- Helm 3

## Getting Started

**1. Bootstrap the Terraform backend:**

```bash
cd terraform
./bootstrap-backend.sh
```

**2. Initialize and apply Terraform:**

```bash
terraform init
terraform plan
terraform apply
```

**3. Configure kubectl:**

```bash
aws eks update-kubeconfig --name yosef-aviv-status-page-prod --region us-east-1
```

**4. Deploy Kubernetes resources:**

```bash
kubectl apply -k k8s/
```

## Cost

**$289/month** for a full Multi-AZ, high-availability architecture — under a $300 budget.

| Layer | Monthly Cost |
|---|---|
| Compute (EKS + Spot Nodes) | $85.91 |
| Data (RDS + RDS Proxy + Redis) | $95.24 |
| Networking (NAT GWs + ALB) | $85.52 |
| Security & Management | $22.70 |

See [docs/AWS Cost Estimation.md](docs/AWS%20Cost%20Estimation.md) for the full breakdown and [docs/System Architecture.md](docs/System%20Architecture.md) for architectural decisions and trade-offs.

## Documentation

- [System Architecture](docs/System%20Architecture.md) -- design, layers, and trade-off rationale
- [AWS Cost Estimation](docs/AWS%20Cost%20Estimation.md) -- line-item pricing and FinOps strategies
