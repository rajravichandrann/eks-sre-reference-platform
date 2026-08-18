# EKS SRE Reference Platform

A hands-on AWS EKS reference platform demonstrating infrastructure engineering, Kubernetes reliability, secure CI/CD, observability, and SRE practices.

I built this project as a working environment for exploring not only how to deploy infrastructure, but how to operate it: identity, deployment safety, application health, telemetry, failure modes, and production trade-offs.

## What I Have Implemented

### AWS and Terraform

- Terraform-managed AWS infrastructure
- VPC spanning two Availability Zones
- Public and private subnets
- Private EKS worker nodes
- Configurable single-NAT lab design or NAT-per-AZ design
- Amazon EKS managed control plane
- EKS managed node group
- KMS encryption for Kubernetes Secrets
- EKS control-plane logging
- ECR with immutable image tags and image scanning
- S3 remote Terraform state with native state locking

### GitHub Actions and CI/CD

- GitHub Actions OIDC federation to AWS
- AWS STS temporary credentials instead of stored AWS access keys
- Terraform format, validation, init, and plan workflow
- Docker Buildx / BuildKit image builds
- GitHub Actions BuildKit cache
- Images pushed to ECR using immutable Git SHA tags

### Kubernetes Reliability

- Two application replicas
- Rolling deployments
- `maxUnavailable: 0`
- `maxSurge: 1`
- Startup probes
- Readiness probes
- Liveness probes
- CPU and memory requests / limits
- PodDisruptionBudget
- Non-root containers
- Read-only root filesystem
- Linux capabilities dropped
- Privilege escalation disabled
- RuntimeDefault seccomp profile

### Application Observability

The reference application is a small FastAPI service instrumented using the Prometheus Python client.

It exposes:

```text
/healthz
/readyz
/work
/metrics
```

The `/work` endpoint supports intentional latency and failures so reliability behavior can be tested:

```bash
curl localhost:8080/work

curl "localhost:8080/work?delay_ms=500"

curl -i "localhost:8080/work?fail=true"
```

Application metrics include:

- request count
- HTTP status
- request latency histogram

Health checks and monitoring traffic are excluded from the application metrics so probes do not distort user-facing reliability measurements.

## Observability Architecture

This project does not run a Prometheus server.

The application uses the Prometheus client library to expose Prometheus/OpenMetrics-compatible metrics. The Datadog Agent discovers the workload and scrapes `/metrics` using the Datadog OpenMetrics integration.

```text
FastAPI
   |
   | Counter + Histogram
   v
Prometheus Python Client
   |
   v
/metrics
   |
   | Prometheus/OpenMetrics format
   v
Datadog Agent
   |
   | OpenMetrics integration
   v
Datadog
```

Current Datadog application metrics include:

```text
eks_sre_reference.http_requests.count

eks_sre_reference.http_request_duration_seconds

eks_sre_reference.http_request_duration_seconds.count

eks_sre_reference.http_request_duration_seconds.sum
```

## Platform Architecture

```text
                         GitHub
                            |
                      GitHub Actions
                            |
                       OIDC token
                            |
                            v
                         AWS STS
                            |
                +-----------+-----------+
                |                       |
            Terraform                 Buildx
                |                       |
                v                       v
        AWS Infrastructure             ECR
                |                       |
                |                       |
                +----------+------------+
                           |
                           v
                          EKS
                           |
                   Kubernetes Pods
                           |
                        FastAPI
                           |
                       /metrics
                           |
                    Datadog Agent
                           |
                           v
                        Datadog
```

## Reliability Scenario: Failed Rolling Deployment

During Kubernetes workload hardening, a replacement Pod failed with:

```text
CreateContainerConfigError
```

I investigated the Pod using:

```bash
kubectl describe pod
```

The Events showed that `runAsNonRoot` could not verify the container's non-numeric Docker user.

The image created a user named:

```text
appuser
```

with UID `10001`, but Kubernetes could not infer from the username that the process was non-root.

I fixed the problem by explicitly configuring:

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 10001
```

The rolling deployment configuration was:

```yaml
rollingUpdate:
  maxUnavailable: 0
  maxSurge: 1
```

Because of that configuration, Kubernetes kept the existing healthy replicas running while the replacement Pod failed.

This demonstrated both a debugging workflow and the value of safe rollout controls.

## Important Design Trade-offs

This is a cost-controlled reference environment, not a claim that a single-node lab is a production HA architecture.

| Current Lab Design | Production Evolution |
|---|---|
| One worker node by default | Multiple nodes distributed across Availability Zones |
| Two Pods can share one node | Topology spread / pod anti-affinity across nodes |
| Single NAT gateway | NAT per AZ or another resilient egress design |
| ClusterIP + port-forward | ALB / Ingress, DNS, and TLS |
| Restricted public EKS API | Private administrative access path |
| Shared CI AWS role | Separate least-privilege Terraform, build, and deploy roles |
| Kubernetes Secret for Datadog key | AWS Secrets Manager / External Secrets |
| VPC CNI permissions on node role | Dedicated pod identity / IRSA |

The Terraform node group currently supports:

```text
minimum: 1
desired: 1
maximum: 4
```

This allows later autoscaling exercises without Terraform continuously resetting the autoscaler's desired node count.

## Repository Structure

```text
.
├── .github/workflows/
│   ├── terraform.yaml
│   └── build_image.yaml
│
├── app/
│   ├── Dockerfile
│   ├── main.py
│   └── requirements.txt
│
├── k8s/
│   └── app.yaml
│
├── observability/
│   └── datadog-agent.yaml
│
└── terraform/
    ├── bootstrap/
    ├── modules/
    │   ├── vpc/
    │   ├── eks/
    │   └── ecr/
    ├── backend.tf
    └── main.tf
```

## What I Am Building Next

The next stages build on the telemetry and reliability controls already implemented:

- Datadog request-rate dashboard
- HTTP 5xx error-rate dashboard
- p95 / p99 latency
- Availability and latency SLIs
- SLOs and error budgets
- SLO burn-rate alerting
- Horizontal Pod Autoscaling
- EKS node autoscaling
- k6 load testing
- Capacity exhaustion testing
- Pod and node failure experiments
- Dependency latency and failure injection
- GitHub Actions CI Visibility
- OpenTelemetry tracing

## Purpose of the Project

The goal of this repository is to make SRE engineering decisions visible and testable.

Examples include:

- Which identity is actually making an AWS API call?
- How should GitHub Actions authenticate to AWS without static credentials?
- What happens when a Kubernetes rollout fails halfway through?
- What is the difference between startup, readiness, and liveness probes?
- What does a PodDisruptionBudget protect against?
- Why do two replicas on one node not provide node-level high availability?
- How should application availability and latency be measured?
- How do Prometheus metrics become Datadog metrics through OpenMetrics?
- What would need to change before this architecture was used for a production workload?

The infrastructure is the implementation; understanding and testing reliability behavior is the main purpose of the project.