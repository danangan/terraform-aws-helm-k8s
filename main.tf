module "network" {
  source = "./modules/network"

  cluster_name                = var.cluster_name
  vpc_cidr                    = var.vpc_cidr
  availability_zone_count     = var.availability_zone_count
  enable_multi_az_nat_gateway = var.enable_multi_az_nat_gateway
}

module "eks" {
  source = "./modules/eks"

  cluster_name       = var.cluster_name
  kubernetes_version = var.kubernetes_version
  enable_auto_mode   = var.enable_auto_mode
  extra_addons       = var.extra_addons

  vpc_id     = module.network.vpc_id
  subnet_ids = module.network.private_subnets

  cpu_instance_type           = var.cpu_instance_type
  cpu_node_group_min_size     = var.cpu_node_group_min_size
  cpu_node_group_max_size     = var.cpu_node_group_max_size
  cpu_node_group_desired_size = var.cpu_node_group_desired_size

  gpu_instance_type           = var.gpu_instance_type
  gpu_node_group_min_size     = var.gpu_node_group_min_size
  gpu_node_group_max_size     = var.gpu_node_group_max_size
  gpu_node_group_desired_size = var.gpu_node_group_desired_size
  gpu_node_taints             = var.gpu_node_taints
}

module "storage" {
  source = "./modules/storage"

  # Auto Mode has its own built-in EBS support
  count = var.enable_auto_mode ? 0 : 1

  cluster_name       = module.eks.cluster_name
  kubernetes_version = var.kubernetes_version

  # The add-on only becomes active once its controller pods are running, so
  # wait for the node groups (and the Pod Identity agent) to be up
  depends_on = [module.eks]
}

# v1.1.0 created the EBS CSI driver's role inside the eks sub-module - keep it
# rather than deleting and recreating it
moved {
  from = module.eks.aws_iam_role.ebs_csi_driver[0]
  to   = module.storage[0].aws_iam_role.ebs_csi_driver
}

module "ecr" {
  source = "./modules/ecr"

  repository_name = "${var.cluster_name}-repo"
}

module "deployment" {
  source = "./modules/deployment"

  cluster_name         = var.cluster_name
  cluster_arn          = module.eks.cluster_arn
  deployment_user_name = var.deployment_user_name
  ecr_repository_arn   = module.ecr.repository_arn
}

module "alb_controller" {
  source = "./modules/alb-controller"

  # Auto Mode has its own built-in ALB/NLB controller
  count = var.enable_auto_mode ? 0 : 1

  aws_region   = var.aws_region
  cluster_name = var.cluster_name
  vpc_id       = module.network.vpc_id
}

# alb_controller gained a count - keep the controller already deployed on
# existing clusters instead of destroying and recreating it
moved {
  from = module.alb_controller
  to   = module.alb_controller[0]
}