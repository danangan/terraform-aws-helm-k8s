# The Amazon EFS CSI driver, installed as an EKS add-on, following
# https://docs.aws.amazon.com/eks/latest/userguide/efs-csi.html

# --- Step 1: IAM role --------------------------------------------------------
# Granted to the driver's controller through EKS Pod Identity, which AWS
# recommends over IRSA.

data "aws_iam_policy_document" "efs_csi_driver_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "efs_csi_driver" {
  name               = "${var.cluster_name}-efs-csi-driver"
  assume_role_policy = data.aws_iam_policy_document.efs_csi_driver_assume_role.json
}

# Unlike the EBS driver's policy, this one is under the service-role/ path. It
# lets the controller create the access points dynamic provisioning uses, and
# only delete ones tagged efs.csi.aws.com/cluster, which it adds to everything
# it creates.
resource "aws_iam_role_policy_attachment" "efs_csi_driver" {
  role       = aws_iam_role.efs_csi_driver.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy"
}

# --- Step 2: the EKS add-on --------------------------------------------------

data "aws_eks_addon_version" "efs_csi_driver" {
  addon_name         = "aws-efs-csi-driver"
  kubernetes_version = var.kubernetes_version
  most_recent        = true
}

resource "aws_eks_addon" "efs_csi_driver" {
  cluster_name  = var.cluster_name
  addon_name    = "aws-efs-csi-driver"
  addon_version = coalesce(var.addon_version, data.aws_eks_addon_version.efs_csi_driver.version)

  # The add-on creates the controller's service account and links it to the
  # role. The node DaemonSet (efs-csi-node-sa) doesn't need AWS permissions to
  # mount, and tolerates all taints by default, so it also runs on the GPU nodes
  pod_identity_association {
    role_arn        = aws_iam_role.efs_csi_driver.arn
    service_account = "efs-csi-controller-sa"
  }

  # Take over driver resources already on the cluster, e.g. left behind by an
  # earlier install of the add-on
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  # The controller needs its permissions from the moment it starts
  depends_on = [aws_iam_role_policy_attachment.efs_csi_driver]
}

# --- Step 3: an EFS file system ----------------------------------------------
# Following https://github.com/kubernetes-sigs/aws-efs-csi-driver/blob/master/docs/efs-create-filesystem.md:
# a mount target in each of the nodes' subnets, behind a security group that
# lets NFS in from the VPC.

data "aws_vpc" "this" {
  id = var.vpc_id
}

resource "aws_security_group" "efs" {
  name        = "${var.cluster_name}-efs"
  description = "NFS access to the ${var.cluster_name} EFS file system from inside the VPC"
  vpc_id      = var.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "nfs" {
  security_group_id = aws_security_group.efs.id
  description       = "NFS from the VPC"
  ip_protocol       = "tcp"
  from_port         = 2049
  to_port           = 2049
  cidr_ipv4         = data.aws_vpc.this.cidr_block
}

# Encrypted at rest with the AWS managed aws/elasticfilesystem key, which costs
# nothing extra - the guide's CLI command leaves it unencrypted
resource "aws_efs_file_system" "this" {
  creation_token   = "${var.cluster_name}-efs"
  performance_mode = "generalPurpose"
  encrypted        = true

  tags = {
    Name = "${var.cluster_name}-efs"
  }
}

# count rather than for_each: subnet IDs aren't known until the VPC exists, but
# how many there are is
resource "aws_efs_mount_target" "this" {
  count = length(var.subnet_ids)

  file_system_id  = aws_efs_file_system.this.id
  subnet_id       = var.subnet_ids[count.index]
  security_groups = [aws_security_group.efs.id]
}
