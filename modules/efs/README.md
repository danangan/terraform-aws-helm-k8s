# efs

Installs the [Amazon EFS CSI driver](https://docs.aws.amazon.com/eks/latest/userguide/efs-csi.html) as an EKS add-on, and creates an EFS file system for it, so PersistentVolumeClaims can get shared `ReadWriteMany` storage. Follows the AWS guide:

1. An IAM role for the driver's controller with the AWS managed `AmazonEFSCSIDriverPolicy`, granted through EKS Pod Identity (needs the `eks-pod-identity-agent` add-on, which the `eks` sub-module installs, or EKS Auto Mode, which has it built in).
2. The `aws-efs-csi-driver` EKS add-on, linked to that role.
3. An encrypted EFS file system, as in the driver's [file system guide](https://github.com/kubernetes-sigs/aws-efs-csi-driver/blob/master/docs/efs-create-filesystem.md): a mount target in each of `subnet_ids`, behind a security group that lets NFS (TCP 2049) in from the VPC's CIDR block.

The add-on only becomes active once its controller pods are running, so apply this after the cluster's nodes exist - the root module does that with `depends_on = [module.eks]`.

Unlike the EBS add-on, the EFS add-on can't create a StorageClass. Create one with `kubectl`, using the `file_system_id` output - see the root README's "EFS storage" section.

Works on both managed node groups and EKS Auto Mode, which doesn't have EFS support built in.

Destroying this module deletes the file system and everything stored on it.

## Inputs

| Name | Description | Default |
|---|---|---|
| `cluster_name` | Name of the EKS cluster to install the driver into - also names the file system and its security group | - |
| `kubernetes_version` | Kubernetes version of the cluster - used to look up the most recent add-on version | - |
| `addon_version` | Version of the `aws-efs-csi-driver` add-on. Defaults to the most recent one for `kubernetes_version` | `null` |
| `vpc_id` | ID of the cluster's VPC - NFS is allowed in from its CIDR block | - |
| `subnet_ids` | IDs of the subnets the nodes run in, at most one per availability zone - each gets a mount target | - |

## Outputs

| Name | Description |
|---|---|
| `iam_role_arn` | ARN of the IAM role the driver's controller runs as |
| `file_system_id` | ID of the EFS file system - the `fileSystemId` of a StorageClass or PersistentVolume that uses it |
| `security_group_id` | ID of the security group on the file system's mount targets |
