variable "cluster_name" {
  description = "Name of the EKS cluster to install the EBS CSI driver into"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version of the cluster - used to look up the most recent add-on version for it"
  type        = string
}

variable "addon_version" {
  description = "Version of the aws-ebs-csi-driver add-on to install. Defaults to the most recent one for kubernetes_version"
  type        = string
  default     = null
}

variable "create_default_storage_class" {
  description = "Have the add-on create `ebs-csi-default-sc`, a default StorageClass for gp3 volumes"
  type        = bool
  default     = true
}

variable "kms_key_arns" {
  description = "ARNs of customer managed KMS keys that encrypt EBS volumes - the driver's role is allowed to use them. Not needed for unencrypted volumes or the AWS managed aws/ebs key"
  type        = list(string)
  default     = []
}
