# storage

Installs the [Amazon EBS CSI driver](https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html) as an EKS add-on, so PersistentVolumeClaims get EBS volumes. Follows the AWS guide:

1. An IAM role for the driver's controller with the AWS managed `AmazonEBSCSIDriverPolicyV2`, granted through EKS Pod Identity (needs the `eks-pod-identity-agent` add-on, which the `eks` sub-module installs). With `kms_key_arns` set, the role can also use those customer managed KMS keys for encrypted volumes.
2. The `aws-ebs-csi-driver` EKS add-on, linked to that role. By default it also creates `ebs-csi-default-sc`, the cluster's default StorageClass, for gp3 volumes.

The add-on only becomes active once its controller pods are running, so apply this after the cluster's nodes exist - the root module does that with `depends_on = [module.eks]`.

Not needed on EKS Auto Mode, which has its own built-in EBS support - the root module skips it when `enable_auto_mode = true`.

## Inputs

| Name | Description | Default |
|---|---|---|
| `cluster_name` | Name of the EKS cluster to install the driver into | - |
| `kubernetes_version` | Kubernetes version of the cluster - used to look up the most recent add-on version | - |
| `addon_version` | Version of the `aws-ebs-csi-driver` add-on. Defaults to the most recent one for `kubernetes_version` | `null` |
| `create_default_storage_class` | Have the add-on create `ebs-csi-default-sc`, a default StorageClass for gp3 volumes | `true` |
| `kms_key_arns` | ARNs of customer managed KMS keys that encrypt EBS volumes - the driver's role is allowed to use them | `[]` |

## Outputs

| Name | Description |
|---|---|
| `iam_role_arn` | ARN of the IAM role the driver's controller runs as |
| `default_storage_class_name` | Name of the default StorageClass the add-on creates, or `null` when `create_default_storage_class` is `false` |
