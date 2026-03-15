# **Implementation Tasks: Code-to-Architecture Alignment**

**Project:** Status-Page

**Purpose:** Itemized task list to bring the existing codebase in line with the documented System Architecture and AWS Cost Estimation.

---

## **1. Terraform — Compute & Instance Migration**

### 1.1 Migrate EC2 Worker Nodes to Graviton + Spot
**File:** `status-page-infra/terraform/main.tf` (EKS module)
- [ ] Change instance type from `t3.medium` to `t4g.medium` (ARM/Graviton).
- [ ] Set `capacity_type` to `SPOT` in the managed node group.
- [ ] Add diversified instance types to the node group: `t4g.medium`, `t4g.small`, `m6g.medium`.
- [ ] Change desired/min/max from `2/2/4` to `3/0/4` (min 0 enables Scale-to-Zero).
- [ ] Change EBS volume size from `20` to `20` (matches — no change needed).

### 1.2 Migrate RDS to Graviton + Correct Sizing
**File:** `status-page-infra/terraform/main.tf` (RDS resources)
- [ ] Change instance class from `db.t3.micro` to `db.t4g.medium`.
- [ ] Change `allocated_storage` from `20` to `50` GB.
- [ ] Change storage type from `gp2` to `gp3`.
- [ ] Verify `multi_az = true` (already set).

### 1.3 Add RDS Proxy
**File:** `status-page-infra/terraform/main.tf` (new resource)
- [ ] Add `aws_db_proxy` resource targeting the RDS instance.
- [ ] Add `aws_db_proxy_default_target_group` and `aws_db_proxy_target`.
- [ ] Add IAM role and policy for Proxy to read Secrets Manager credentials.
- [ ] Add security group for Proxy (allow ingress from EKS node SG on 5432).
- [ ] Update SSM parameter `/{name}/db/host` to point to the Proxy endpoint instead of RDS endpoint.

---

## **2. Terraform — Networking**

### 2.1 Enable Dual NAT Gateways
**File:** `status-page-infra/terraform/main.tf` (VPC module)
- [ ] Add `one_nat_gateway_per_az = true` to the VPC module to deploy one NAT Gateway per AZ.
- [ ] Add `single_nat_gateway = false` (explicit).

### 2.2 Add S3 Gateway Endpoint
**File:** `status-page-infra/terraform/main.tf` (new resource or VPC module parameter)
- [ ] Add a VPC Gateway Endpoint for S3 to reduce NAT traffic and cost (free).

---

## **3. Terraform — Security**

### 3.1 Add AWS WAF
**File:** `status-page-infra/terraform/main.tf` (new resources)
- [ ] Add `aws_wafv2_web_acl` with managed rule groups:
  - AWS Managed Rules Common Rule Set (AWSManagedRulesCommonRuleSet).
  - SQL Injection Rule Set (AWSManagedRulesSQLiRuleSet).
  - Known Bad Inputs Rule Set (AWSManagedRulesKnownBadInputsRuleSet).
- [ ] Add `aws_wafv2_web_acl_association` attaching the ACL to the ALB.
- [ ] Output the WAF WebACL ARN.

### 3.2 Add Route 53 + DNS Failover
**File:** `status-page-infra/terraform/main.tf` (new resources)
- [ ] Add `aws_route53_zone` for the project domain.
- [ ] Add `aws_route53_record` (Alias to ALB, primary failover, evaluate_target_health = true).
- [ ] Add `aws_route53_record` (secondary failover pointing to S3 static page).
- [ ] Add S3 bucket for the static failover page with a pre-deployed "investigating" HTML file.
- [ ] Add CloudWatch alarm on Route 53 health status metric → SNS topic for alerting.

### 3.3 Enable HTTPS / TLS
**File:** `status-page-infra/terraform/main.tf` + `status-page-infra/k8s/ingress.yaml`
- [ ] Add `aws_acm_certificate` resource (or import an existing cert) for the domain.
- [ ] Add `aws_acm_certificate_validation` with Route 53 DNS validation records.
- [ ] Update Kubernetes Ingress annotations to use HTTPS:
  - `alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'`
  - `alb.ingress.kubernetes.io/certificate-arn: <ACM_ARN>`
  - `alb.ingress.kubernetes.io/ssl-redirect: "443"`

---

## **4. Terraform — State Management**

### 4.1 Configure Remote State Backend
**New file:** `status-page-infra/terraform/backend.tf`
- [ ] Create an S3 bucket for Terraform state (manually or via a bootstrap script).
- [ ] Create a DynamoDB table for state locking.
- [ ] Add `backend "s3"` configuration block.
- [ ] Run `terraform init -migrate-state` to migrate existing local state.

---

## **5. Terraform — Scale-to-Zero Automation**

### 5.1 Build EventBridge + Lambda for Scheduled Scaling
**New files:** `status-page-infra/terraform/scale-to-zero.tf` + Lambda source
- [ ] Create IAM role for Lambda (permissions: EKS node group scaling, RDS stop/start, CloudWatch, SNS).
- [ ] Create Lambda function for **shutdown**: scale node group desired to 0, stop RDS.
- [ ] Create Lambda function for **startup**: start RDS, wait for `available`, scale node group desired to 3.
- [ ] Create Lambda function for **startup health check**: verify RDS available, nodes Ready, app returns HTTP 200. On failure → publish to SNS.
- [ ] Create EventBridge Scheduler rule for shutdown (e.g., weekdays 20:00 UTC).
- [ ] Create EventBridge Scheduler rule for startup (e.g., weekdays 06:30 UTC, 30 min before business).
- [ ] Create EventBridge Scheduler rule for startup health check (e.g., weekdays 07:00 UTC).
- [ ] Create SNS topic + subscription for failure alerts.

### 5.2 RDS Auto-Restart Protection
- [ ] Deploy the `amazon-rds-auto-restart-protection` pattern (EventBridge rule on RDS event + Lambda to re-stop) for holiday periods.

---

## **6. Kubernetes Manifests**

### 6.1 Eliminate Singleton Scheduler Deployment
**Delete:** `status-page-infra/k8s/deployment-scheduler.yaml`
**Edit:** `status-page-infra/k8s/deployment-worker.yaml`
- [ ] Remove `deployment-scheduler.yaml` from the manifests and from `kustomization.yaml`.
- [ ] Update the Worker Deployment command from `python manage.py rqworker default high low` to `python manage.py rqworker --with-scheduler default high low` to enable RQ's built-in leader-elected scheduling.

### 6.2 Update Docker Base Image for ARM
**File:** `status-page/Dockerfile`
- [ ] Change base image from `python:3.10-slim` to `python:3.10-slim` with a multi-arch build, or explicitly target `--platform linux/arm64` to match t4g (Graviton/ARM) nodes.
- [ ] Verify all pip dependencies install cleanly on ARM (psycopg2, etc.).

### 6.3 Update Kustomization
**File:** `status-page-infra/k8s/kustomization.yaml`
- [ ] Remove `deployment-scheduler.yaml` from the resources list.

---

## **7. CI/CD Pipeline**

### 7.1 GitHub Actions — Continuous Integration
**New file:** `.github/workflows/ci.yml`
- [ ] Trigger on push/PR to main.
- [ ] Run Django tests (`python manage.py test`).
- [ ] Run linting (flake8/ruff).
- [ ] Build Docker image (multi-arch: amd64 + arm64).
- [ ] Push image to ECR with commit SHA tag.
- [ ] Run `collectstatic` and upload static files to S3.

### 7.2 GitHub Actions — Continuous Delivery Trigger
**New file:** `.github/workflows/cd.yml`
- [ ] On successful CI, update the Kustomize image tag in a GitOps repo/branch.
- [ ] ArgoCD detects the change and pulls the new state into the cluster.

### 7.3 Configure ArgoCD Application
**New file:** `status-page-infra/argocd/application.yaml`
- [ ] Create ArgoCD `Application` resource pointing to the `status-page-infra/k8s/` directory.
- [ ] Configure sync policy (automated, self-heal, prune).
- [ ] ArgoCD Helm release is already installed in Terraform — it just needs the Application manifest.

---

## **8. Verification & Testing**

### 8.1 Validate Architecture Alignment
- [ ] Run `terraform plan` and verify all resources match the documented architecture.
- [ ] Deploy to a staging environment and verify:
  - ALB + WAF + HTTPS serves traffic correctly.
  - Route 53 DNS resolves to ALB.
  - DNS failover activates when ALB targets are unhealthy (test by scaling web pods to 0).
  - RDS Proxy connects to RDS and application works through it.
  - Worker pods with `--with-scheduler` correctly elect a leader and schedule tasks.
  - Scale-to-Zero Lambda shuts down and starts up the environment correctly.
  - Startup health check Lambda detects failures and sends SNS alerts.
- [ ] Verify Spot Instance behavior:
  - Nodes launch from diversified instance types.
  - Pod disruption is handled gracefully on Spot reclamation.
- [ ] Verify cost alignment:
  - After one week of operation, check AWS Cost Explorer against the $289.37/month estimate.
