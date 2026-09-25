locals {
  # AWS Graviton (ARM) instance families follow a "<letters><digits>g<letters>.<size>"
  # naming convention (t4g, m6g, m6gd, c7g, r7gn, ...) - match on that "g" marker
  # to pick the matching EKS-optimized AMI, so a future instance-type change
  # doesn't silently mismatch the AMI arch again.
  cpu_node_ami_type = can(regex("^[a-z][0-9]+g[a-z]*\\.", var.cpu_instance_type)) ? "AL2023_ARM_64_STANDARD" : "AL2023_x86_64_STANDARD"
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version

  authentication_mode = "API_AND_CONFIG_MAP"

  endpoint_public_access                   = true
  enable_cluster_creator_admin_permissions = true
  enable_irsa                              = true

  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  # Auto Mode has its own CoreDNS, kube-proxy, VPC CNI, Pod Identity agent and
  # EBS support, so add-ons are only installed on the managed node groups.
  # extra_addons entries are merged over these defaults.
  addons = var.enable_auto_mode ? null : merge({
    coredns                = {}
    kube-proxy             = {}
    vpc-cni                = { before_compute = true }
    eks-pod-identity-agent = { before_compute = true }

    # Needed for any EBS-backed PersistentVolume. Also creates
    # `ebs-csi-default-sc`, a default StorageClass whose volumes are gp3
    # (the driver's default volume type).
    aws-ebs-csi-driver = {
      configuration_values = jsonencode({ defaultStorageClass = { enabled = true } })
      pod_identity_association = [{
        role_arn        = one(aws_iam_role.ebs_csi_driver[*].arn)
        service_account = "ebs-csi-controller-sa"
      }]
    }
  }, var.extra_addons)

  # This one flag turns on all of Auto Mode: compute (the built-in node pools),
  # block storage (EBS) and load balancing (ALB/NLB). At least one built-in
  # node pool is needed for EKS to create the `default` NodeClass that custom
  # node pools reference.
  compute_config = {
    enabled    = var.enable_auto_mode
    node_pools = var.enable_auto_mode ? ["general-purpose", "system"] : null
  }

  # This is deliberate so that the cluster use AWS-managed encryption key
  # rather than customer managed key
  # This is to save some cost associated with the key creation
  # create_kms_key = false

  # Auto Mode launches its own nodes, so no managed node groups there
  eks_managed_node_groups = var.enable_auto_mode ? null : {
    cpu = {
      ami_type       = local.cpu_node_ami_type
      instance_types = [var.cpu_instance_type]

      min_size     = var.cpu_node_group_min_size
      max_size     = var.cpu_node_group_max_size
      desired_size = var.cpu_node_group_desired_size
    },
    gpu = {
      ami_type       = "AL2023_x86_64_NVIDIA"
      instance_types = [var.gpu_instance_type]

      min_size     = var.gpu_node_group_min_size
      max_size     = var.gpu_node_group_max_size
      desired_size = var.gpu_node_group_desired_size

      taints = var.gpu_node_taints
    }
  }
}

# Permissions for the EBS CSI driver add-on to create/attach/delete EBS volumes,
# granted through EKS Pod Identity. Not needed on Auto Mode, which has its own
# built-in EBS support.
data "aws_iam_policy_document" "ebs_csi_driver_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ebs_csi_driver" {
  count = var.enable_auto_mode ? 0 : 1

  name               = "${var.cluster_name}-ebs-csi-driver"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_driver_assume_role.json
}

resource "aws_iam_role_policy_attachment" "ebs_csi_driver" {
  count = var.enable_auto_mode ? 0 : 1

  role       = aws_iam_role.ebs_csi_driver[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}
