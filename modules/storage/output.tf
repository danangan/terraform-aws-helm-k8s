output "iam_role_arn" {
  description = "ARN of the IAM role the EBS CSI driver's controller runs as"
  value       = aws_iam_role.ebs_csi_driver.arn
}

output "default_storage_class_name" {
  description = "Name of the default StorageClass the add-on creates, or null when create_default_storage_class is false"
  value       = var.create_default_storage_class ? "ebs-csi-default-sc" : null
}
