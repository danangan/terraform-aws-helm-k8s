terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
  }
}

locals {
  region       = "us-east-1"
  cluster_name = "platform-cluster"
}

provider "aws" {
  region = local.region
}

provider "helm" {
  kubernetes = {
    host                   = module.platform.cluster_endpoint
    cluster_ca_certificate = base64decode(module.platform.cluster_certificate_authority_data)

    exec = {
      api_version = "client.authentication.k8s.io/v1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", local.cluster_name, "--region", local.region]
    }
  }
}

module "platform" {
  source = "../.."

  aws_region   = local.region
  cluster_name = local.cluster_name

  vpc_cidr                = "10.0.0.0/16"
  availability_zone_count = 2

  kubernetes_version = "1.33"

  cpu_instance_type           = "t4g.small"
  cpu_node_group_min_size     = 0
  cpu_node_group_max_size     = 2
  cpu_node_group_desired_size = 2

  gpu_instance_type           = "g4dn.xlarge"
  gpu_node_group_min_size     = 0
  gpu_node_group_max_size     = 1
  gpu_node_group_desired_size = 0

  deployment_user_name = "platform-cluster-deployer"
}