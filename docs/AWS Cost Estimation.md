# **Monthly AWS Cost Estimation ☁️💲**

**Project:** Status-Page

**Document Purpose:** Presenting a High Availability architecture alongside advanced FinOps capabilities for budget optimization (\<$300).

**Evaluated Region:** US East (N. Virginia) us-east-1

**Uptime Basis:** Compute resources operate during business hours only (~260 monthly active hours); network and management resources run 24/7. Note that certain managed services (ElastiCache, RDS Proxy) cannot be paused and are billed for the full 730-hour month.

## **1\. Executive Cost Summary 📊**

The estimated cost for running the full architecture (High Availability & Multi-AZ) has dropped drastically and currently stands at **$296.58 per month**.

We achieved the budget goal (under $300) without compromising on reliability (two availability zones remain active) by implementing industry Best Practices from the FinOps domain: migrating to **AWS Graviton** processors, utilizing **Spot Instances**, and operating compute resources during business hours only (~260 hours/month). The t4g.large instance type was chosen over t4g.medium to maximize pod-per-node density (35 vs 8), reducing total node count while maintaining cluster capacity.

**24/7 Production Reference:** If the architecture runs continuously without off-hours shutdowns, the monthly cost is **$390.28**.

| Layer | With Scheduling (260hr) | Full 24/7 (730hr) |
|---|---|---|
| Compute (EKS + Spot Nodes) | $98.86 | $131.93 |
| Data (RDS + RDS Proxy + Redis) | $90.30 | $150.93 |
| Networking (NAT GWs + ALB) | $85.52 | $85.52 |
| Security & Management | $21.90 | $21.90 |
| **Total** | **$296.58** | **$390.28** |

## **2\. Detailed FinOps Cost Breakdown 💰**

### **2.1 Platform & Compute Layer (Compute & K8s) \- Total: $98.86**

* **Amazon EKS Control Plane (Runs 24/7):**
  * **Pricing:** $0.10/hour × 730 hours.
  * **Cost:** $73.00/month
* **EC2 Worker Nodes (Runs 260 hours):** 3 servers of type t4g.large (ARM-based Graviton processors, 2 vCPU / 8 GiB). Running tasks on Spot Instances to reduce costs. Larger instance type chosen to maximize pod capacity per node (35 pods vs 8 on t4g.medium), reducing total node count.
  * **Compute Pricing (Spot):** \~$0.027/hour × 260 hours × 3 servers \= $21.06.
  * **Storage Pricing (EBS gp3):** 20GB per server (Total 60GB) × $0.08 per GB \= $4.80.
  * **Cost:** $25.86/month

### **2.2 Data Layer \- Total: $90.30**

* **Amazon RDS (PostgreSQL):** db.t4g.medium server in **Multi-AZ** configuration (active synchronous replica).
  * **Compute Pricing (Graviton):** $0.129/hour × 260 active hours only \= $33.54.
  * **Storage Pricing (gp3 Multi-AZ):** 50GB × $0.23 per GB \= $11.50.
  * **Cost:** $45.04/month
* **Amazon RDS Proxy (Runs 24/7):**
  * **Pricing:** $0.015 per vCPU/hour. The server has 2 vCPUs.
  * **Calculation:** $0.03 × 730 hours.
  * **Cost:** $21.90/month
  * *Note: RDS Proxy cannot be stopped or paused—only deleted and recreated. It incurs charges continuously, even while the underlying RDS instance is stopped.*
* **Amazon ElastiCache (Redis):** Two cache.t4g.micro servers in **Multi-AZ** configuration. *(Note: ElastiCache has no native stop/pause capability; pricing reflects a full 24/7 month).*
  * **Pricing:** \~$0.016/hour × 730 hours × 2 servers.
  * **Cost:** $23.36/month

### **2.3 Networking Layer \- Total: $85.52**

*(Network components run 24/7 in preparation for traffic and cannot be shut down).*

* **NAT Gateways:** 2 components (one per Availability Zone, ensuring full high availability).  
  * **Base Pricing:** $0.045/hour × 730 hours × 2 components \= $65.70.  
  * **Traffic Pricing:** Assuming 10GB outbound traffic × $0.045 \= $0.45.  
  * **Cost:** $66.15/month  
* **Application Load Balancer (ALB):**  
  * **Base Pricing:** $0.0225/hour × 730 hours \= $16.42.  
  * **Load Pricing (LCU):** Assuming 0.5 LCU/hour × $0.008 × 730 \= $2.92.  
  * **Cost:** $19.37/month

### **2.4 Security, Storage & Management Layer \- Total: $21.90**

* **AWS WAF:** $5.00 (WebACL) \+ $3.00 (3 rules) \+ $0.60 (per million requests).  
  * **Cost:** $8.60/month  
* **Amazon CloudWatch:** Accurate and filtered log collection of \~10GB.  
  * **Cost:** $5.00/month  
* **AWS Secrets Manager:** Payment for 3 managed secrets (DB credentials, Redis auth token, Django secret key).
  * **Cost:** $1.20/month  
* **Amazon Route 53 & S3:** Hosted Zone management, DNS queries, and low-tier S3 storage for static files.  
  * **Cost:** \~$7.10/month

## **3\. FinOps Strategies Implemented 🚀**

To reduce costs from the initial $455 down to $297 without compromising quality or reliability (avoiding a downgrade to Single-AZ), we implemented 3 advanced DevOps/FinOps techniques recognized as industry Best Practices:

1. **Migration to ARM Architecture (AWS Graviton Processors):** Instead of using traditional x86 processors (t3), the entire architecture was converted to Graviton processors (t4g series for EC2, RDS, and ElastiCache). This change alone improves performance and cuts about 20% off the hourly costs of compute and data components.  
2. **Business-Hours-Only Compute:** Cloud provisioning was calculated based on an operating duration of 12 hours on weekdays (approx. 260 monthly hours). Compute resources are shut down outside working hours — Web and Worker pods go to sleep, EC2 consumption drops to zero, and RDS instances are stopped during nights and weekends — saving over 60% of the runtime for the most expensive resources.  
3. **Integrating Spot Instances in Kubernetes:** Since the application is divided into layers and microservices (separation of Web and Workers), it was configured so that components performing asynchronous background work run on **AWS Spot Instances**. This grants the system a significant discount of about 50-60% on these servers, while gracefully managing service terminations (via Kubernetes Termination Grace Period). To reduce Spot interruption risk during scale-up, the ASG is configured with diversified instance types (t4g.large, m6g.large), tapping into multiple capacity pools.

## **4\. Resource Scheduling: Key Assumptions and Constraints 🔒**

The business-hours-only operating model is the single largest cost-saving lever in this architecture (saving ~$81/month). Because the entire budget depends on it, the following operational constraints are documented:
2. **Services That Cannot Be Paused:** ElastiCache Redis and RDS Proxy have no native stop/pause capability. Their costs are reflected as full 24/7 charges in Section 2.2.
3. **RDS 7-Day Auto-Restart:** AWS automatically restarts any stopped RDS instance after 7 consecutive days. Under a weekday schedule, the maximum stop duration is ~64 hours (Friday evening to Monday morning), so this limit is not triggered under normal operation.
4. **Spot Capacity on Startup:** If Spot capacity for the configured instance types is unavailable at morning scale-up, the Cluster Autoscaler falls back to the on-demand node group. Instance type diversification (see Strategy 3 above) further mitigates this risk.
5. **DNS Failover During Off-Hours:** When compute resources are shut down, the ALB has no healthy targets. Route 53 detects this and failovers to the static S3 page — users visiting during off-hours see a "We are investigating" page rather than a connection error.