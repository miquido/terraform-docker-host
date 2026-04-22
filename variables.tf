variable "domain" {
  description = "Base domain for wildcard certificate and routing (e.g. dmc.miquido.dev)"
  type        = string
}

variable "acme_email" {
  description = "Email for Let's Encrypt ACME registration"
  type        = string
}

variable "dns_challenge_provider" {
  description = "Traefik ACME DNS challenge provider (e.g. route53, cloudflare)"
  type        = string
  default     = "route53"
}

variable "dns_challenge_env" {
  description = "Environment variables required by the DNS challenge provider"
  type        = map(string)
  sensitive   = true
}

variable "oidc_jwks_url" {
  description = "JWKS URL for docker-compose-runner OIDC authentication"
  type        = string
}

variable "oidc_audience" {
  description = "Expected OIDC audience for docker-compose-runner"
  type        = string
}

variable "oidc_expected_subs" {
  description = "Comma-separated list of expected OIDC subjects for docker-compose-runner"
  type        = string
}

variable "ip_allowlist" {
  description = "CIDR range allowed to access the docker-compose-runner endpoint"
  type        = string
}

variable "docker_compose_runner_image" {
  description = "Docker image for the docker-compose-runner service"
  type        = string
  default     = "miquido/gitlab-docker-compose-host:172950-746ccb39"
}

variable "passwd_hash" {
  description = "Bcrypt hash of the password for the dynamic user"
  type        = string
  sensitive   = true
}

variable "registry_url" {
  description = "Docker registry hostname to authenticate against (empty to skip)"
  type        = string
  default     = ""
}

variable "registry_username" {
  description = "Username for docker login"
  type        = string
  default     = ""
}

variable "registry_password" {
  description = "Password for docker login"
  type        = string
  sensitive   = true
  default     = ""
}

variable "use_ecr_credential_helper" {
  description = "Install and configure amazon-ecr-credential-helper instead of static docker login"
  type        = bool
  default     = false
}

variable "block_device" {
  description = "Block device path for the persistent data volume"
  type        = string
  default     = "/dev/sdb"
}

variable "walg_s3_endpoint" {
  description = "WAL-G S3 endpoint URL. Empty = skip walg.env generation."
  type        = string
  default     = ""
}

variable "walg_s3_access_key_id" {
  type      = string
  default   = ""
  sensitive = true
}

variable "walg_s3_secret_access_key" {
  type      = string
  default   = ""
  sensitive = true
}

variable "walg_s3_region" {
  type    = string
  default = ""
}