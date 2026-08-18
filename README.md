# EKS SRE Reference Platform

A hands-on AWS EKS reference platform demonstrating infrastructure engineering, Kubernetes reliability, secure CI/CD, observability, and SRE practices.

I built this project as a working environment for exploring not only how to deploy infrastructure, but how to operate it: identity, deployment safety, application health, telemetry, failure modes, service-level objectives, and production trade-offs.

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
- Node group configured with minimum, desired, and maximum capacity for later autoscaling exercises

### GitHub Actions and CI/CD

- GitHub Actions OIDC federation to AWS
- AWS STS temporary credentials instead of stored AWS access keys
- Repository and branch-bound OIDC trust policy
- Terraform format, validation, init, and plan workflow
- Docker Buildx / BuildKit image builds
- GitHub Actions BuildKit cache
- Images pushed to ECR using immutable Git SHA tags
- Workflow concurrency controls

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
- Explicit non-root UID
- Read-only root filesystem
- Linux capabilities dropped
- Privilege escalation disabled
- RuntimeDefault seccomp profile
- ClusterIP Service

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

Application telemetry includes:

- request count
- HTTP method
- HTTP route
- HTTP response status
- request latency histogram
- explicit latency buckets
- Prometheus/OpenMetrics-compatible `/metrics` endpoint

Health checks, readiness checks, and monitoring traffic are excluded from the application request metrics so probes and scrapes do not distort user-facing reliability measurements.

## Observability Architecture

This project does not run a Prometheus server.

The application uses the Prometheus Python client library to instrument requests and expose Prometheus/OpenMetrics-compatible metrics.

The Datadog Agent discovers the Kubernetes workload and directly scrapes `/metrics` using the Datadog OpenMetrics integration.

```text
FastAPI Application
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

This allows the application to use the Prometheus instrumentation ecosystem without operating a separate Prometheus monitoring backend.

### Datadog Integration

Implemented Datadog components include:

- Datadog Operator
- Datadog Agent on EKS
- Kubernetes Autodiscovery
- OpenMetrics workload scraping
- Kubernetes infrastructure metrics
- application custom metrics
- histogram-to-distribution collection for latency analysis

Current Datadog application metrics include:

```text
eks_sre_reference.http_requests.count

eks_sre_reference.http_request_duration_seconds

eks_sre_reference.http_request_duration_seconds.count

eks_sre_reference.http_request_duration_seconds.sum
```

The Datadog Agent has been validated directly with:

```bash
kubectl exec -n datadog <datadog-agent-pod> \
  -c agent -- agent status
```

The application OpenMetrics checks report successful collection of metric samples and histogram buckets from the application Pods.

## Reliability Dashboard

A Datadog reliability dashboard uses the application telemetry to visualize service behavior.

Current views include:

- request rate
- HTTP 5xx error rate
- p95 request latency

Conceptually:

```text
Request traffic
      |
      +------> Request Rate
      |
      +------> HTTP status labels
      |            |
      |            v
      |       5xx Error Rate
      |
      +------> Latency Histogram
                   |
                   v
              Distribution
                   |
                   v
                  p95
```

The latency metric is collected as a Datadog distribution so percentile aggregations can be used rather than relying only on averages.

## Availability SLO

The application has a count-based availability SLO in Datadog.

The SLI is:

```text
                 Good Requests
Availability = -----------------
               Good + Bad Requests
```

For the current reference workload:

```text
Good events = HTTP 200 responses
Bad events  = HTTP 500 responses
```

The current objective is:

```text
99.9% availability over a rolling 7-day window
```

This provides an error budget of:

```text
100% - 99.9% = 0.1%
```

The reliability flow is therefore:

```text
HTTP Request
     |
     v
FastAPI
     |
     v
Prometheus Counter / Histogram
     |
     v
OpenMetrics
     |
     v
Datadog
     |
     +------> Request Rate
     |
     +------> Error Rate
     |
     +------> p95 Latency
     |
     v
Availability SLI
     |
     v
99.9% SLO
     |
     v
0.1% Error Budget
```

Health checks, readiness checks, and `/metrics` scrapes are excluded from the underlying application request counter so infrastructure monitoring traffic does not artificially improve the SLI.

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

## Kubernetes Probe Behavior Tested

The application includes three separate health mechanisms.

### Startup Probe

Answers:

```text
Has the application successfully started yet?
```

A failing startup probe prevents Kubernetes from evaluating normal liveness behavior before the application has completed startup.

### Readiness Probe

Answers:

```text
Should this Pod receive traffic?
```

A Pod that fails readiness remains running but is removed from Service endpoints.

### Liveness Probe

Answers:

```text
Is this process unhealthy enough that Kubernetes should restart it?
```

Repeated liveness failures cause the kubelet to restart the container.

These behaviors were tested independently to demonstrate that readiness failures and liveness failures have different operational consequences.

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

Terraform ignores changes to the managed node group's desired capacity so an autoscaler can eventually control that value without Terraform continuously attempting to reset it.

## Terraform State and CI Identity

Terraform state is stored remotely in S3.

The state infrastructure includes:

- S3 versioning
- server-side encryption
- public-access blocking
- HTTPS-only bucket policy
- native S3 state locking

GitHub Actions authenticates to AWS using OIDC:

```text
GitHub Actions
      |
      | OIDC token
      v
AWS STS
      |
      | AssumeRoleWithWebIdentity
      v
Temporary AWS Credentials
```

This avoids storing long-lived AWS access keys in GitHub.

The trust relationship is restricted to the repository and `main` branch.

## Container Build and Delivery

The application image is built using Docker Buildx / BuildKit.

```text
Application Source
      |
      v
GitHub Actions
      |
      v
Buildx / BuildKit
      |
      +------> GitHub Actions layer cache
      |
      v
ECR
      |
      v
EKS
```

Images use immutable Git SHA tags:

```text
sha-<git-commit-sha>
```

This provides traceability from a deployed container image back to the source commit that produced it.

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

- SLO burn-rate alerting
- latency SLI and SLO
- Horizontal Pod Autoscaling
- EKS node autoscaling
- k6 load testing
- capacity exhaustion testing
- pod failure experiments
- node failure experiments
- dependency latency and failure injection
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
- Why is p95 more useful than an average for many latency investigations?
- How do Prometheus metrics become Datadog metrics through OpenMetrics?
- How does an application metric become an SLI?
- How does an SLI become an SLO and error budget?
- What would need to change before this architecture was used for a production workload?

The infrastructure is the implementation; understanding and testing reliability behavior is the main purpose of the project.