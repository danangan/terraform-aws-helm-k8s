# Kubernetes Terraform Module for AWS EKS

[![Terraform](https://img.shields.io/badge/Terraform-7B42BC?style=flat&logo=terraform&logoColor=white)](https://www.terraform.io/)
[![AWS](https://img.shields.io/badge/AWS-232F3E?style=flat&logo=amazonaws&logoColor=white)](https://aws.amazon.com/)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?style=flat&logo=kubernetes&logoColor=white)](https://kubernetes.io/)
[![Helm](https://img.shields.io/badge/Helm-0F1689?style=flat&logo=helm&logoColor=white)](https://helm.sh/)

This reusable Terraform module handles everything needed to stand up a production-ready Kubernetes cluster on AWS EKS:

- A VPC (public + private subnets across multiple AZs, Internet & NAT gateway`)
- An EKS cluster with a CPU node group and a GPU node group
- An ECR repository, and a permissions-boundary-scoped IAM deployment role/user for CI/CD
- The AWS Load Balancer Controller, so `Ingress` resources with `ingressClassName: alb` provision an ALB out of the box
- The EBS CSI driver, with gp3 as the default StorageClass for PersistentVolumeClaims
- Optionally, [EKS Auto Mode](#eks-auto-mode) instead of the node groups and controller above, so EKS manages the nodes, ingress and storage itself

This module is published on the public Terraform Registry as [`danangan/k8s/aws`](https://registry.terraform.io/modules/danangan/k8s/aws/latest).

Point it at your AWS account and you'll have a cluster ready for your containerized workloads in minutes - no manual wiring required.

## Contents

- [Requirements](#requirements)
- [Example usage](#example-usage)
- [The bootstrap catch](#the-bootstrap-catch)
- [Deploying pods into the GPU nodes](#deploying-pods-into-the-gpu-nodes)
- [Add-ons](#add-ons)
- [EKS Auto Mode](#eks-auto-mode)
- [Project structure](#project-structure)
- [Trying it out (via the example)](#trying-it-out-via-the-example)

## Requirements

| Name | Version |
|------|---------|
| Terraform | >= 1.7.0 (pinned by the example; the module itself does not set `required_version`) |
| [aws provider](https://registry.terraform.io/providers/hashicorp/aws) | ~> 6.0 |
| [helm provider](https://registry.terraform.io/providers/hashicorp/helm) | ~> 3.0 |

The full list of inputs and outputs is generated on the [Terraform Registry page](https://registry.terraform.io/modules/danangan/k8s/aws/latest) from `variables.tf` and `outputs.tf`.

## Example usage

```hcl
provider "aws" {}

# This is an important setup to allow Terraform to install the Ingress Controller to the k8s cluster
provider "helm" {
  kubernetes = {
    host                   = module.platform.cluster_endpoint
    cluster_ca_certificate = base64decode(module.platform.cluster_certificate_authority_data)

    exec = {
      api_version = "client.authentication.k8s.io/v1"
      # In this example, we are using the `aws eks` command to authenticate to the k8s API.
      # For local use, authenticate to AWS first, e.g. via "aws login" or "aws sso login".
      # On a remote machine (e.g. your CI/CD workflow), authenticate via a static access key with "aws configure" instead.
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", local.cluster_name, "--region", local.region]
    }
  }
}

module "platform" {
  source  = "danangan/k8s/aws"
  version = "~> 1.0"

  cluster_name = "my-other-project"
}
```

## The bootstrap catch

**Warning:** this module needs to be applied twice on a brand new deployment. The first run will always fail - this is expected.

The reason is that the `helm` provider depends on the cluster it's installing into, so the first apply fails while provisioning the ingress controller: authentication fails because the provider is configured before the cluster it needs actually exists, and providers can't take a `depends_on`. The second apply succeeds, since the cluster is already in state by then.

This doesn't apply with `enable_auto_mode = true`: the ingress controller isn't installed then (Auto Mode has its own), so nothing goes through the `helm` provider.

If you'd rather avoid this, compose your own resources from the sub-modules in `modules/` across two separate root modules instead of one. For example, define your AWS resources in an `aws/` folder as its own root module, and the ingress in a separate `k8s/` folder as its own root module:

In `aws/main.tf`:
```hcl
module "network" {
  source  = "danangan/k8s/aws//modules/network"
  version = "~> 1.0"

  cluster_name = "my-cluster"
}

module "eks" {
  source  = "danangan/k8s/aws//modules/eks"
  version = "~> 1.0"

  cluster_name = "my-cluster"

  vpc_id     = module.network.vpc_id
  subnet_ids = module.network.private_subnets
}

module "ecr" {
  source  = "danangan/k8s/aws//modules/ecr"
  version = "~> 1.0"

  repository_name = "my-cluster-repo"
}

module "deployment" {
  source  = "danangan/k8s/aws//modules/deployment"
  version = "~> 1.0"

  cluster_name          = "my-cluster"
  cluster_arn           = module.eks.cluster_arn
  deployment_user_name  = "deployer"
  ecr_repository_arn    = module.ecr.repository_arn
}
```

In `k8s/main.tf`:
```hcl
module "alb_controller" {
  source  = "danangan/k8s/aws//modules/alb-controller"
  version = "~> 1.0"

  cluster_name = "my-cluster"
  vpc_id       = var.vpc_id # the `aws` root module's `network.vpc_id` output, passed in by hand or via remote state
}
```

## Deploying pods into the GPU nodes

GPU nodes are expensive, so we should only use them sparingly and only deploy relevant workloads onto that node group. To do so, we can leverage Kubernetes' [taints and tolerations](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/) feature. To deploy pods into the GPU nodes, you'd need to provision your workload with the following tolerations:
```
tolerations:
- key: "gpu-workload"
  operator: "Equal"
  value: "true"
  effect: "NoSchedule"
```

You can override this configuration in the module with `gpu_node_taints` variable.

With `enable_auto_mode = true` there's no GPU node group - apply [`examples/demo-k8s-cluster-auto/auto-mode/gpu-node-pool.yaml`](examples/demo-k8s-cluster-auto/auto-mode/gpu-node-pool.yaml) instead (see [EKS Auto Mode](#eks-auto-mode)), which uses the same taint. GPU pods also need to request `nvidia.com/gpu` in their resources: that's what makes Auto Mode launch a GPU node for them.

## Add-ons

On the managed node groups (the default), the module installs these EKS add-ons:

- `coredns`, `kube-proxy`, `vpc-cni` and `eks-pod-identity-agent`
- `aws-ebs-csi-driver`, with its own IAM role through EKS Pod Identity. It also creates `ebs-csi-default-sc`, the cluster's default StorageClass, so PersistentVolumeClaims get gp3 EBS volumes. EKS's own `gp2` StorageClass is still there, but isn't the default.

Add more with `extra_addons`, keyed by add-on name. Each entry takes the same settings as an `addons` entry in [terraform-aws-modules/eks](https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/latest), such as `addon_version`, `configuration_values` or `pod_identity_association`:

```hcl
module "platform" {
  source  = "danangan/k8s/aws"
  version = "~> 1.0"

  cluster_name = "my-other-project"

  extra_addons = {
    metrics-server      = {}
    snapshot-controller = {}
  }
}
```

An entry named after a default add-on replaces that add-on's settings entirely - for `aws-ebs-csi-driver`, that includes its Pod Identity role. `extra_addons` is ignored with `enable_auto_mode = true`.

## EKS Auto Mode

Set `enable_auto_mode = true` to run the cluster on [EKS Auto Mode](https://docs.aws.amazon.com/eks/latest/userguide/automode.html). EKS then launches, patches and replaces the nodes itself, and runs the cluster's core components for you:

| | Default (`enable_auto_mode = false`) | Auto Mode (`enable_auto_mode = true`) |
|---|---|---|
| Nodes | `cpu` and `gpu` managed node groups, sized by the `cpu_*` / `gpu_*` inputs | Launched on demand from the built-in `general-purpose` and `system` node pools. The `cpu_*` / `gpu_*` inputs are ignored |
| Add-ons | CoreDNS, kube-proxy, VPC CNI, Pod Identity agent and EBS CSI driver, plus `extra_addons` - see [Add-ons](#add-ons) | Built in. `extra_addons` is ignored |
| Ingress | AWS Load Balancer Controller, installed via Helm | Built-in ALB/NLB controller - the `alb-controller` sub-module is skipped |
| Persistent volumes | EBS CSI driver add-on, with `ebs-csi-default-sc` (gp3) as the default StorageClass | Built-in EBS support. Apply `storage-class.yaml` for a default gp3 StorageClass |
| [Bootstrap catch](#the-bootstrap-catch) | First `apply` fails | Doesn't apply |

**Cost:** on top of the EC2 price, AWS charges a management fee for every node Auto Mode launches - in us-east-1, about 12% of the on-demand price for most instance types, and about 8% for `g4dn.xlarge` (see [EKS pricing](https://aws.amazon.com/eks/pricing/)). Auto Mode also doesn't launch anything smaller than `medium`, so there's no `t4g.small`.

**What you create yourself:** Auto Mode doesn't create an IngressClass, a StorageClass or a GPU node pool. The Auto Mode example ships manifests for them in [`examples/demo-k8s-cluster-auto/auto-mode/`](examples/demo-k8s-cluster-auto/auto-mode/) - apply them with `kubectl` once the cluster is up. They're kept out of Terraform on purpose: creating them from Terraform would need the `kubernetes` provider, and bring the bootstrap catch back.

| File | What it's for |
|---|---|
| `ingress-class.yaml` | An `alb` IngressClass backed by Auto Mode's ALB controller, so Ingresses with `ingressClassName: alb` keep working. Required for any Ingress |
| `storage-class.yaml` | A default, encrypted `gp3` StorageClass for PersistentVolumeClaims |
| `graviton-node-pool.yaml` | An arm64 node pool, tried before the built-in `general-purpose` pool (which is amd64 only). Needed for arm64 images, like the demo app's when built on an Apple Silicon Mac |
| `gpu-node-pool.yaml` | A `g4dn.xlarge` node pool with the same `gpu-workload` taint as the `gpu` node group |

**Switching an existing cluster:** uninstall apps that have an Ingress first (for the demo app, `./teardown.sh`), so the AWS Load Balancer Controller deletes their ALBs before Terraform removes it - otherwise those ALBs are left behind. Redeploy them after the switch; Auto Mode creates new ALBs, with new DNS names. Existing PersistentVolumes can't come along as they are: Auto Mode uses a different EBS provisioner (`ebs.csi.eks.amazonaws.com`), so volumes created by the EBS CSI driver add-on have to be migrated - see [AWS's migration guide](https://docs.aws.amazon.com/eks/latest/userguide/migrate-auto.html).

## Project structure

```
(repo root)/             # The module itself
modules/                 # The sub-modules it's composed of, usable on their own
                         # if you split the bootstrap catch across two root
                         # modules (see "The bootstrap catch" above)
  ...
examples/
  demo-k8s-cluster/      # A deployable example of k8s cluster
  demo-k8s-cluster-auto/ # The same cluster on EKS Auto Mode
    auto-mode/           # Manifests to apply once it's up
  demo-app/              # A minimal FastAPI "hello world" service + Helm chart,
                         # deployed onto the example cluster's Ingress.
```

## Trying it out (via the example)

### Prerequisites

- AWS CLI, configured with credentials that can manage the resources below
- Terraform (>= 1.7.0)
- kubectl
- Helm
- Docker (or another Docker-compatible CLI, e.g. Podman) - to build and push the demo app image

### 1. Provision the cluster and the Ingress controller

Log in with the AWS CLI first, so Terraform has credentials to work with - e.g. `aws login` (requires AWS CLI >= 2.32.0) for browser-based console credentials, `aws sso login` if you use IAM Identity Center, or `aws configure` for a static access key/secret:

```
aws login
```

Then, from `examples/demo-k8s-cluster`:

```
cd examples/demo-k8s-cluster
terraform init
terraform apply
```

As mentioned in [The bootstrap catch](#the-bootstrap-catch) above, you'll hit an error on the first apply - just re-run `terraform apply` and it should succeed. Any subsequent update after the second apply works as expected.

To try [EKS Auto Mode](#eks-auto-mode) instead, use `examples/demo-k8s-cluster-auto`. One `terraform apply` is enough there. Afterwards, point `kubectl` at the cluster and apply the Auto Mode manifests:

```
cd examples/demo-k8s-cluster-auto
terraform init
terraform apply
aws eks update-kubeconfig --region us-east-1 --name platform-cluster-auto
kubectl apply -f auto-mode/
```

### 2. Build and deploy the demo app

The demo app (`examples/demo-app/`) is a FastAPI service built with `uv` inside its Dockerfile (no local `uv` install needed). Build its image, push it to the ECR repo Terraform just created, and roll it out with Helm:

```
cd examples/demo-app
./deploy.sh
```

For the Auto Mode cluster, pass its directory: `./deploy.sh ../demo-k8s-cluster-auto`.

Once deployed, the app is reachable at the ALB's DNS name - available in the AWS Console or via the AWS CLI.

### Tearing it down

Optionally uninstall the app first, so a clean `helm uninstall` is recorded before the cluster disappears from under it:

```
cd examples/demo-app
./teardown.sh
```

Then tear down the cluster:

```
cd examples/demo-k8s-cluster   # or examples/demo-k8s-cluster-auto
terraform destroy
```

This destroys everything (Ingress controller, EKS cluster, node groups, VPC, ECR, IAM) in one pass.

If you created any PersistentVolumeClaims, delete them before destroying. Their EBS volumes are only deleted while the cluster is still running, so volumes still claimed at that point are left behind - and keep being billed.
