# Kubernetes Terraform Module for AWS EKS

[![Terraform](https://img.shields.io/badge/Terraform-7B42BC?style=flat&logo=terraform&logoColor=white)](https://www.terraform.io/)
[![AWS](https://img.shields.io/badge/AWS-232F3E?style=flat&logo=amazonaws&logoColor=white)](https://aws.amazon.com/)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?style=flat&logo=kubernetes&logoColor=white)](https://kubernetes.io/)
[![Helm](https://img.shields.io/badge/Helm-0F1689?style=flat&logo=helm&logoColor=white)](https://helm.sh/)

A reusable Terraform module that provisions:

- A VPC (public + private subnets across multiple AZs, single NAT gateway by default - multi-AZ NAT is available via `enable_multi_az_nat_gateway`)
- An EKS cluster with a CPU node group and a GPU node group
- An ECR repository, and a permissions-boundary-scoped IAM deployment role/user for CI/CD
- The AWS Load Balancer Controller, so `Ingress` resources with `ingressClassName: alb` provision an ALB out of the box

This module is published on the public Terraform Registry as [`danangan/k8s/aws`](https://registry.terraform.io/modules/danangan/k8s/aws/latest).

## Contents

- [Requirements](#requirements)
- [Example usage](#example-usage)
- [The bootstrap catch](#the-bootstrap-catch)
- [Deploying pods into the GPU nodes](#deploying-pods-into-the-gpu-nodes)
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

## Project structure

```
(repo root)/        # The module itself
modules/            # The sub-modules it's composed of, usable on their own
                    # if you split the bootstrap catch across two root
                    # modules (see "The bootstrap catch" above)
  ...
examples/
  demo-k8s-cluster/ # A deployable example of k8s cluster
  demo-app/         # A minimal FastAPI "hello world" service + Helm chart,
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

### 2. Build and deploy the demo app

The demo app (`examples/demo-app/`) is a FastAPI service built with `uv` inside its Dockerfile (no local `uv` install needed). Build its image, push it to the ECR repo Terraform just created, and roll it out with Helm:

```
cd examples/demo-app
./deploy.sh
```

Once the app is deployed, you can access it directly via the ALB DNS name. You can get this information via AWS console or via AWS CLI.

### Tearing it down

Optionally uninstall the app first, so a clean `helm uninstall` is recorded before the cluster disappears from under it:

```
cd examples/demo-app
./teardown.sh
```

Then tear down the cluster:

```
cd examples/demo-k8s-cluster
terraform destroy
```

This destroys everything (Ingress controller, EKS cluster, node groups, VPC, ECR, IAM) in one pass.
