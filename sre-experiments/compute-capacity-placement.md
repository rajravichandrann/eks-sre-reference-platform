# Compute Capacity, Placement, Autoscaling, and Node-Failure Experiments

These experiments turn the EKS reference platform into a repeatable compute-behavior lab.

The goal is not to claim Big-scale infrastructure. The goal is to make the mechanics visible:

```text
workload demand
      |
      v
pod resource requests
      |
      v
Kubernetes scheduler
      |
      +---- capacity available ----> pod placed
      |
      +---- insufficient capacity -> Pending
                                      |
                                      v
                              node capacity changes
                                      |
                                      v
                                pod placement
```

The experiments deliberately separate **pod autoscaling** from **node capacity** because they are different control loops.

## Prerequisites

- Existing EKS reference platform deployed.
- `kubectl` configured for the cluster.
- AWS CLI authenticated to the same account/region.
- `k6` installed for the HPA load test.
- Kubernetes Metrics Server installed for CPU-based HPA.

Install Metrics Server with Helm:

```bash
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm repo update

helm upgrade --install metrics-server metrics-server/metrics-server \
  --namespace kube-system \
  --create-namespace
```

Validate:

```bash
kubectl top nodes
kubectl top pods
```

## Experiment 1: Capacity exhaustion and scheduler placement

The reference node group starts at:

```text
minimum: 1
desired: 1
maximum: 4
instance type: t3.medium
```

Apply a workload whose **resource requests**, not actual CPU consumption, create scheduling pressure:

```bash
kubectl apply -f k8s/capacity-pressure.yaml
kubectl get pods -l app=capacity-pressure -o wide
```

Watch placement and Pending pods:

```bash
kubectl get pods -l app=capacity-pressure -o wide -w
```

Inspect one Pending pod:

```bash
POD=$(kubectl get pods -l app=capacity-pressure \
  --field-selector=status.phase=Pending \
  -o jsonpath='{.items[0].metadata.name}')

kubectl describe pod "$POD"
```

Look for scheduler events such as `FailedScheduling` and `Insufficient cpu`.

This is the important distinction:

- a container does **not** need to consume 900m CPU to create placement pressure;
- the scheduler reasons about requested resources;
- a workload can remain Pending even when current node CPU utilization looks low.

### Expand node capacity

The Terraform module intentionally ignores `desired_size` drift so an autoscaling mechanism can own desired capacity later.

For this experiment, increase desired node-group capacity manually:

```bash
CLUSTER=eks-sre-reference-dev

aws eks update-nodegroup-config \
  --cluster-name "$CLUSTER" \
  --nodegroup-name general \
  --scaling-config minSize=1,maxSize=4,desiredSize=3
```

Watch nodes and pods:

```bash
kubectl get nodes -w
```

In another terminal:

```bash
kubectl get pods -l app=capacity-pressure -o wide -w
```

Record:

- how many pods were Pending before capacity was added;
- the scheduler reason;
- how long it took new nodes to become Ready;
- when Pending pods became Scheduled/Running;
- which node each pod landed on.

Useful snapshot:

```bash
kubectl get pods -l app=capacity-pressure \
  -o custom-columns='POD:.metadata.name,PHASE:.status.phase,NODE:.spec.nodeName,START:.status.startTime'
```

Clean up:

```bash
kubectl delete -f k8s/capacity-pressure.yaml
```

Return to one node when the remaining experiments are complete:

```bash
aws eks update-nodegroup-config \
  --cluster-name "$CLUSTER" \
  --nodegroup-name general \
  --scaling-config minSize=1,maxSize=4,desiredSize=1
```

## Experiment 2: HPA under CPU load

This experiment demonstrates the **pod-level** scaling loop.

The application `/work` endpoint accepts `cpu_ms`, which performs bounded CPU work. That makes HPA behavior reproducible without adding a separate benchmark application.

Deploy the current application image and HPA:

```bash
kubectl apply -f k8s/app.yaml
kubectl apply -f k8s/hpa.yaml
```

Validate metrics:

```bash
kubectl top pods -l app=eks-sre-reference-app
kubectl get hpa eks-sre-reference-app
```

Port-forward the service:

```bash
kubectl port-forward svc/eks-sre-reference-app 8080:80
```

Run load in another terminal:

```bash
BASE_URL=http://127.0.0.1:8080 k6 run load-tests/hpa.js
```

Watch the scaling decision:

```bash
kubectl get hpa eks-sre-reference-app -w
```

Also watch pod placement:

```bash
kubectl get pods -l app=eks-sre-reference-app -o wide -w
```

Questions to answer from the run:

1. At what observed CPU utilization did HPA increase desired replicas?
2. How long passed between sustained load and new Ready replicas?
3. Did all desired replicas schedule?
4. If replicas became Pending, was the limiting factor **pod scaling** or **node capacity**?
5. What happened to p95 latency during the scale-out window?
6. How long did scale-down take after load stopped?

That fourth question is the key systems point: HPA can ask for more pods while the scheduler has nowhere to place them.

## Experiment 3: Node drain and workload recovery

Start with at least two Ready nodes:

```bash
aws eks update-nodegroup-config \
  --cluster-name "$CLUSTER" \
  --nodegroup-name general \
  --scaling-config minSize=1,maxSize=4,desiredSize=2

kubectl get nodes -w
```

Confirm application placement:

```bash
kubectl get pods -l app=eks-sre-reference-app -o wide
```

Choose one worker node:

```bash
NODE=$(kubectl get nodes \
  -l eks.amazonaws.com/nodegroup=general \
  -o jsonpath='{.items[0].metadata.name}')

echo "$NODE"
```

Cordon it first:

```bash
kubectl cordon "$NODE"
```

Inspect what is on the node:

```bash
kubectl get pods -A --field-selector spec.nodeName="$NODE" -o wide
```

Drain while respecting normal eviction behavior and the application's PodDisruptionBudget:

```bash
kubectl drain "$NODE" \
  --ignore-daemonsets \
  --delete-emptydir-data
```

Observe:

```bash
kubectl get pods -l app=eks-sre-reference-app -o wide -w
```

Record:

- which application pod was evicted;
- whether the PDB constrained the disruption;
- how long replacement placement/readiness took;
- whether there was sufficient capacity on the remaining node;
- whether the service remained available;
- what would change with topology spread constraints or pod anti-affinity.

Bring the node back:

```bash
kubectl uncordon "$NODE"
```

## Evidence to save from each experiment

Do not write conclusions before running the experiment. Save the real outputs.

Recommended evidence:

```bash
kubectl get nodes -o wide
kubectl get pods -A -o wide
kubectl get events --sort-by=.lastTimestamp
kubectl top nodes
kubectl top pods
kubectl describe pod <pending-pod>
kubectl get hpa
```

Also capture:

- Datadog request rate;
- p95 latency;
- 5xx rate;
- the availability SLO during the experiment window.

## What this demonstrates

These experiments make several compute-platform behaviors explicit:

- Kubernetes scheduling is request/capacity based.
- Pod autoscaling and node autoscaling/capacity are separate concerns.
- More desired replicas do not guarantee successful placement.
- Placement failures can be diagnosed from scheduler events.
- Capacity changes have a measurable time-to-ready.
- Node loss/drain tests both available capacity and disruption controls.
- PDBs reduce voluntary disruption risk but do not create replacement capacity.
- Reliability should be measured through the workload while infrastructure changes occur.

## Next iteration

The next iteration replaces manual node-group expansion with a real node autoscaler such as Karpenter or Kubernetes Cluster Autoscaler and measures:

```text
Pending pod
   |
   v
unschedulable signal
   |
   v
node provisioning decision
   |
   v
EC2 instance launch
   |
   v
node Ready
   |
   v
pod Scheduled
   |
   v
application Ready
```

That will let the repo measure the full queue/capacity/placement/startup path automatically.
