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
- Optionally, the [EFS CSI driver](#efs-storage) and an EFS file system, for volumes many pods can share
- Optionally, [EKS Auto Mode](#eks-auto-mode) instead of the node groups and controller above, so EKS manages the nodes, ingress and storage itself

This module is published on the public Terraform Registry as [`danangan/k8s/aws`](https://registry.terraform.io/modules/danangan/k8s/aws/latest).

Point it at your AWS account and you'll have a cluster ready for your containerized workloads in minutes - no manual wiring required.

## Contents

- [Requirements](#requirements)
- [Example usage](#example-usage)
- [The bootstrap catch](#the-bootstrap-catch)
- [Deploying pods into the GPU nodes](#deploying-pods-into-the-gpu-nodes)
- [Add-ons](#add-ons)
- [EFS storage](#efs-storage)
- [EKS Auto Mode](#eks-auto-mode)
- [Project structure](#project-structure)
- [Examples](#examples)

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

module "storage" {
  source  = "danangan/k8s/aws//modules/storage"
  version = "~> 1.0"

  cluster_name       = module.eks.cluster_name
  kubernetes_version = "1.33"

  depends_on = [module.eks] # the add-on needs the nodes up
}

# Optional - see "EFS storage" below
module "efs" {
  source  = "danangan/k8s/aws//modules/efs"
  version = "~> 1.0"

  cluster_name       = module.eks.cluster_name
  kubernetes_version = "1.33"

  vpc_id     = module.network.vpc_id
  subnet_ids = module.network.private_subnets

  depends_on = [module.eks] # the add-on needs the nodes up
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
- `aws-ebs-csi-driver`, through the [`storage`](modules/storage/) sub-module, which follows [AWS's EBS CSI driver guide](https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html): an IAM role with `AmazonEBSCSIDriverPolicyV2` through EKS Pod Identity, then the add-on itself. It also creates `ebs-csi-default-sc`, the cluster's default StorageClass, so PersistentVolumeClaims get gp3 EBS volumes. EKS's own `gp2` StorageClass is still there, but isn't the default.

The EFS CSI driver is opt-in - see [EFS storage](#efs-storage).

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

An entry named after one of the four default add-ons above replaces that add-on's settings entirely - e.g. overriding `vpc-cni` drops its `before_compute = true`, so set it again. `extra_addons` is ignored with `enable_auto_mode = true`.

## EFS storage

An EBS volume attaches to one node at a time. An [Amazon EFS](https://docs.aws.amazon.com/efs/latest/ug/whatisefs.html) file system can be mounted by many pods at once, across nodes and AZs (`ReadWriteMany`), and grows as you write to it. Set `enable_efs_csi_driver = true` to use one:

```hcl
module "platform" {
  source  = "danangan/k8s/aws"
  version = "~> 1.0"

  cluster_name = "my-other-project"

  enable_efs_csi_driver = true
}
```

The module then creates the [`efs`](modules/efs/) sub-module's resources, which follow [AWS's EFS CSI driver guide](https://docs.aws.amazon.com/eks/latest/userguide/efs-csi.html):

1. An IAM role with `AmazonEFSCSIDriverPolicy`, granted through EKS Pod Identity
2. The `aws-efs-csi-driver` EKS add-on
3. An encrypted EFS file system with a mount target in each private subnet, behind a security group that allows NFS (TCP 2049) in from the VPC

It's off by default. It works with or without [EKS Auto Mode](#eks-auto-mode), which doesn't have EFS support built in.

The EFS add-on can't create a StorageClass the way the EBS add-on does, so create one with `kubectl` once the cluster is up. The file system's ID is the module's `efs_file_system_id` output. Pass it through as an output of your own root module (as [`examples/demo-k8s-cluster`](examples/demo-k8s-cluster/main.tf) does), then run this from that module's folder:

```
kubectl apply -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: efs-sc
provisioner: efs.csi.aws.com
parameters:
  provisioningMode: efs-ap
  fileSystemId: $(terraform output -raw efs_file_system_id)
  directoryPerms: "700"
EOF
```

This uses [dynamic provisioning](https://github.com/kubernetes-sigs/aws-efs-csi-driver/blob/master/examples/kubernetes/efs/dynamic_provisioning/README.md): each PersistentVolumeClaim gets its own EFS access point, a directory on the file system that only that claim's pods can see. `ebs-csi-default-sc` stays the default StorageClass, so claims have to name `efs-sc`:

```
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: shared-data
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: efs-sc
  resources:
    requests:
      storage: 5Gi # required by Kubernetes, but EFS doesn't enforce a size
```

**Warning:** setting `enable_efs_csi_driver` back to `false` deletes the file system and everything on it. Delete any claims that use `efs-sc` first, while the driver is still there to clean up their access points.

## EKS Auto Mode

Set `enable_auto_mode = true` to run the cluster on [EKS Auto Mode](https://docs.aws.amazon.com/eks/latest/userguide/automode.html): EKS launches, patches and removes the EC2 nodes itself as pods need them, and runs networking, EBS storage and the ALB controller for you. The module then skips the node groups, add-ons and ALB controller.

Nodes come from node pools. EKS enables two built-in ones, `general-purpose` and `system`, but they only launch amd64 C/M/R instances - for anything else, add your own `NodePool` with `kubectl` once the cluster is up. The Auto Mode example has two to start from:

- [`graviton-node-pool.yaml`](examples/demo-k8s-cluster-auto/auto-mode/graviton-node-pool.yaml) - arm64 instances, e.g. for images built on an Apple Silicon Mac
- [`gpu-node-pool.yaml`](examples/demo-k8s-cluster-auto/auto-mode/gpu-node-pool.yaml) - `g4dn.xlarge` GPU nodes, tainted like the `gpu` node group

```
kubectl apply -f examples/demo-k8s-cluster-auto/auto-mode/
```

That folder also has the IngressClass and StorageClass Auto Mode needs - see the [examples README](examples/README.md#eks-auto-mode-demo-k8s-cluster-auto).

## Project structure

```
(repo root)/             # The module itself
modules/                 # The sub-modules it's composed of, usable on their own
                         # if you split the bootstrap catch across two root
                         # modules (see "The bootstrap catch" above)
  ...
examples/                # Deployable example clusters and a demo app - see
                         # "Examples" below
```

## Examples

[`examples/`](examples/) has two deployable clusters - one on managed node groups, one on EKS Auto Mode - and a demo app to deploy onto either. The [examples README](examples/README.md) walks through provisioning them, deploying the app and tearing everything down.
