output "iam_role_arn" {
  description = "ARN of the IAM role the EFS CSI driver's controller runs as"
  value       = aws_iam_role.efs_csi_driver.arn
}

output "file_system_id" {
  description = "ID of the EFS file system - the fileSystemId of a StorageClass or PersistentVolume that uses it"
  value       = aws_efs_file_system.this.id
}

output "security_group_id" {
  description = "ID of the security group on the file system's mount targets"
  value       = aws_security_group.efs.id
}
