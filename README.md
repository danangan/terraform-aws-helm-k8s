# Kubernetes Cluster Terraform Module for AWS EKS with AWS ALB Ingress Controller Setup

[![Terraform](https://img.shields.io/badge/Terraform-7B42BC?style=flat&logo=terraform&logoColor=white)](https://www.terraform.io/)
[![AWS](https://img.shields.io/badge/AWS-232F3E?style=flat&logo=amazonaws&logoColor=white)](https://aws.amazon.com/)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?style=flat&logo=kubernetes&logoColor=white)](https://kubernetes.io/)
[![Helm](https://img.shields.io/badge/Helm-0F1689?style=flat&logo=helm&logoColor=white)](https://helm.sh/)



A reusable Terraform module that provisions:

- A VPC (public + private subnets across multiple AZs, single NAT gateway)
- An EKS cluster with a CPU node group and a GPU node group
- An ECR repository, and a permissions-boundary-scoped IAM deployment role/user for CI/CD
- The AWS Load Balancer Controller, so `Ingress` resources with `ingressClassName: alb` provision an ALB out of the box

This terraform module is available in public terraform registry as `danangan/k8s/aws`.

Example usage:

```hcl
provider "aws" {}

# This is an important setup to allow Terraform to install the Ingress Controller to the k8s cluster
provider "helm" {
  kubernetes = {
    host                   = module.platform.cluster_endpoint
    cluster_ca_certificate = base64decode(module.platform.cluster_certificate_authority_data)

    exec = {
      api_version = "client.authentication.k8s.io/v1"
      # In this example, we are using aws eks command to authenticate to the k8s API
      # For local operation, you need to authenticate to aws via run "aws login"
      # In remote machine (e.g. in your CI/CD workflow), you can use static access token and authenticate via "aws configure"
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

## Deploying Pods into the GPU nodes

GPU nodes are expensive, so we should only use it sparingly and only deploy relevant workload into that node. To do so, we are using Kubernetes' [node affinity](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/) feature. To deploy pods into the GPU nodes, you'd need to provision your workload with the following tolerations:
```
tolerations:
- key: "gpu-workload"
  operator: "Equal"
  value: "true"
  effect: "NoSchedule"
```

You can override this configuration in the TF module with the

## Project structure

```
(repo root)/        # The module itself
modules/            # The sub-modules it's composed of, usable on their own
                    # if you split the bootstrap catch across two root
                    # modules (see "The bootstrap catch" above)
  ...
examples/
  demo-k8s-cluster/ # A deployable example: calls this module with
                    # `source = "../.."` and its own provider config.
                    # Use this to actually stand up a cluster.
  demo-app/         # A minimal FastAPI "hello world" service + Helm chart,
                    # deployed onto the example cluster's Ingress.
```

## Trying it out (via the example)

### Prerequisites

- AWS CLI, configured with credentials that can manage the resources below
- Terraform
- kubectl
- Helm

### 1. Provision the cluster and the Ingress controller

Log in with the AWS CLI first, so Terraform has credentials to work with - e.g. `aws login` if you use IAM Identity Center, or `aws configure` for a static access key/secret:

```
aws login
```

Then, from `examples/demo-k8s-cluster`:

```
cd examples/demo-k8s-cluster
terraform init
terraform apply
```

As mentioned in the section above (see bootrstrapping catch), you'd encounter an error on your first apply. You can just re-run the apply (`terraform apply`) and it should succeess for now. Any subsequent update after the second apply should work as expected.

### 2. Build and deploy the demo app

The demo app (`examples/demo-app/`) is managed with `uv`. Build its image, push it to the ECR repo Terraform just created, and roll it out with Helm:

```
cd examples/demo-app
./deploy.sh
```

This tags the image with a timestamp (the ECR repo is immutable-tagged, so re-running always pushes a new tag) and does a `helm upgrade --install app .` pointed at it. Safe to re-run for every new deploy.

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
