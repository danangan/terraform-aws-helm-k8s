# network

A VPC (via `terraform-aws-modules/vpc/aws`) with public + private subnets spread across multiple AZs, and a single NAT gateway by default (multi-AZ NAT optional). Public/private subnets are tagged for the AWS Load Balancer Controller's subnet auto-discovery.

## Inputs

| Name | Description | Default |
|---|---|---|
| `cluster_name` | Used to name the VPC and tag subnets for ALB/NLB auto-discovery | - |
| `vpc_cidr` | CIDR block for the VPC | `10.0.0.0/16` |
| `availability_zone_count` | Number of AZs to spread subnets across | `2` |
| `enable_multi_az_nat_gateway` | Deploy a NAT gateway per AZ instead of a single shared one - higher availability, higher cost | `false` |

## Outputs

| Name | Description |
|---|---|
| `vpc_id` | ID of the VPC |
| `private_subnets` | IDs of the private subnets - where the EKS node groups run |
| `public_subnets` | IDs of the public subnets - where ALBs/NLBs get placed |
