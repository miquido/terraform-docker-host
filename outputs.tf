output "cloud_init_config" {
  description = "Rendered cloud-init configuration to pass as instance user_data"
  value       = local.cloud_init_config
  sensitive   = true

  precondition {
    condition     = var.registry_htpasswd == "" || (var.enable_registry && var.registry_username != "" && var.registry_password != "")
    error_message = "registry_htpasswd requires enable_registry = true and non-empty registry_username and registry_password: the host logs in to its own registry with them (with an empty one the login loop would never succeed)."
  }

  precondition {
    condition     = var.registry_htpasswd == "" || var.registry_url == ""
    error_message = "registry_htpasswd (built-in registry) cannot be combined with registry_url (an external registry such as ECR): the host would be logged in to only one of them. Pick one."
  }
}
