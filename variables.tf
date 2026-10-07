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
  description = "Environment variables required by the DNS challenge provider. Empty map = credentials come from elsewhere (instance role, traefik_extra_environment, ...)."
  type        = map(string)
  sensitive   = true
  default     = {}
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
  description = "List of expected OIDC subjects for docker-compose-runner"
  type        = list(string)
}

variable "ip_allowlist" {
  description = "CIDR range allowed to access the docker-compose-runner endpoint"
  type        = string
}

variable "docker_compose_runner_image" {
  description = "Docker image for the docker-compose-runner service"
  type        = string
  default     = "ghcr.io/miquido/gitlab-docker-compose-host:v1.4.0"
}

variable "vm_user" {
  description = "Login user created on the VM. Its home holds docker-compose.yml and the helper scripts."
  type        = string
  default     = "ubuntu"
}

variable "hostname" {
  description = "VM hostname set through cloud-init. Empty = leave to the platform."
  type        = string
  default     = ""
}

variable "passwd_hash" {
  description = "Bcrypt hash of the password for vm_user. Empty = password login disabled (SSH keys only)."
  type        = string
  sensitive   = true
  default     = ""
}

variable "registry_url" {
  description = "External docker registry hostname to authenticate against (empty to skip). Not needed for the built-in registry: see registry_htpasswd."
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
  description = "Block device path for the persistent data volume. Empty = no separate disk, /mnt/data lives on the root disk."
  type        = string
  default     = "/dev/sdb"
}

variable "enable_traefik_metrics" {
  description = "Expose Traefik Prometheus metrics on the internal `metrics` entrypoint (:8080) for a collector to scrape. Enabled automatically when Alloy is."
  type        = bool
  default     = false
}

variable "ofelia_image" {
  description = "Ofelia image running the scheduled jobs (backups, registry GC, image prune). Must be the netresearch fork: it follows Docker events and namespaces jobs per container (see docker-compose template)."
  type        = string
  default     = "ghcr.io/netresearch/ofelia:1.0.1"
}

variable "docker_prune_schedule" {
  description = "Cron schedule for Docker image pruning via Ofelia. Set to empty string to disable."
  type        = string
  default     = "0 3 * * *"
}

variable "alloy_remote_write_url" {
  description = "Full Prometheus remote_write URL for Grafana Alloy (e.g. https://metrics.../api/v1/push). Empty string disables Alloy."
  type        = string
  default     = ""
}

variable "alloy_remote_write_username" {
  description = "Basic auth username for Alloy remote_write. Scaleway Cockpit uses 'scaleway'."
  type        = string
  default     = "scaleway"
}

variable "alloy_remote_write_token" {
  description = "Basic auth password / token for Alloy remote_write."
  type        = string
  default     = ""
  sensitive   = true
}

variable "alloy_loki_write_url" {
  description = "Loki-compatible push URL for shipping Docker container logs via Grafana Alloy (e.g. https://.../loki/api/v1/push). Empty string disables log shipping."
  type        = string
  default     = ""
}

variable "alloy_loki_write_username" {
  description = "Basic auth username for Alloy Loki write. Scaleway Cockpit uses 'scaleway'."
  type        = string
  default     = "scaleway"
}

variable "alloy_loki_write_token" {
  description = "Basic auth password / token for Alloy Loki write."
  type        = string
  default     = ""
  sensitive   = true
}

variable "ssh_public_keys" {
  description = "List of SSH public keys added to vm_user's authorized_keys."
  type        = list(string)
  default     = []
}

variable "walg_env_vars" {
  description = "WAL-G environment variables written to /etc/docker-host/walg.env (symlinked from /home/<vm_user>/walg.env). Empty map = skip file generation. Cloud-agnostic: pass whatever KEY=VALUE pairs your storage backend requires (AWS S3 IAM, S3-compatible endpoint, GCS, Azure Blob, etc.)."
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "enable_registry" {
  description = "Run a registry:2 container at registry.<domain> (data in /mnt/data/registry, daily GC through Ofelia). It ships without authentication: protect it with static_extra_labels / extra_compose_services or the network. Independent of registry_url, which is an external registry the host logs in to."
  type        = bool
  default     = false
}

variable "registry_htpasswd" {
  description = "htpasswd entries (bcrypt; comma-separated for several users) protecting the built-in registry with basic auth. Used with enable_registry. When set, the host also logs in to registry.<domain> with registry_username / registry_password once the stack is up, so the docker-compose-runner can pull from it."
  type        = string
  sensitive   = true
  default     = ""
}

variable "traefik_access_log" {
  description = "Enable Traefik access log in JSON format on stdout."
  type        = bool
  default     = false
}

variable "nginx_static_server_extra" {
  description = "Extra nginx directives inserted into the server block of the static-sites vhost."
  type        = string
  default     = ""
}

# Extension points: let a platform wrapper add what the core must not know about
# (credential helpers, tunnels, mounts, log shippers) without forking the templates.

variable "traefik_entrypoint" {
  description = "Override the Traefik container entrypoint (compose `entrypoint:` list). Empty = image default."
  type        = list(string)
  default     = []
}

variable "traefik_extra_volumes" {
  description = "Extra Traefik volume mounts (compose short syntax, e.g. /home/ubuntu/creds:/creds:ro)."
  type        = list(string)
  default     = []
}

variable "traefik_extra_environment" {
  description = "Extra environment variables for the Traefik container."
  type        = map(string)
  sensitive   = true
  default     = {}
}

variable "traefik_extra_args" {
  description = "Extra Traefik command-line arguments."
  type        = list(string)
  default     = []
}

variable "static_extra_labels" {
  description = "Extra Docker labels for the nginx-static service (e.g. additional Traefik routers)."
  type        = list(string)
  default     = []
}

variable "extra_compose_services" {
  description = "YAML fragment with additional compose services, written at column 0 (it is indented under `services:` for you)."
  type        = string
  default     = ""
}

variable "extra_packages" {
  description = "Extra apt packages installed before Docker."
  type        = list(string)
  default     = []
}

variable "extra_write_files" {
  description = "Extra cloud-init write_files entries."
  type = list(object({
    path        = string
    content     = string
    permissions = optional(string, "0644")
    owner       = optional(string, "root:root")
    append      = optional(bool, false)
  }))
  default   = []
  sensitive = true
}

variable "extra_runcmd" {
  description = "Extra shell commands run (as root) after Docker is installed and the data dir exists, right before `docker compose up`."
  type        = list(string)
  default     = []
}
