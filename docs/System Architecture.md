# **System Architecture: Status-Page Project**

**High-Level Overview**

*Yosef Migirov & Aviv Hanania*

*March 2026*

## **1\. Executive Summary**

This document presents the architectural design of the Status-Page application. Built with resilience at its core, the system is engineered to stay online even if an entire AWS data center goes dark. We achieved this level of reliability by decoupling the application into distinct layers and deploying them across multiple Availability Zones.

To ensure consistent, accurate, and reproducible management of this complex infrastructure, the entire cloud environment is defined and managed as Infrastructure as Code (IaC) using **Terraform**. Coupled with advanced edge security, fully automated GitOps pipelines, and smart FinOps strategies, the result is a highly reliable, low-maintenance, and cost-efficient platform.

## **2\. Core System Layers**

### **2.1 Routing and Security Layer (Route 53 & WAF)**

Amazon Route 53 routes inbound DNS queries directly to our Application Load Balancer (ALB). AWS WAF (Web Application Firewall) is attached directly to the ALB, securing the application without the overhead of a caching layer. This setup efficiently blocks malicious attacks (such as SQL injection, XSS, or DDoS attempts) before they reach our application logic.

### **2.2 Distributed Network Layer (AWS VPC)**

Our Virtual Private Cloud (VPC) is split across two Availability Zones for high availability and contains strictly segregated subnets:

* **Public Network:** Contains only the routing components (ALB) responsible for receiving public traffic.  
* **Private Network:** Hosts our compute and database resources, strictly isolated from direct internet access. Outbound internet traffic for updates is securely routed through NAT Gateways, while administrative access is securely managed via **AWS Systems Manager (SSM) Session Manager** without opening any inbound ports.
* **S3 Gateway Endpoint:** A VPC Gateway Endpoint routes all S3 traffic directly over the AWS backbone, bypassing the NAT Gateways entirely. This eliminates NAT data-processing charges for static asset uploads, Terraform state access, and container image layers—at zero additional cost.

### **2.3 Smart Compute Layer & Kubernetes Resources**

We utilize Amazon EKS (Kubernetes) to orchestrate our highly dynamic Python, Django, and Gunicorn stack. Workloads and shared infrastructure are strictly divided into specific Kubernetes resources:

1. **Web and User Requests:**  
   * **Deployment (Web):** Runs the lightweight Web pods. A **Horizontal Pod Autoscaler (HPA)** dynamically adjusts the replica count based on real-time CPU and memory utilization. To ensure traffic is only routed to healthy instances, these pods utilize strict **Liveness and Readiness Probes**.  
   * **Service:** Configured to receive internal traffic and evenly load balance it across available Web pods.  
   * **Ingress:** The application's entry point, integrated with the AWS Load Balancer Controller to provision a public ALB and define routing rules.  
2. **Background Processing and Scheduling:**
   * **Deployment (Workers):** RQ Workers that pull and execute heavy background processing tasks from the Redis queue. Each Worker pod runs with the `--with-scheduler` flag, enabling RQ's built-in leader election mechanism. Only one Worker acts as the active scheduler at any time; if it fails, another Worker automatically assumes the role within seconds. This eliminates the need for a dedicated singleton Scheduler deployment and removes a potential Single Point of Failure.  
3. **Deployment Lifecycle (DB State Management):**  
   * **Job (DB Migration):** A temporary pod spun up during CI/CD deployments to run PostgreSQL migration scripts. It terminates upon successful completion, ensuring the schema is ready before new application pods serve traffic.  
4. **Shared Infrastructure and Cluster Management:**  
   * **ConfigMap & AWS Secrets Manager:** ConfigMaps strictly store non-sensitive environment variables. For sensitive credentials (e.g., database/Redis passwords), we utilize **AWS Secrets Manager** integrated via the **Secrets Store CSI Driver**. By mounting secrets as temporary in-memory volumes, the CSI driver prevents log leaks and completely eliminates the critical risk of exposing credentials within the Kubernetes etcd database.  
   * **Cluster Autoscaler:** Monitors for pods in a "Pending" state due to insufficient cluster resources and triggers the AWS Auto Scaling Group (ASG) to dynamically provision or terminate EC2 instances. The ASG is configured with diversified Spot Instance types (t4g.medium, t4g.small, m6g.medium) to tap into multiple capacity pools and reduce the risk of Spot unavailability during scale-up events.

### **2.4 Data Layer (Automated Survivability with RDS & ElastiCache)**

Site and user data is stored in a managed database using an Amazon RDS Multi-AZ strategy. Similarly, background task queues are managed by **Amazon ElastiCache for Redis** in a Multi-AZ deployment to prevent task loss during zone failures. To achieve seamless failover for the primary database, we implemented Amazon RDS Proxy.

**Data Protection:**

* **Deletion Protection** is enabled to prevent accidental database termination.
* **Automated Backups** are retained for 7 days with a dedicated backup window, enabling point-in-time recovery to any second within the retention period.
* **Final Snapshot** is enforced on deletion, ensuring data is never permanently lost during infrastructure teardown.
* **Encryption at Rest** is enabled via AWS KMS, protecting all data, backups, and snapshots.

**Why RDS Proxy?**

* **Reduced Failover Time:** Instead of relying on slow DNS propagation, the Proxy automatically routes traffic to the new standby instance within seconds.
* **Connection Pooling:** Since Django opens a new connection per request, the Proxy manages a pool of established connections, drastically reducing database CPU overhead during sudden traffic spikes.

### **2.5 Static Assets Delivery (Amazon S3)**

To optimize performance, all static assets (CSS, JavaScript, images) are stored in and served directly from an **Amazon S3** bucket. During the CI/CD pipeline, Django's static files are automatically collected and uploaded. This strictly focuses our web pods on processing dynamic application logic rather than serving static files.

## **3\. Automation, Cost Management, and Infrastructure**

### **3.1 Smart Savings (FinOps) \- Log Filtering via CloudWatch Agent**

To optimize log storage costs and reduce cluster overhead, we run the Amazon CloudWatch Agent as a centralized DaemonSet (one per node). This agent captures cluster-wide logs, filters out routine "noise" (like HTTP 200 health checks), and forwards only actionable alerts and errors, significantly reducing AWS log ingestion costs.

### **3.2 Cost Governance in CI (Infracost)**

Every Terraform pull request is automatically analyzed by **Infracost**, an open-source FinOps tool that estimates the monthly cost impact of infrastructure changes before they are merged. Infracost parses the Terraform HCL code, queries a pricing database of over 3 million cloud SKUs, and posts a cost diff directly as a PR comment — giving the team immediate visibility into whether a change increases, decreases, or has no effect on the monthly bill. This prevents cost surprises and enforces budget awareness at the code-review stage, without requiring cloud credentials or a `terraform apply`.

### **3.3 Automated Updates (CI/CD with GitHub Actions & Argo CD)**

Deployments are fully automated via a modern GitOps pipeline. Upon code commit, **GitHub Actions** (Continuous Integration) automatically runs linting, executes the full test suite against real PostgreSQL and Redis services, builds the ARM container image, collects and uploads static assets to S3, and pushes the image to Amazon ECR.

Once successful, our Continuous Delivery tool, **Argo CD**, detects changes in the Git repository and automatically pulls them into the Amazon EKS cluster. This guarantees the live environment always matches our declarative code, enabling zero-downtime rollouts and instant rollbacks.

### **3.4 Infrastructure as Code (Terraform)**

The entire cloud infrastructure—including the VPC, EKS cluster, RDS and ElastiCache instances, S3 buckets, and edge routing (WAF, ALB, Route 53)—is exclusively provisioned via declarative code using **Terraform**. Terraform state is stored remotely in an S3 backend with DynamoDB locking to enable safe, collaborative infrastructure changes.

### **3.5 Scale-to-Zero Automation (EventBridge & Lambda)**

The Scale-to-Zero strategy is the architecture's primary cost optimization lever, reducing compute and database runtime from 730 to approximately 260 hours per month. An **Amazon EventBridge Scheduler** triggers **AWS Lambda** functions on a cron schedule to orchestrate the shutdown and startup of expensive resources.

**Shutdown Sequence (end of business):**

1. Scale application Deployments to 0 replicas, allowing pods to drain gracefully.
2. Scale the EKS managed node group to 0 desired instances.
3. Stop the RDS instance via the AWS API.

**Startup Sequence (before working hours):**

1. Start the RDS instance and wait until it reaches `available` status (typically 10–15 minutes).
2. Scale the EKS managed node group back to the desired count. Nodes launch in parallel (\~3–5 minutes).
3. Pods auto-schedule and connect to the database through RDS Proxy.

**Operational Constraints:**

* **Always-on services:** ElastiCache Redis and RDS Proxy cannot be natively stopped or paused—they run 24/7. Their costs are accounted for at full-month pricing.
* **RDS 7-day auto-restart:** AWS automatically restarts any stopped RDS instance after 7 consecutive days. Under our weekday schedule the maximum stop duration is \~64 hours, well within this limit. An auto-restart protection Lambda is deployed as a safety net for holiday periods.
* **Startup health check:** A post-startup Lambda verifies RDS availability, node readiness, and application health (HTTP 200). Failures trigger an immediate SNS alert.
* **DNS Failover coordination:** During planned Scale-to-Zero shutdowns, the ALB will have no healthy backend targets. Route 53 will detect this and failover to the static S3 page—this is intentional and correct, since users visiting during off-hours should see a static page rather than a connection error. To prevent false-positive alerts, the shutdown Lambda suppresses the Route 53 CloudWatch alarm before scaling down, and the startup Lambda re-enables it after the health check confirms the application is serving traffic.

### **3.6 Status-Page Availability & DNS Failover**

Because a status page is the resource users rely on during outages, it must remain accessible even when the primary infrastructure degrades. We implement a layered availability strategy:

1. **Route 53 Alias with "Evaluate Target Health":** The DNS record for the status page is an Alias to the ALB with target health evaluation enabled. Route 53 continuously monitors the ALB's backend target health at no additional cost and without passing through the WAF.
2. **Static S3 Failover Page:** A pre-deployed static HTML page hosted on **Amazon S3** serves as a secondary Route 53 failover target. If the ALB health evaluation reports unhealthy, Route 53 automatically resolves DNS to the S3-hosted page, displaying a "We are investigating" notice to end users. During planned Scale-to-Zero windows, this failover activates by design, serving as the off-hours landing page.
3. **SNS Alerting:** A CloudWatch alarm on the Route 53 health status metric triggers an SNS notification to the operations team when a failover is activated. Planned shutdowns suppress this alarm to avoid false positives (see Section 3.5, Operational Constraints).

## **4\. Architectural Decisions and Trade-offs**

Below is the rationale for our selected stack and the alternatives we evaluated:

### **4.1 Execution Platform: Why EKS (Kubernetes)?**

* **Alternative (EC2 / Docker Compose):** Introduces a Single Point of Failure (SPOF) and lacks native self-healing capabilities.  
* **Alternative (AWS ECS):** A valid managed solution, but tightly couples orchestration to AWS-specific APIs.  
* **Decision (EKS):** EKS ensures cloud-agnostic portability, natively supports advanced GitOps tooling (Argo CD), and provides granular networking control for distributed workloads.

### **4.2 Databases: Why Amazon RDS over a Self-Hosted DB?**

* **Alternative (Self-hosted PostgreSQL on EC2/K8s):** Requires extensive manual overhead for backups, replication, and disaster recovery.  
* **Decision (RDS Multi-AZ):** RDS offloads operational overhead to AWS, guaranteeing automated sub-minute failover, continuous backups, and high availability.

### **4.3 Edge Protection: Why WAF on ALB directly (No CDN)?**

* **Alternative (CDN like CloudFront):** Excellent for global caching, but adds architectural complexity and transit costs.  
* **Decision (Direct to ALB \+ WAF):** Since Status-Page data requires real-time delivery, application-layer edge caching yields no benefits. With static assets already offloaded to S3, attaching AWS WAF directly to the ALB efficiently secures the application.

### **4.4 Application Architecture: Separating Web and Worker Pods**

* **Alternative (Monolithic Container):** Running web servers and background workers together risks catastrophic failures; a spike in background tasks can crash the UI.  
* **Decision (Decoupled Architecture):** Running Web traffic and background tasks on separate Deployments prevents resource starvation and allows independent scaling based on specific bottlenecks.

### **4.5 CI/CD: Why Decouple with GitHub Actions and Argo CD?**

* **Alternative (Push-based CI/CD):** Granting an external CI server direct access to the EKS cluster introduces security vulnerabilities and configuration drift.  
* **Decision (Pull-based GitOps):** GitHub Actions handles strictly Continuous Integration. Argo CD, residing securely *inside* the cluster, handles Continuous Delivery by "pulling" the desired state, automatically self-healing any unauthorized manual changes.

### **4.6 Observability: CloudWatch DaemonSet vs. Log Sidecars**

* **Alternative (Sidecar Pattern):** Deploying a log-forwarding container alongside every application pod unnecessarily duplicates resource consumption.  
* **Decision (DaemonSet Agent):** Running one logging agent per physical EC2 node drastically reduces compute overhead and provides a centralized bottleneck for FinOps log-filtering.

### **4.7 Infrastructure Provisioning: Why Terraform?**

* **Alternative (Manual Provisioning / ClickOps):** Configuring cloud resources manually leads to human errors and an inability to reliably replicate environments.  
* **Decision (Terraform):** Terraform ensures our underlying infrastructure is version-controlled, auditable, and perfectly aligned with our GitOps deployment methodologies.

### **4.8 Secrets Management: Why AWS Secrets Manager over K8s Secrets?**

* **Alternative (Native Kubernetes Secrets):** Standard Kubernetes Secrets are merely Base64 encoded and stored within the cluster's internal etcd database, introducing a high risk of credential exposure.  
* **Decision (AWS Secrets Manager):** By utilizing AWS Secrets Manager and the CSI Driver, sensitive data is completely decoupled from the cluster's internal state. Passwords are encrypted at rest using AWS KMS and injected securely at runtime.

### **4.9 Static Assets Management: Why S3 over Application Pods?**

* **Alternative (Serving via Gunicorn/WhiteNoise in Pods):** Serving static files directly from application containers consumes valuable CPU and ties up worker threads meant for dynamic API requests.
* **Decision (Amazon S3):** Offloading static content to S3 decouples asset delivery from the compute layer, drastically reducing cluster load while providing highly durable, cost-effective storage.

### **4.10 Scheduling: Why Leader-Elected Workers over a Singleton Scheduler?**

* **Alternative (Dedicated Singleton Deployment):** Running a single Scheduler pod (replicas: 1) creates a Single Point of Failure. On Spot Instance clusters, node eviction leaves a gap of 2–5 minutes where no tasks are scheduled. Pinning the Scheduler to a dedicated On-Demand node solves this but introduces a second node group, taints, affinity rules, and complicates the Scale-to-Zero sequence.
* **Decision (RQ `--with-scheduler` on Workers):** Enabling the built-in scheduler flag on all Worker pods activates RQ's native leader election. Only one Worker schedules tasks at a time; if it fails, another takes over within seconds—no dedicated Deployment, no singleton risk, and no additional node group required.

### **4.11 Status-Page Availability: Why DNS Failover over External Hosting?**

* **Alternative (External SaaS Status Page):** Hosting the status page on a completely separate provider (e.g., Atlassian Statuspage) eliminates shared-fate risk entirely. However, it introduces an external dependency, recurring SaaS costs, and reduces our ability to customize the page.
* **Decision (Self-hosted with S3 Failover):** We self-host for full control and zero SaaS cost, while mitigating shared-fate risk with a static S3 failover page activated via Route 53 DNS failover. This ensures users always see a meaningful response, even during a full EKS outage.

