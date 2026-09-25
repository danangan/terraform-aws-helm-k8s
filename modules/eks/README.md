# eks

An EKS cluster (via `terraform-aws-modules/eks/aws`) with a Graviton (ARM) CPU node group and a GPU node group (tainted `gpu-workload=true:NoSchedule`, so only pods that tolerate it land there). AMI architecture for the CPU group is picked automatically from the instance type.

Installs the `coredns`, `kube-proxy`, `vpc-cni` and `eks-pod-identity-agent` add-ons, plus any in `extra_addons`. The EBS CSI driver is in the separate [`storage`](../storage/) sub-module.

With `enable_auto_mode = true`, the cluster runs on EKS Auto Mode instead: no node groups or add-ons are created, and EKS launches nodes from its built-in `general-purpose` and `system` node pools. See the root README's "EKS Auto Mode" section.

## Inputs

| Name | Description | Default |
|---|---|---|
| `cluster_name` | Name of the EKS cluster | - |
| `kubernetes_version` | Kubernetes version | `1.33` |
| `enable_auto_mode` | Run the cluster on EKS Auto Mode. When `true`, the `cpu_*`, `gpu_*` and `extra_addons` inputs are ignored | `false` |
| `extra_addons` | Extra EKS add-ons, keyed by add-on name, merged over the defaults. Entries take the same settings as `addons` in `terraform-aws-modules/eks` | `{}` |
| `vpc_id` | ID of the VPC to create the cluster in | - |
| `subnet_ids` | IDs of the (private) subnets for the cluster and its node groups | - |
| `cpu_instance_type` | Instance type for the CPU-only node group | `t4g.small` |
| `cpu_node_group_min_size` / `max_size` / `desired_size` | CPU node group sizing | `0` / `2` / `2` |
| `gpu_instance_type` | Instance type for the GPU-enabled node group | `g4dn.xlarge` |
| `gpu_node_group_min_size` / `max_size` / `desired_size` | GPU node group sizing | `0` / `1` / `1` |
| `gpu_node_taints` | Taints applied to the GPU node group, keyed by an arbitrary map key | `{ gpu_workload = { key = "gpu-workload", value = "true", effect = "NO_SCHEDULE" } }` |

## Outputs

| Name | Description |
|---|---|
| `cluster_name` | Name of the EKS cluster |
| `cluster_arn` | ARN of the EKS cluster |
| `cluster_endpoint` | Endpoint of the cluster's Kubernetes API - needed to configure the kubernetes/helm providers |
| `cluster_certificate_authority_data` | Base64-encoded CA certificate - needed to configure the kubernetes/helm providers |
