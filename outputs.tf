output "cloud_init_config" {
  description = "Rendered cloud-init configuration to pass as instance user_data"
  value       = local.cloud_init_config
  sensitive   = true
}
