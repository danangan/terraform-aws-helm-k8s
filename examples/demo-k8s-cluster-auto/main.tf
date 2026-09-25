terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

locals {
  region       = "us-east-1"
  cluster_name = "platform-cluster-auto"
}

provider "aws" {
  region = local.region
}

# No helm provider needed: on Auto Mode the module doesn't install anything
# through Helm (the ALB controller is built in), so there's no bootstrap catch
# either - one apply is enough.

module "platform" {
  # The module at the repo root, so local changes are picked up. Outside this
  # repo, use the registry instead: source = "danangan/k8s/aws"
  source = "../.."

  aws_region   = local.region
  cluster_name = local.cluster_name

  vpc_cidr                = "10.0.0.0/16"
  availability_zone_count = 2

  kubernetes_version = "1.33"

  # EKS launches and manages the nodes, so there are no cpu_*/gpu_* node group
  # settings here. Apply the manifests in ./auto-mode once the cluster is up.
  enable_auto_mode = true

  deployment_user_name = "platform-cluster-auto-deployer"
}

output "ecr_repository_url" {
  value = module.platform.ecr_repository_url
}

output "cluster_name" {
  value = module.platform.cluster_name
}
