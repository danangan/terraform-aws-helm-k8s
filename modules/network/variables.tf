variable "cluster_name" {
  description = "Used to name the VPC and tag subnets for ALB/NLB auto-discovery"
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
  type = bool
  default = false
}