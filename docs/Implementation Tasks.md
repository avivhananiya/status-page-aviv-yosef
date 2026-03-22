# **Implementation Tasks: Code-to-Architecture Alignment**

**Project:** Status-Page

**Purpose:** Itemized task list to bring the existing codebase in line with the documented System Architecture and AWS Cost Estimation.

---

## **1. Terraform — Compute & Instance Migration**

### 1.1 Migrate EC2 Worker Nodes to Graviton + Spot
**File:** `terraform/eks.tf`
- [x] Change instance type from `t3.medium` to `t4g.medium` (ARM/Graviton).
- [x] Set `capacity_type` to `SPOT` in the managed node group.
- [x] Add diversified ARM instance types: `t4g.large`, `m6g.large` (upgraded from medium for higher pod-per-node density).
- [x] Set `ami_type` to `AL2023_ARM_64_STANDARD` (migrated from AL2 to AL2023).
- [x] Change desired/min/max from `2/2/4` to `3/1/4` (min 1 ensures at least one node is always available).

### 1.2 Migrate RDS to Graviton + Correct Sizing
**File:** `terraform/rds.tf`
- [x] Change instance class from `db.t3.micro` to `db.t4g.medium`.
- [x] Change `allocated_storage` from `20` to `50` GB.
- [x] Change storage type from `gp2` to `gp3`.
- [x] Verify `multi_az = true` (already set).

### 1.3 Add RDS Data Protection
**File:** `terraform/rds.tf`
- [x] Enable `deletion_protection = true`.
- [x] Set `skip_final_snapshot = false` with `final_snapshot_identifier`.
- [x] Set `backup_retention_period = 7` with dedicated `backup_window`.
- [x] Enable `storage_encrypted = true`.

### 1.4 Add RDS Proxy
**File:** `terraform/rds.tf`
- [x] Add `aws_db_proxy` resource targeting the RDS instance.
- [x] Add `aws_db_proxy_default_target_group` and `aws_db_proxy_target`.
- [x] Add IAM role and policy for Proxy to read Secrets Manager credentials.
- [x] Add security group for Proxy (allow ingress from EKS node SG on 5432).
- [x] Add egress rules for Proxy SG: port 5432 to RDS SG + port 443 to Secrets Manager.
- [x] Update SSM parameter `/{name}/db/host` to point to the Proxy endpoint instead of RDS endpoint.

---

## **2. Terraform — Networking**

### 2.1 Enable Dual NAT Gateways
**File:** `terraform/network.tf`
- [x] Add `one_nat_gateway_per_az = true` to the VPC module.
- [x] Add `single_nat_gateway = false` (explicit).

### 2.2 Add S3 Gateway Endpoint
**File:** `terraform/network.tf`
- [x] Add a VPC Gateway Endpoint for S3 to reduce NAT traffic and cost (free).

---

## **3. Terraform — Security**

### 3.1 Add AWS WAF
**File:** `terraform/waf.tf` + `k8s/status-page-chart/templates/ingress.yaml`
- [x] Add `aws_wafv2_web_acl` with managed rule groups:
  - AWS Managed Rules Common Rule Set (AWSManagedRulesCommonRuleSet).
  - SQL Injection Rule Set (AWSManagedRulesSQLiRuleSet).
  - Known Bad Inputs Rule Set (AWSManagedRulesKnownBadInputsRuleSet).
- [x] Associate WAF with ALB via Ingress annotation (`alb.ingress.kubernetes.io/wafv2-acl-arn`).
- [x] Output the WAF WebACL ARN.
- [x] After `terraform apply`, update `wafAclArn` in `k8s/status-page-chart/values.yaml` with the actual WAF ACL ARN.

### 3.2 Add Route 53 + DNS
**File:** `terraform-dns/` + `terraform/dns.tf` + `k8s/status-page-chart/templates/ingress.yaml`
- [x] Add `aws_route53_zone` for `yosef-aviv-statuspage.xyz` (separate state in `terraform-dns/`).
- ~~Add ExternalDNS (IRSA + Helm)~~ — not needed; Terraform-managed Route 53 failover records handle DNS directly.
- ~~Add `external-dns.alpha.kubernetes.io/hostname` annotation to Ingress~~ — not needed; see above.
- [x] Add DNS Failover: primary Route 53 record (Alias to ALB, evaluate_target_health) + secondary (Alias to S3).
- [x] Add S3 bucket for the static failover page with a pre-deployed "investigating" HTML file.
- [x] Add Route 53 health check for ALB failover monitoring.

### 3.3 Enable HTTPS / TLS
**File:** `terraform/dns.tf` + `k8s/status-page-chart/templates/ingress.yaml`
- [x] Add `aws_acm_certificate` resource with wildcard SAN for the domain.
- [x] Add `aws_acm_certificate_validation` with Route 53 DNS validation records.
- [x] Update Kubernetes Ingress annotations to use HTTPS:
  - `alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80},{"HTTPS":443}]'`
  - `alb.ingress.kubernetes.io/certificate-arn` (placeholder — update after `terraform apply`)
  - `alb.ingress.kubernetes.io/ssl-redirect: "443"`
- [x] After `terraform apply`, update `certificateArn` in `k8s/status-page-chart/values.yaml` with the actual ACM certificate ARN.
- [x] Restrict `ALLOWED_HOSTS` in `k8s/status-page-chart/templates/configmap.yaml` to the project domain.

---

## **4. Terraform — State Management**

### 4.1 Configure Remote State Backend
**File:** `terraform/backend.tf` + `terraform/bootstrap-backend.sh`
- [x] Create an S3 bucket for Terraform state (via bootstrap script).
- [x] Create a DynamoDB table for state locking.
- [x] Add `backend "s3"` configuration block.
- [x] Run `terraform init -migrate-state` to migrate existing local state.

---

## **5. Infrastructure Upgrades & Hardening**

### 5.1 Upgrade EKS to Latest Standard-Support Version
**File:** `terraform/eks.tf`
- [x] Upgrade `cluster_version` from `1.30` to `1.35` (sequential: 1.30→1.31→1.32→1.33→1.34→1.35).
- [x] Migrate node AMI from `AL2_ARM_64` to `AL2023_ARM_64_STANDARD` (AL2 AMIs stopped publishing Nov 2025).
- **Why:** EKS 1.30 entered extended support ($0.60/hr vs $0.10/hr) — 6x the control plane cost.

### 5.2 Split Terraform into Domain-Specific Modules
**File:** `terraform/` (was monolithic `main.tf`)
- [x] Split 1262-line `main.tf` into: `network.tf`, `eks.tf`, `rds.tf`, `elasticache.tf`, `secrets.tf`, `iam.tf`, `helm.tf`, `storage.tf`, `dns.tf`, `waf.tf`, `ssm.tf`.
- [x] Zero functional change — Terraform reads all `.tf` files in a directory.

### 5.3 Fix Infracost CI Pipeline
**File:** `.github/workflows/infracost.yml`
- [x] Add `terraform init -backend=false` step before Infracost (S3 backend requires AWS credentials which CI doesn't have).
- [x] Pass `--terraform-init-flags "-backend=false"` to Infracost breakdown.

### 5.4 Upgrade Instance Types for Pod Density
**File:** `terraform/eks.tf`
- [x] Upgrade Spot and On-Demand instance types from `t4g.medium`/`t4g.small`/`m6g.medium` to `t4g.large`/`m6g.large`.
- **Why:** Smaller instances had an ENI limit of 8 pods/node, forcing excessive node scaling. Large instances support 35 pods/node.

### 5.5 Fix ArgoCD Application Manifest
**File:** `argocd/application.yaml`
- [x] Fix `helm` block indentation — was a sibling of `source` instead of nested under it.
- **Why:** ArgoCD would ignore `values.yaml` without this fix.

### 5.6 Conditional DNS Failover (Chicken-and-Egg)
**File:** `terraform/dns.tf` + `terraform/variables.tf`
- [x] Add `enable_dns_failover` variable (default `false`).
- [x] Wrap ALB data source, Route 53 failover records, and health check with `count`.
- [x] After app deployment creates the ALB, run `terraform apply -var="enable_dns_failover=true"`.
- [x] Change `enable_dns_failover` default to `true` (ALB exists, no longer needed as CLI flag).

### 5.7 Protect EKS Nodegroups from College Cron Job
**File:** `terraform/eks.tf`
- [x] Add `DoNotDelete = "true"` tag to both `spot` and `on_demand` nodegroups.
- **Why:** College Lambda `stop_resources` (EventBridge rule `stop-resources-schedule`, runs every 60 min) scales all EKS nodegroups to `min=0/max=1/desired=0` unless tagged `DoNotDelete`. This was the root cause of repeated nodegroup drain.

---

## **6. Kubernetes Manifests**

### 6.1 Eliminate Singleton Scheduler Deployment
- [x] Delete `k8s/deployment-scheduler.yaml`.
- [x] Remove scheduler from Kustomize resources (now Helm chart).
- [x] Update Worker command to `python manage.py rqworker --with-scheduler default high low`.

### 6.2 Convert K8s Manifests to Helm Chart
**Directory:** `k8s/status-page-chart/`
- [x] Create Helm chart structure (`Chart.yaml`, `values.yaml`, `templates/`).
- [x] Move all raw manifests into `templates/` with Helm value references.
- [x] Centralize config in `values.yaml` (image, replicas, HPA limits, ingress, AWS settings).
- [x] Remove old `kustomization.yaml`.
- [x] Update ArgoCD `application.yaml` to point to `k8s/status-page-chart` with Helm values.

### 6.3 Add Emergency On-Demand Node Group
**File:** `terraform/eks.tf`
- [x] Rename existing node group from `default` to `spot` (explicit naming).
- [x] Add `on_demand` node group (`desired_size=0`, `max_size=1`) as Spot fallback.
- [x] Use same Graviton ARM instance types (`t4g.large`, `m6g.large`).

### 6.4 Harden Manifests
- [x] Fix ingress `success-codes` from `200-499` to `200`.
- [x] Add `terminationGracePeriodSeconds: 120` to worker deployment for Spot eviction grace.
- [x] Fix migration job `backoffLimit` comment.
- [x] Add `Host` header to web liveness/readiness probes so Django does not reject health checks with `DisallowedHost`.
- [x] Template `ALLOWED_HOSTS` in ConfigMap as `{{ .Values.ingress.host }}` instead of hardcoded domain.

### 6.5 Update Docker Base Image for ARM
**File:** `status-page-app/Dockerfile`
- [x] Target `--platform linux/arm64` in CI build to match Graviton nodes.
- [x] Verify all pip dependencies install cleanly on ARM (psycopg2, etc.) — confirmed by successful CI build on `11a05f5`.

---

## **7. CI/CD Pipeline**

### 7.1 GitHub Actions — Continuous Integration (App Repo)
**File:** `status-page-app/.github/workflows/ci.yml`
- [x] Trigger on push/PR to main.
- [x] Run Django tests with PostgreSQL + Redis services.
- [x] Build Docker image (ARM/linux-arm64) via Buildx.
- [x] Push image to ECR with commit SHA tag.
- [x] Add linting step (ruff).
- [x] Add `collectstatic` and upload static files to S3.
- [x] Add `configuration_docker.py` (env-var bridge for Docker/CI/K8s — without it, Django cannot import settings).
- [x] Update `configuration_docker.py` to read secrets (`DB_PASSWORD`, `REDIS_PASSWORD`, `DJANGO_SECRET_KEY`) from Secrets Store CSI mount (`/mnt/secrets-store/`), falling back to env vars.
- [x] ~~Store `S3_STATIC_BUCKET` as a GitHub Actions secret~~ — replaced by AWS SSM parameter lookup (`/yosef-aviv-status-page-prod/s3/static_url`) in CI, no secret needed.

### 7.2 GitHub Actions — Continuous Delivery Trigger (App Repo)
**Part of:** `status-page-app/.github/workflows/ci.yml`
- [x] On successful CI, update `image.tag` in infra repo's `k8s/status-page-chart/values.yaml` to the commit SHA.
- [x] ArgoCD detects the change and pulls the new state into the cluster.

### 7.3 GitHub Actions — Terraform Validation (Infra Repo)
**File:** `.github/workflows/terraform.yml`
- [x] Trigger on PR to main (Terraform changes only).
- [x] Run `terraform fmt -check`, `terraform init -backend=false`, `terraform validate`.

### 7.4 GitHub Actions — Infracost Cost Estimation (Infra Repo)
**File:** `.github/workflows/infracost.yml`
- [x] Trigger on PR to main (Terraform changes only).
- [x] Run `infracost breakdown` on the Terraform directory.
- [x] Post cost diff as a PR comment using `infracost comment`.
- [x] Store Infracost API key as a GitHub Actions secret (manual step).

### 7.5 Harden CI Pipeline
**File:** `status-page-app/.github/workflows/ci.yml`
- [x] Align Python version in CI (3.10) with Dockerfile/production (3.12) — tests and collectstatic must match runtime.
- [x] Make `ruff` lint visible — shows statistics as CI warning. Kept non-blocking: 219 pre-existing errors in upstream app code need Aviv to fix before lint can block.
- [x] Avoid duplicate `pip install` in Build & Deploy — baked `collectstatic` into Dockerfile, CI extracts static files from the built image via `docker cp`.

### 7.6 Enable Branch Protection on `main`
**Location:** GitHub repo → Settings → Branches (requires admin access)
- [ ] Add branch protection rule for `main`:
  - Require pull request with 1 approval before merging.
  - Require status checks to pass: `Format & Validate`, `Cost Estimation`.
  - Require branches to be up to date before merging.

### 7.7 Configure ArgoCD Application
**New file:** `argocd/application.yaml`
- [x] Create ArgoCD `Application` resource pointing to `k8s/status-page-chart` (Helm).
- [x] Configure sync policy (automated, self-heal, prune, CreateNamespace).
- [x] ArgoCD Helm release is already installed in Terraform — it just needs the Application manifest.

---

## **8. Deployment & Go-Live**

### 8.1 Deploy Infrastructure
- [x] Run `terraform apply` — VPC, EKS, RDS, ElastiCache, WAF, ACM, S3, ECR, Helm releases.
- [x] Verify all resources created and cluster is healthy.

### 8.2 Deploy Application via ArgoCD
- [x] Apply ArgoCD Application manifest (`kubectl apply -f argocd/application.yaml`).
- [x] Verify web pods, worker pods, and migration job start successfully.
- [x] Verify ALB is created by the Ingress.

### 8.3 Enable DNS Failover
- [x] Run `terraform apply -var="enable_dns_failover=true"` after ALB exists.
- [x] Verify Route 53 resolves to ALB (failover active — currently serving S3 page while nodes cycle).

### 8.4 Update Helm Values with Live ARNs
- [x] Update `wafAclArn` in `k8s/status-page-chart/values.yaml` with actual WAF ACL ARN.
- [x] Update `certificateArn` in `k8s/status-page-chart/values.yaml` with actual ACM certificate ARN.
- [x] Restrict `ALLOWED_HOSTS` in ConfigMap to the project domain.

### 8.5 Configure GitHub Secrets (Manual)
- [x] App repo: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `INFRA_REPO_TOKEN` — confirmed by successful CI run.
- [x] ~~App repo: `S3_STATIC_BUCKET`~~ — no longer needed (replaced by SSM lookup in CI).
- [x] Infra repo: `INFRACOST_API_KEY`.

### 8.6 Demonstrate CI Pipeline
- [x] Open a test PR with a Terraform change to trigger validation + Infracost workflows.
- [x] Verify Infracost posts a cost comment on the PR.

---

## **9. Verification & Testing**

### 9.1 Validate Architecture Alignment
- [x] Run `terraform plan` and verify all resources match the documented architecture (174 resources, 0 drift).
- [ ] Deploy to a staging environment and verify:
  - ALB + WAF + HTTPS serves traffic correctly.
  - Route 53 DNS resolves to ALB.
  - DNS failover activates when ALB targets are unhealthy (test by scaling web pods to 0).
  - RDS Proxy connects to RDS and application works through it.
  - Worker pods with `--with-scheduler` correctly elect a leader and schedule tasks.
- [ ] Verify Spot Instance behavior:
  - Nodes launch from diversified instance types.
  - Pod disruption is handled gracefully on Spot reclamation.
- [ ] Verify cost alignment:
  - After one week of operation, check AWS Cost Explorer against the $390.28/month estimate (24/7) or ~$296.58/month with college scheduling.
