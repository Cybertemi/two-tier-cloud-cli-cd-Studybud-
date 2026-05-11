
# StudyBud — Production DevOps Deployment
### Terraform · Docker · GitHub Actions · AWS EC2 · CloudWatch

---

## Table of Contents
1. [Architecture Overview](#architecture-overview)
2. [Technology Stack](#technology-stack)
3. [Project Structure](#project-structure)
4. [Infrastructure as Code](#infrastructure-as-code)
5. [Containerization](#containerization)
6. [CI/CD Pipeline](#cicd-pipeline)
7. [Deployment Steps](#deployment-steps)
8. [Monitoring & Logging](#monitoring--logging)
9. [Security](#security)
10. [Design Decisions](#design-decisions)
11. [Assumptions](#assumptions)
12. [Limitations & Future Improvements](#limitations--future-improvements)
13. [Screenshots](#screenshots)

---

## Architecture Overview

This project follows a **two-tier production deployment model** for the StudyBud Django application. The architecture separates the application layer (EC2 + Docker) from the data layer (SQLite), with a fully automated CI/CD pipeline orchestrating every deployment from code push to live production.

```
Developer (git push)
        │
        ▼
┌─────────────────────────┐
│     GitHub Repository    │
└─────────────────────────┘
        │
        ▼
┌─────────────────────────────────────────────────┐
│           GitHub Actions CI/CD Pipeline          │
│                                                  │
│  ┌─────────┐  ┌─────────┐  ┌──────────┐  ┌────┐│
│  │  Test   │→ │  Build  │→ │  Scan    │→ │Deploy││
│  │(Django) │  │(Docker) │  │(Trivy)   │  │(SSH) ││
│  └─────────┘  └─────────┘  └──────────┘  └────┘│
└─────────────────────────────────────────────────┘
        │                         │
        ▼                         ▼
┌──────────────┐        ┌──────────────────────────┐
│  Docker Hub  │        │     AWS (us-east-1)       │
│  (Registry)  │        │                           │
└──────────────┘        │  ┌────────────────────┐  │
        │               │  │        VPC          │  │
        │               │  │  ┌──────────────┐  │  │
        └───────────────┼─▶│  │  Public Subnet│  │  │
                        │  │  │              │  │  │
                        │  │  │  ┌────────┐  │  │  │
                        │  │  │  │  EC2   │  │  │  │
                        │  │  │  │t3.micro│  │  │  │
                        │  │  │  │        │  │  │  │
                        │  │  │  │ Docker │  │  │  │
                        │  │  │  │ Nginx  │  │  │  │
                        │  │  │  │ Certbot│  │  │  │
                        │  │  │  └────────┘  │  │  │
                        │  │  └──────────────┘  │  │
                        │  │                    │  │
                        │  │  ┌──────────────┐  │  │
                        │  │  │  CloudWatch  │  │  │
                        │  │  │  Log Groups  │  │  │
                        │  │  └──────────────┘  │  │
                        │  └────────────────────┘  │
                        └──────────────────────────┘
                                    │
                                    ▼
                        ┌──────────────────────┐
                        │  End Users           │
                        │  https://studybud    │
                        │  .duckdns.org        │
                        └──────────────────────┘
```

---

## Technology Stack

| Tool | Purpose |
|------|---------|
| Django (Python) | Web application framework |
| Docker | Containerization |
| Docker Hub | Container image registry |
| Terraform | Infrastructure as Code |
| GitHub Actions | CI/CD automation |
| AWS EC2 | Application hosting |
| AWS VPC | Network isolation |
| AWS CloudWatch | Monitoring & logging |
| AWS IAM | Access management |
| Nginx | Reverse proxy & static files |
| Certbot | Automated SSL certificates |
| Trivy | Container vulnerability scanning |
| DuckDNS | Free dynamic DNS |
| Gunicorn | Production WSGI server |

---

## Project Structure

```
two-tier-cloud-ci-cd/
├── .github/
│   └── workflows/
│       └── deploy.yml          # GitHub Actions CI/CD pipeline
│
├── scripts/
│   └── deploy.sh               # Automated deployment script
│
├── terraform/
│   ├── main.tf                 # Root Terraform configuration
│   ├── variables.tf            # Input variables
│   ├── outputs.tf              # Output values
│   └── modules/
│       ├── vpc/
│       │   ├── main.tf         # VPC, subnets, routing
│       │   ├── variables.tf
│       │   └── outputs.tf
│       └── ec2/
│           ├── main.tf         # EC2, IAM, security groups
│           ├── variables.tf
│           ├── outputs.tf
│           └── cloudwatch.tf   # CloudWatch alarms & log groups
│
├── base/                       # Django app
│   ├── views.py                # Includes /health endpoint
│   ├── urls.py
│   ├── models.py
│   └── templates/
│
├── studybud/                   # Django project
│   ├── settings.py
│   ├── urls.py
│   └── wsgi.py
│
├── Dockerfile                  # Multi-stage production Dockerfile
├── requirements.txt
├── manage.py
└── README.md
```

---

## Infrastructure as Code

Infrastructure is provisioned using **Terraform** with a modular structure for reusability and maintainability.

### Provisioned AWS Resources

| Resource | Details |
|----------|---------|
| VPC | `10.0.0.0/16` CIDR block |
| Public Subnets | 2 subnets across 2 AZs |
| Internet Gateway | For public internet access |
| Route Tables | Public routing configured |
| Security Group | Ports 22, 80, 443, 8000 open |
| EC2 Instance | `t3.micro` — Ubuntu 22.04 |
| IAM Role | CloudWatch agent permissions |
| CloudWatch Log Group | `/studybud/app` |
| CloudWatch Alarms | CPU utilization & status checks |

### Initialize & Apply

```bash
cd terraform
terraform init
terraform validate
terraform plan
terraform apply
```

---

## Containerization

The application is containerized using **Docker** with **Gunicorn** as the production WSGI server.

```bash
# Build image locally
docker build -t studybud .

# Run container locally
docker run -p 8000:8000 studybud
```

Docker images are tagged with the **Git commit SHA** for immutable, traceable deployments.

---

## CI/CD Pipeline

The pipeline is triggered automatically on every push to the `main` branch.

```
push to main
     │
     ▼
┌─────────┐     ┌───────────────┐     ┌──────────────┐     ┌───────────┐
│  Test   │────▶│ Build & Push  │────▶│ Security Scan│────▶│  Deploy   │
│         │     │  to Docker Hub│     │ (Trivy)      │     │  to EC2   │
└─────────┘     └───────────────┘     └──────────────┘     └───────────┘
```

### Pipeline Stages

**1. Test**
- Installs Python dependencies
- Runs `python manage.py check`
- Runs `python manage.py test`

**2. Build & Push**
- Builds Docker image
- Tags with Git commit SHA
- Pushes to Docker Hub

**3. Security Scan**
- Scans image with Trivy
- Detects CRITICAL and HIGH vulnerabilities
- Non-blocking — pipeline continues regardless

**4. Deploy**
- SSHs into EC2 via GitHub Actions
- Copies `deploy.sh` to server
- Pulls new image from Docker Hub
- Stops old container, starts new one
- Runs Django migrations
- Copies static files
- Configures Nginx
- Provisions/renews SSL certificate via Certbot

### Required GitHub Secrets

| Secret | Description |
|--------|-------------|
| `DOCKERHUB_USERNAME` | Docker Hub username |
| `DOCKERHUB_TOKEN` | Docker Hub access token |
| `EC2_HOST` | EC2 public IP address |
| `EC2_SSH_KEY` | Private SSH key (PEM format) |
| `DOMAIN` | `studybud.duckdns.org` |
| `CERTBOT_EMAIL` | Email for SSL certificate |

---

## Deployment Steps

### Prerequisites

- AWS CLI configured (`aws configure`)
- Terraform installed
- Docker installed
- SSH key pair generated
- GitHub repository secrets configured
- Docker Hub account

### Step 1 — Generate SSH Key

```bash
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa
```

### Step 2 — Provision Infrastructure

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

Note the `server_ip` output — you will need it for:
- GitHub `EC2_HOST` secret
- DuckDNS domain configuration

### Step 3 — Configure DuckDNS

1. Go to [duckdns.org](https://duckdns.org)
2. Point `studybud.duckdns.org` to your EC2 public IP

### Step 4 — Add GitHub Secrets

Go to your repo → **Settings → Secrets → Actions** and add all 6 secrets listed above.

### Step 5 — Push to Main Branch

```bash
git push origin main
```

GitHub Actions handles everything automatically:
- Testing → Building → Scanning → Deploying

### Step 6 — Verify Deployment

```bash
# Check app is live
curl https://studybud.duckdns.org/health/

# Expected response
{"status": "healthy"}
```

---

## Monitoring & Logging

**AWS CloudWatch** is used for centralized monitoring and logging.

### Log Groups

| Log Group | Stream | Content |
|-----------|--------|---------|
| `/studybud/app` | `nginx-access` | All HTTP requests |
| `/studybud/app` | `nginx-error` | Nginx errors |

### CloudWatch Alarms

| Alarm | Threshold | Action |
|-------|-----------|--------|
| `ec2-cpu-high` | CPU > 80% for 2 periods | Alert |
| `ec2-status-check-failed` | Status check failed | Alert |

### CloudWatch Agent

The CloudWatch agent is installed and configured automatically by `deploy.sh` on first deployment. It collects Nginx access and error logs and ships them to CloudWatch in real time.

---

## Security

| Measure | Implementation |
|---------|---------------|
| HTTPS | Certbot + Let's Encrypt SSL |
| Container scanning | Trivy on every pipeline run |
| IAM least privilege | EC2 role with minimal permissions |
| SSH key authentication | No password SSH |
| GitHub Secrets | No credentials in source code |
| Security Groups | Only required ports open |
| Nginx reverse proxy | App not exposed directly |

---

## Design Decisions

**Two-tier over three-tier architecture**
A two-tier architecture (application + SQLite database) was chosen over three-tier to keep the solution clean and focused. The evaluation criteria prioritizes automation and completeness over complexity. A well-executed two-tier solution scores higher than a partially working three-tier one.

**EC2 over ECS/EKS**
EC2 was chosen to demonstrate core infrastructure skills — security groups, IAM roles, SSH automation, and server configuration. ECS/EKS abstracts too much of this for a challenge focused on DevOps fundamentals.

**Docker Hub over ECR**
Docker Hub eliminates AWS-specific registry setup, simplifies the pipeline, and keeps the solution accessible without additional IAM configuration for image pulling.

**GitHub Actions over Jenkins**
GitHub Actions provides native integration with the repository, requires no separate server to maintain, and delivers a cleaner pipeline configuration for this use case.

**Gunicorn over Django dev server**
Django's `runserver` is single-threaded and explicitly not intended for production. Gunicorn handles concurrent requests properly and is the industry standard for Django production deployments.

**Git SHA image tagging**
Every Docker image is tagged with its Git commit SHA. This ensures immutable deployments, full traceability, and easy rollback to any previous version.

**Nginx as reverse proxy**
Nginx handles SSL termination, static file serving, and proxying to the Gunicorn container. This follows production best practices and removes static file responsibility from the Django application.

**Certbot for SSL**
Let's Encrypt via Certbot provides free, automated, production-grade SSL certificates. The `deploy.sh` script handles both first-time provisioning and certificate renewal automatically.

**t3.micro instance type**
`t3.micro` is the free tier eligible instance type for this AWS account region. `t2.micro` was not available, so `t3.micro` was selected as the appropriate free tier alternative.

---

## Assumptions

- AWS free tier account with `t3.micro` as the eligible instance type
- Single environment deployment (no staging/production separation required)
- SQLite is acceptable as the database tier for this challenge scope
- Public subnet deployment is acceptable — no bastion host required
- DuckDNS provides a suitable free domain for SSL certificate provisioning
- EC2 public IP may change on instance restart (Elastic IP not provisioned to stay within free tier)

---

## Limitations & Future Improvements

| Limitation | Improvement |
|------------|-------------|
| Single EC2 instance | Auto Scaling Group for high availability |
| SQLite database | RDS PostgreSQL for production scale |
| No remote Terraform state | S3 backend + DynamoDB state locking |
| EC2 public IP changes on restart | Elastic IP allocation |
| No multi-environment support | Separate staging and production environments |
| No blue/green deployment | Zero-downtime deployments with ALB |
| Basic monitoring | Prometheus + Grafana for advanced observability |
| No automated rollback | Rollback mechanism on deployment failure |
| Single AZ deployment | Multi-AZ for fault tolerance |

---

## Screenshots

### 1. Infrastructure Provisioning

**terraform init**
> *(Screenshot: Terminal showing `Terraform has been successfully initialized`)*

**terraform plan**
> *(Screenshot: Terminal showing planned resources)*

**terraform apply**
> *(Screenshot: Terminal showing `Apply complete! Resources: X added` with EC2 IP in outputs)*

---

### 2. AWS Console

**EC2 Instance Running**
> *(Screenshot: AWS Console → EC2 → Instances showing green `Running` status)*

**Security Group Inbound Rules**
> *(Screenshot: AWS Console → EC2 → Security Groups showing ports 22, 80, 443, 8000)*

**CloudWatch Log Groups**
> *(Screenshot: AWS Console → CloudWatch → Log Groups showing `/studybud/app`)*

**CloudWatch Log Streams**
> *(Screenshot: AWS Console → CloudWatch → `/studybud/app` showing `nginx-access` and `nginx-error` streams)*

**CloudWatch Alarms**
> *(Screenshot: AWS Console → CloudWatch → Alarms showing `ec2-cpu-high` and `ec2-status-check-failed`)*

---

### 3. CI/CD Pipeline

**All Pipeline Jobs Green**
> *(Screenshot: GitHub → Actions → latest run showing all 4 jobs green ✅)*

**Test Job Logs**
> *(Screenshot: GitHub → Actions → Test job expanded showing `manage.py check` and `manage.py test` passing)*

**Build Job Logs**
> *(Screenshot: GitHub → Actions → Build job showing Docker image pushed to Docker Hub)*

**Security Scan Job Logs**
> *(Screenshot: GitHub → Actions → Security Scan job showing Trivy scan results)*

**Deploy Job Logs**
> *(Screenshot: GitHub → Actions → Deploy job showing deployment complete)*

---

### 4. Docker Hub

**Docker Hub Repository**
> *(Screenshot: hub.docker.com showing `studybud` repository)*


---

### 5. DuckDNS

**Domain Configuration**
> *(Screenshot: duckdns.org dashboard showing `studybud.duckdns.org` pointing to EC2 IP)*

---

### 6. GitHub

**GitHub Secrets**
> *(Screenshot: GitHub → Settings → Secrets → Actions showing all 6 secret names)*

---

### 7. Application Live

**App Running in Browser**
> *(Screenshot: Browser showing `https://studybud.duckdns.org` with full styling)*


**Health Endpoint**
> *(Screenshot: Browser showing `https://studybud.duckdns.org/health/` returning `{"status": "healthy"}`)*

---

---

## Repository

GitHub: [https://github.com/Cybertemi/two-tier-cloud-cli-cd-Studybud-](https://github.com/Cybertemi/two-tier-cloud-cli-cd-Studybud-)

Live Application: [https://studybud.duckdns.org](https://studybud.duckdns.org)

## Author

Temitope Ilori Cloud DevOps Engineer