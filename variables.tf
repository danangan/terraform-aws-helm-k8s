variable "aws_region" {
  description = "AWS region the cluster lives in - not used to configure the aws provider (the caller owns that), only passed to the ALB controller's helm values and the aws eks get-token exec args."
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zone_count" {
  description = "Number of availability zones to spread subnets across"
  type        = number
  default     = 2
}

variable "enable_multi_az_nat_gateway" {
  description = "To enable/disable multi AZ nat gateway setup"
  type        = bool
  default     = false
}

variable "kubernetes_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.33"
}

variable "enable_auto_mode" {
  description = "Run the cluster on EKS Auto Mode: EKS launches and manages the nodes (built-in general-purpose and system node pools) and runs the core add-ons, ALB/NLB controller and EBS CSI driver itself. When true, the cpu_* and gpu_* node group settings are ignored and the AWS Load Balancer Controller isn't installed, so nothing goes through the helm provider"
  type        = bool
  default     = false
}

variable "extra_addons" {
  description = "Extra EKS add-ons to install on the managed node groups, keyed by add-on name, on top of the defaults (coredns, kube-proxy, vpc-cni, eks-pod-identity-agent). Entries take the same settings as terraform-aws-modules/eks's `addons`; a key matching a default add-on replaces its settings. Ignored when enable_auto_mode = true"
  # Mirrors terraform-aws-modules/eks's `addons` type (minus `name`) - unset
  # fields fall back to that module's defaults
  type = map(object({
    before_compute       = optional(bool)
    most_recent          = optional(bool)
    addon_version        = optional(string)
    configuration_values = optional(string)
    namespace_config = optional(object({
      namespace = string
    }))
    pod_identity_association = optional(list(object({
      role_arn        = string
      service_account = string
    })))
    preserve                    = optional(bool)
    resolve_conflicts_on_create = optional(string)
    resolve_conflicts_on_update = optional(string)
    service_account_role_arn    = optional(string)
    timeouts = optional(object({
      create = optional(string)
      update = optional(string)
      delete = optional(string)
    }))
    tags = optional(map(string))
  }))
  default  = {}
  nullable = false
}

variable "cpu_instance_type" {
  description = "Instance type for the CPU-only node group"
  type        = string
  default     = "t4g.small"
}

variable "cpu_node_group_min_size" {
  description = "Minimum CPU nodes; kept at 1+ since these nodes host cluster add-ons (coredns, kube-proxy, the EBS CSI driver)"
  type        = number
  default     = 0
}

variable "cpu_node_group_max_size" {
  type    = number
  default = 2
}

variable "cpu_node_group_desired_size" {
  type    = number
  default = 2
}

variable "gpu_instance_type" {
  description = "Instance type for the GPU-enabled node group"
  type        = string
  default     = "g4dn.xlarge"
}

variable "gpu_node_group_min_size" {
  description = "Minimum GPU nodes; 0 lets the group scale to zero when idle, since the CPU node group covers cluster add-ons"
  type        = number
  default     = 0
}

variable "gpu_node_group_max_size" {
  type    = number
  default = 1
}

variable "gpu_node_group_desired_size" {
  type    = number
  default = 1
}

variable "gpu_node_taints" {
  type = map(any)
  default = {
    gpu_workload = {
      key    = "gpu-workload"
      value  = "true"
      effect = "NO_SCHEDULE"
    }
  }
}

variable "deployment_user_name" {
  description = "Name of the IAM user used to assume the deployment role (CI/CD System)"
  type        = string
  default     = "ai-app-deploy"
}

variable "alb_controller_chart_version" {
  description = "Version of the aws-load-balancer-controller Helm chart to install"
  type        = string
  default     = "3.5.0"
}
