# The Amazon EFS CSI driver, installed as an EKS add-on, following
# https://docs.aws.amazon.com/eks/latest/userguide/efs-csi.html

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

resource "aws_iam_role_policy_attachment" "efs_csi_driver" {
  role       = aws_iam_role.efs_csi_driver.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy"
}

data "aws_eks_addon_version" "efs_csi_driver" {
  addon_name         = "aws-efs-csi-driver"
  kubernetes_version = var.kubernetes_version
  most_recent        = true
}

resource "aws_eks_addon" "efs_csi_driver" {
  cluster_name  = var.cluster_name
  addon_name    = "aws-efs-csi-driver"
  addon_version = coalesce(var.addon_version, data.aws_eks_addon_version.efs_csi_driver.version)

  pod_identity_association {
    role_arn        = aws_iam_role.efs_csi_driver.arn
    service_account = "efs-csi-controller-sa"
  }

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_iam_role_policy_attachment.efs_csi_driver]
}
