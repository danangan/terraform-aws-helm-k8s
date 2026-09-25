# The Amazon EBS CSI driver, installed as an EKS add-on, following
# https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html

# --- Step 1: IAM role --------------------------------------------------------
# Granted to the driver's controller through EKS Pod Identity, which AWS
# recommends over IRSA.

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
  name               = "${var.cluster_name}-ebs-csi-driver"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_driver_assume_role.json
}

# Unlike the older AmazonEBSCSIDriverPolicy, V2 isn't under the service-role/
# path (the AWS guide's commands get this wrong). It only lets the driver manage
# volumes and snapshots tagged ebs.csi.aws.com/cluster=true, which the driver
# adds to everything it creates.
resource "aws_iam_role_policy_attachment" "ebs_csi_driver" {
  role       = aws_iam_role.ebs_csi_driver.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEBSCSIDriverPolicyV2"
}

# Only needed for volumes encrypted with customer managed KMS keys - the AWS
# managed aws/ebs key works without it.
data "aws_iam_policy_document" "kms" {
  count = length(var.kms_key_arns) > 0 ? 1 : 0

  statement {
    effect    = "Allow"
    actions   = ["kms:CreateGrant", "kms:ListGrants", "kms:RevokeGrant"]
    resources = var.kms_key_arns

    condition {
      test     = "Bool"
      variable = "kms:GrantIsForAWSResource"
      values   = ["true"]
    }
  }

  statement {
    effect    = "Allow"
    actions   = ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:DescribeKey"]
    resources = var.kms_key_arns
  }
}

resource "aws_iam_role_policy" "kms" {
  count = length(var.kms_key_arns) > 0 ? 1 : 0

  name   = "kms-key-for-encryption-on-ebs"
  role   = aws_iam_role.ebs_csi_driver.name
  policy = data.aws_iam_policy_document.kms[0].json
}

# --- Step 2: the EKS add-on --------------------------------------------------

data "aws_eks_addon_version" "ebs_csi_driver" {
  addon_name         = "aws-ebs-csi-driver"
  kubernetes_version = var.kubernetes_version
  most_recent        = true
}

resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name  = var.cluster_name
  addon_name    = "aws-ebs-csi-driver"
  addon_version = coalesce(var.addon_version, data.aws_eks_addon_version.ebs_csi_driver.version)

  # defaultStorageClass creates `ebs-csi-default-sc`, a default StorageClass
  # whose volumes are gp3 (the driver's default volume type)
  configuration_values = jsonencode({
    defaultStorageClass = { enabled = var.create_default_storage_class }
  })

  # The add-on creates the controller's service account and links it to the role
  pod_identity_association {
    role_arn        = aws_iam_role.ebs_csi_driver.arn
    service_account = "ebs-csi-controller-sa"
  }

  # Take over driver resources already on the cluster, e.g. left behind by an
  # earlier install of the add-on
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  # The controller needs its permissions from the moment it starts
  depends_on = [aws_iam_role_policy_attachment.ebs_csi_driver, aws_iam_role_policy.kms]
}
