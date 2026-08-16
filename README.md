# eks-sre-reference-platform

A public reference platform for demonstrating production-oriented AWS EKS, Terraform, CI/CD, observability, autoscaling, load testing, and SRE failure experimentation.

## Roadmap

### Phase 1 — Infrastructure foundation
- VPC across two Availability Zones
- Public subnets for internet-facing load balancers / NAT
- Private subnets for EKS worker nodes
- Configurable single-NAT (lab) vs NAT-per-AZ (HA) design
- Amazon EKS managed control plane
- EKS managed node group using Amazon Linux 2023
- EKS control-plane logs
- KMS envelope encryption for Kubernetes Secrets
- EKS API authentication mode
- ECR repositories with immutable tags, scanning, and lifecycle policies

### Phase 2 — Identity and CI
- GitHub Actions OIDC -> AWS STS
- Least-privilege deploy roles
- EKS access entries
- IRSA for the VPC CNI and platform workloads
- Docker Buildx / BuildKit

### Phase 3 — Application delivery
- Sample application
- Kubernetes manifests / Helm
- ALB ingress
- readiness / liveness / startup probes
- requests / limits / disruption budgets

### Phase 4 — Observability
- Datadog agent
- OpenMetrics
- CI Visibility
- dashboards, monitors, logs, traces
- SLIs / SLOs / error budgets

### Phase 5 — Scaling and SRE experiments
- HPA
- cluster autoscaling / Karpenter comparison
- load testing
- node pressure
- pod eviction
- dependency latency / failures
- insufficient capacity experiments
- SLO burn-rate alerts

## Phase 1 architecture

```text
                        Internet
                           |
                    Internet Gateway
                           |
              +------------+------------+
              |                         |
       public subnet A             public subnet B
              |                         |
           NAT GW A               (NAT GW B in HA mode)
              |                         |
              +------------+------------+
                           |
              private subnet A     private subnet B
                    |                    |
                    +---- EKS nodes -----+
                           |
                     EKS control plane
                           |
                          ECR
```

The default lab configuration uses a single NAT gateway to keep cost down. Set `single_nat_gateway = false` for a NAT gateway per Availability Zone and better egress resilience.

## Prerequisites

- Terraform >= 1.8
- AWS CLI authenticated to a sandbox AWS account
- kubectl
- permissions to create VPC, IAM, KMS, EKS, EC2, CloudWatch Logs, and ECR resources

## Deploy Phase 1

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`, especially `cluster_public_access_cidrs`. Use your public IPv4 address as a `/32` instead of allowing the entire internet.

```bash
terraform init
terraform fmt -recursive
terraform validate
terraform plan -out=phase1.tfplan
terraform apply phase1.tfplan
```

Configure kubectl:

```bash
aws eks update-kubeconfig \
  --region us-east-1 \
  --name eks-sre-reference-dev

kubectl get nodes -o wide
kubectl get pods -A
```

## Destroy when you are done

This lab incurs hourly AWS charges, especially for EKS, EC2, and NAT Gateway resources.

```bash
terraform destroy
```

## Phase 1 design decisions worth discussing in an interview

1. **Private worker nodes.** Nodes do not need public IPv4 addresses; outbound access goes through NAT.
2. **Two Availability Zones.** The network is multi-AZ even though the cheap lab configuration can intentionally run only one worker node.
3. **Single NAT by default.** This is a cost optimization for a portfolio lab, not the HA production choice. The VPC module can switch to one NAT per AZ.
4. **Managed node groups instead of EKS Auto Mode.** Later phases intentionally expose node scaling, scheduling, and capacity behavior for SRE experiments.
5. **Restricted public EKS endpoint plus private endpoint.** Local administration is possible without exposing the API server to every address.
6. **EKS access API mode.** This prepares the repo for access entries rather than centering the legacy `aws-auth` ConfigMap.
7. **Control-plane logs enabled.** API, audit, authenticator, controller-manager, and scheduler signals are available for operational exercises.
8. **KMS encryption for Kubernetes Secrets.** The platform makes encryption an explicit design decision.
9. **IMDSv2 on nodes.** The launch template requires metadata tokens.
10. **Temporary CNI permission trade-off.** Phase 1 places `AmazonEKS_CNI_Policy` on the node role for bootstrap simplicity. Phase 2 will move it to IRSA and remove it from the node role.
11. **ECR immutable tags.** CI will publish unique image tags/digests instead of silently replacing deployed artifacts.
12. **No remote Terraform backend yet.** Backend bootstrap and CI ownership of Terraform state will be added with the GitHub OIDC phase rather than hiding a manual prerequisite.
