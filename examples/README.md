# Examples

| Example | |
|---|---|
| [`demo-k8s-cluster/`](demo-k8s-cluster/) | Cluster on managed node groups |
| [`demo-k8s-cluster-auto/`](demo-k8s-cluster-auto/) | Cluster on [EKS Auto Mode](../README.md#eks-auto-mode) |
| [`demo-app/`](demo-app/) | FastAPI "hello world" app with a Helm chart, for either cluster |

The cluster examples use the local module (`source = "../.."`). In your own project, use `danangan/k8s/aws` from the registry.

Commands run from the repo root.

## Prerequisites

AWS CLI, Terraform >= 1.7.0, kubectl, Helm, and Docker or Podman.

Log in to AWS first, e.g. `aws login`, `aws sso login` or `aws configure`.

## Provision a cluster

### Managed node groups (`demo-k8s-cluster`)

```
cd examples/demo-k8s-cluster
terraform init
terraform apply
```

The first apply fails - run it again. See [the bootstrap catch](../README.md#the-bootstrap-catch).

### EKS Auto Mode (`demo-k8s-cluster-auto`)

```
cd examples/demo-k8s-cluster-auto
terraform init
terraform apply
aws eks update-kubeconfig --region us-east-1 --name platform-cluster-auto
kubectl apply -f auto-mode/
```

`auto-mode/` holds what Auto Mode doesn't create itself:

- `ingress-class.yaml` - the `alb` IngressClass. Required for any Ingress
- `storage-class.yaml` - a default, encrypted gp3 StorageClass
- `graviton-node-pool.yaml` - arm64 nodes. The built-in pools are amd64 only
- `gpu-node-pool.yaml` - `g4dn.xlarge` GPU nodes, tainted `gpu-workload=true:NoSchedule`

## Deploy the demo app

```
cd examples/demo-app
./deploy.sh                          # managed node group cluster
./deploy.sh ../demo-k8s-cluster-auto # Auto Mode cluster
```

It builds the image, pushes it to the cluster's ECR repo and installs the Helm chart. The app is served on the ALB's DNS name.

## Tear down

```
cd examples/demo-app
./teardown.sh

cd ../demo-k8s-cluster   # or ../demo-k8s-cluster-auto
terraform destroy
```

Delete any PersistentVolumeClaims before `terraform destroy`, or their EBS volumes are left behind.
