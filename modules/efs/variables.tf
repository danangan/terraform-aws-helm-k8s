variable "cluster_name" {
  description = "Name of the EKS cluster to install the EFS CSI driver into - also used to name the file system and its security group"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version of the cluster - used to look up the most recent add-on version for it"
  type        = string
}

variable "addon_version" {
  description = "Version of the aws-efs-csi-driver add-on to install. Defaults to the most recent one for kubernetes_version"
  type        = string
  default     = null
}

variable "vpc_id" {
  description = "ID of the cluster's VPC - the file system's security group lets NFS in from its CIDR block"
  type        = string
}

variable "subnet_ids" {
  description = "IDs of the subnets the cluster's nodes run in, at most one per availability zone - each gets a mount target for the file system"
  type        = list(string)
}
