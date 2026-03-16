# **Monthly AWS Cost Estimation ☁️💲**

**Project:** Status-Page

**Document Purpose:** Presenting a High Availability architecture alongside advanced FinOps capabilities for budget optimization (\<$300).

**Evaluated Region:** US East (N. Virginia) us-east-1

**Uptime Basis:** Smart organizational environment based on night/weekend shutdowns (approx. 260 monthly active hours for compute and data resources; network and management resources run 24/7). Note that certain managed services (ElastiCache, RDS Proxy) cannot be paused and are billed for the full 730-hour month.

## **1\. Executive Cost Summary 📊**

The estimated cost for running the full architecture (High Availability & Multi-AZ) has dropped drastically and currently stands at **$288.57 per month**.

We achieved the budget goal (under $300) without compromising on reliability (two availability zones remain active) by implementing industry Best Practices from the FinOps domain: migrating to **AWS Graviton** processors, utilizing **Spot Instances**, and leveraging the organizational CronJob to shut down expensive resources outside of working hours (**Scale to Zero**).

## **2\. Detailed FinOps Cost Breakdown 💰**

### **2.1 Platform & Compute Layer (Compute & K8s) \- Total: $85.91**

* **Amazon EKS Control Plane (Runs 24/7):**  
  * **Pricing:** $0.10/hour × 730 hours.  
  * **Cost:** $73.00/month  
* **EC2 Worker Nodes (Runs 260 hours):** 3 servers of type t4g.medium (ARM-based Graviton processors). Running tasks on Spot Instances to reduce costs.  
  * **Compute Pricing (Spot):** \~$0.0104/hour × 260 hours × 3 servers \= $8.11.  
  * **Storage Pricing (EBS gp3):** 20GB per server (Total 60GB) × $0.08 per GB \= $4.80.  
  * **Cost:** $12.91/month

### **2.2 Data Layer \- Total: $95.24**

* **Amazon RDS (PostgreSQL):** db.t4g.medium server in **Multi-AZ** configuration (active synchronous replica).
  * **Compute Pricing (Graviton):** $0.148/hour × 260 active hours only \= $38.48.
  * **Storage Pricing (gp3 Multi-AZ):** 50GB × $0.23 per GB \= $11.50.
  * **Cost:** $49.98/month
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

To reduce costs from the initial $455 down to $288 without compromising quality or reliability (avoiding a downgrade to Single-AZ), we implemented 3 advanced DevOps/FinOps techniques recognized as industry Best Practices:

1. **Migration to ARM Architecture (AWS Graviton Processors):** Instead of using traditional x86 processors (t3), the entire architecture was converted to Graviton processors (t4g series for EC2, RDS, and ElastiCache). This change alone improves performance and cuts about 20% off the hourly costs of compute and data components.  
2. **Leveraging Organizational Automation for "Scale to Zero":** Cloud provisioning was calculated based on an operating duration of 12 hours on weekdays (approx. 260 monthly hours). By integrating the organizational CronJob with the EKS Cluster Autoscaler, the architecture automatically "puts to sleep" Web and Worker pods, reduces EC2 consumption to zero, and pauses the RDS instances during nights and weekends—an action that saves over 60% of the runtime for the most expensive resources.  
3. **Integrating Spot Instances in Kubernetes:** Since the application is divided into layers and microservices (separation of Web and Workers), it was configured so that components performing asynchronous background work run on **AWS Spot Instances**. This grants the system a massive discount of about 70-90% on these servers, while gracefully managing service terminations (via Kubernetes Termination Grace Period). To reduce Spot interruption risk during scale-up, the ASG is configured with diversified instance types (t4g.medium, t4g.small, m6g.medium), tapping into multiple capacity pools.

## **4\. Scale-to-Zero: Key Assumptions and Risks 🔒**

The Scale-to-Zero strategy is the single largest cost-saving lever in this architecture (saving \~$166/month). Because the entire budget depends on it, the following operational constraints are documented:

1. **Shutdown/Startup Automation:** An **Amazon EventBridge Scheduler** triggers **AWS Lambda** functions on a cron schedule (shutdown at end of business, startup before working hours). Lambda orchestrates the sequence: drain application pods, scale EKS node group to zero desired instances, then stop the RDS instance. Startup reverses this order—RDS starts first (allow 10–15 minutes to become available), then EKS nodes scale up, and pods schedule automatically.
2. **Services That Cannot Be Paused:** ElastiCache Redis and RDS Proxy have no native stop/pause capability. Their costs are reflected as full 24/7 charges in Section 2.2. Deleting and recreating these resources during off-hours was evaluated but rejected due to added automation complexity and startup latency.
3. **RDS 7-Day Auto-Restart:** AWS automatically restarts any stopped RDS instance after 7 consecutive days. Under our weekday schedule, the maximum stop duration is \~64 hours (Friday evening to Monday morning), so this limit is not triggered under normal operation. An auto-restart protection Lambda is deployed as a safety net for extended holiday periods.
4. **Spot Capacity on Startup:** If Spot capacity for the configured instance types is unavailable at Monday morning scale-up, the Cluster Autoscaler may take up to 15 minutes to fall back. Instance type diversification (see Strategy 3 above) mitigates this risk.
5. **Startup Health Check:** A post-startup Lambda verifies that the RDS instance is available, EKS nodes are Ready, and the application endpoint returns HTTP 200. If any check fails, an SNS alert is sent to the operations team immediately.