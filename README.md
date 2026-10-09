# docker-host <a href="https://miquido.com"><img align="right" src="https://cdn.miquido.dev/miquido-logo.png" width="150" /></a>

Terraform module that generates a cloud-init configuration for a Docker host with Traefik reverse proxy, OIDC-authenticated docker-compose-runner, and optional Grafana Alloy observability (cloud-specific shippers such as CloudWatch live in the platform wrappers, through the extra_* hooks).

## Quick start

The module renders a cloud-init document; a platform wrapper creates the machine and feeds it in. Ready-made wrappers: `terraform-aws-docker-host` (EC2), `terraform-scaleway-docker-host`, and the Proxmox one in `terraform-proxmox-docker-host`. To use the core directly on any cloud:

```hcl
module "docker_host" {
  source = "git::https://github.com/miquido/terraform-docker-host.git?ref=v2.0.0"

  domain             = "dmc.example.com"      # wildcard certificate for *.domain
  acme_email         = "devops@example.com"
  dns_challenge_provider = "route53"          # any Traefik/lego DNS-01 provider
  dns_challenge_env  = { AWS_REGION = "eu-west-1" }   # or leave empty and use an instance role
  oidc_jwks_url      = "https://gitlab.example.com/oauth/discovery/keys"
  oidc_audience      = "https://gitlab.example.com"
  oidc_expected_subs = ["project_path:my-group/**"]
  ip_allowlist       = "203.0.113.0/24"       # who may call the docker-compose-runner
  ssh_public_keys    = ["ssh-ed25519 AAAA..."]
  block_device       = ""                     # "" = data on the root disk; or e.g. /dev/sdb for a separate volume
}

# user_data / cloud-init of whatever machine you create:
#   module.docker_host.cloud_init_config
```

Platform specifics (credential helpers, log shippers, NFS mounts, tunnels, ...) go in through the `extra_*` and `traefik_*` inputs rather than by forking the templates. The rendered document can exceed provider limits (EC2: 16 KB), in which case pass it gzipped (`base64gzip`).

## Scheduled jobs (Ofelia)

Database backup jobs are declared as labels on the app's own containers (`ofelia.enabled=true`, `ofelia.job-exec.<job>.schedule/command`). The scheduler is the maintained `netresearch/ofelia` fork configured by `/etc/docker-host/ofelia.ini`:
- it follows Docker events, so a stack redeployed later is picked up without restarting anything (the original `mcuadros/ofelia` reads labels once at start and silently drops jobs of containers created afterwards);
- `job-exec-label-scope = container` names jobs `<container>.<job>`, so several projects can all define `backup`;
- `default-user = root` (the fork's own default is `nobody`, which cannot read the database data directories);
- `docker-prune` (`docker_prune_schedule`) is defined in the INI because the fork drops label-defined `job-run` jobs that mount `docker.sock`.

## On the host

The same files and commands exist on every platform, whatever the VM user is, so app compose files and runbooks do not depend on the cloud:

| Path | What |
|---|---|
| `/etc/docker-host/walg.env` | WAL-G environment (`walg_env_vars`), `root:<vm_user>` mode 0640. Use it from app compose files with `env_file: [{path: /etc/docker-host/walg.env, required: false}]`. The docker-compose-runner mounts it at the same path. `/home/<vm_user>/walg.env` is a symlink to it. |
| `/usr/local/bin/pitr-marker <container\|compose_project> [name]` | Takes a marker to restore to, for a Postgres or a MySQL WAL-G container, and returns once everything up to it is in the WAL-G storage. Postgres: a named restore point in the WAL. MySQL (no named restore points): the binlog file and position, rotated and pushed, written to the storage as `markers/<name>`. Take one before a risky operation, then restore with `pitr-restore <container\|compose_project> marker:<name>` or `pitr-restore-mysql <container> marker:<name>`. |
| `/usr/local/bin/pitr-restore <container\|compose_project> [target_time\|marker:<name>\|IMMEDIATE] [backup]` | Point-in-time restore of a Postgres (WAL-G) container. With a compose project name it finds the Postgres container by label, stops the project's other running containers, restores, and starts them again. Reads WAL-G settings from the container's own environment, so it works with static keys and with instance roles alike. |
| `/usr/local/bin/pitr-restore-mysql <container> [target_time\|marker:<name>\|LATEST\|IMMEDIATE] [backup]` | Same for mysql-walg containers (container name only). Restores the base backup, then replays binlogs starting from the position recorded in `xtrabackup_binlog_info` (wal-g 3.0.x would otherwise replay the whole binlog file the backup began in and abort on statements already applied). With `marker:<name>` it replays the binlogs up to exactly the marker's position (`mysqlbinlog --stop-position`) and, with the default `LATEST`, restores from the newest base backup that finished before the marker. |

Reaching the host (SSM, SSH, console) is the platform wrapper's job; the scripts only need a root shell.

## Development

```bash
make init   # run once after cloning
make readme # regenerate README.md
make lint   # lint terraform code
```

## Usage

```hcl
module "docker_host" {
  source = "git@gitlab.miquido.com:miquido/terraform/docker-host.git"

  domain                 = "dmc.miquido.dev"
  acme_email             = "devops@miquido.com"
  dns_challenge_provider = "route53"
  dns_challenge_env      = { AWS_REGION = "eu-west-1" }
  oidc_jwks_url          = "https://gitlab.com/-/jwks"
  oidc_audience          = "https://gitlab.com"
  oidc_expected_subs     = "project_path:miquido/my-project:ref_type:branch:ref:main"
  ip_allowlist           = "10.0.0.0/8"
  passwd_hash            = "$2b$12$..."
}
```

<!-- BEGIN_TF_DOCS -->
## Requirements

No requirements.

## Providers

No providers.

## Modules

No modules.

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_acme_email"></a> [acme\_email](#input\_acme\_email) | Email for Let's Encrypt ACME registration | `string` | n/a | yes |
| <a name="input_alloy_loki_write_token"></a> [alloy\_loki\_write\_token](#input\_alloy\_loki\_write\_token) | Basic auth password / token for Alloy Loki write. | `string` | `""` | no |
| <a name="input_alloy_loki_write_url"></a> [alloy\_loki\_write\_url](#input\_alloy\_loki\_write\_url) | Loki-compatible push URL for shipping Docker container logs via Grafana Alloy (e.g. https://.../loki/api/v1/push). Empty string disables log shipping. | `string` | `""` | no |
| <a name="input_alloy_loki_write_username"></a> [alloy\_loki\_write\_username](#input\_alloy\_loki\_write\_username) | Basic auth username for Alloy Loki write. Scaleway Cockpit uses 'scaleway'. | `string` | `"scaleway"` | no |
| <a name="input_alloy_remote_write_token"></a> [alloy\_remote\_write\_token](#input\_alloy\_remote\_write\_token) | Basic auth password / token for Alloy remote\_write. | `string` | `""` | no |
| <a name="input_alloy_remote_write_url"></a> [alloy\_remote\_write\_url](#input\_alloy\_remote\_write\_url) | Full Prometheus remote\_write URL for Grafana Alloy (e.g. https://metrics.../api/v1/push). Empty string disables Alloy. | `string` | `""` | no |
| <a name="input_alloy_remote_write_username"></a> [alloy\_remote\_write\_username](#input\_alloy\_remote\_write\_username) | Basic auth username for Alloy remote\_write. Scaleway Cockpit uses 'scaleway'. | `string` | `"scaleway"` | no |
| <a name="input_block_device"></a> [block\_device](#input\_block\_device) | Block device path for the persistent data volume. Empty = no separate disk, /mnt/data lives on the root disk. | `string` | `"/dev/sdb"` | no |
| <a name="input_dns_challenge_env"></a> [dns\_challenge\_env](#input\_dns\_challenge\_env) | Environment variables required by the DNS challenge provider. Empty map = credentials come from elsewhere (instance role, traefik\_extra\_environment, ...). | `map(string)` | `{}` | no |
| <a name="input_dns_challenge_provider"></a> [dns\_challenge\_provider](#input\_dns\_challenge\_provider) | Traefik ACME DNS challenge provider (e.g. route53, cloudflare) | `string` | `"route53"` | no |
| <a name="input_docker_compose_runner_image"></a> [docker\_compose\_runner\_image](#input\_docker\_compose\_runner\_image) | Docker image for the docker-compose-runner service | `string` | `"ghcr.io/miquido/gitlab-docker-compose-host:v1.4.0"` | no |
| <a name="input_docker_prune_schedule"></a> [docker\_prune\_schedule](#input\_docker\_prune\_schedule) | Cron schedule for Docker image pruning via Ofelia. Set to empty string to disable. | `string` | `"0 3 * * *"` | no |
| <a name="input_domain"></a> [domain](#input\_domain) | Base domain for wildcard certificate and routing (e.g. dmc.miquido.dev) | `string` | n/a | yes |
| <a name="input_enable_registry"></a> [enable\_registry](#input\_enable\_registry) | Run a registry:2 container at registry.<domain> (data in /mnt/data/registry, daily GC through Ofelia). It ships without authentication: protect it with static\_extra\_labels / extra\_compose\_services or the network. Independent of registry\_url, which is an external registry the host logs in to. | `bool` | `false` | no |
| <a name="input_enable_traefik_metrics"></a> [enable\_traefik\_metrics](#input\_enable\_traefik\_metrics) | Expose Traefik Prometheus metrics on the internal `metrics` entrypoint (:8080) for a collector to scrape. Enabled automatically when Alloy is. | `bool` | `false` | no |
| <a name="input_extra_compose_services"></a> [extra\_compose\_services](#input\_extra\_compose\_services) | YAML fragment with additional compose services, written at column 0 (it is indented under `services:` for you). | `string` | `""` | no |
| <a name="input_extra_packages"></a> [extra\_packages](#input\_extra\_packages) | Extra apt packages installed before Docker. | `list(string)` | `[]` | no |
| <a name="input_extra_runcmd"></a> [extra\_runcmd](#input\_extra\_runcmd) | Extra shell commands run (as root) after Docker is installed and the data dir exists, right before `docker compose up`. | `list(string)` | `[]` | no |
| <a name="input_extra_write_files"></a> [extra\_write\_files](#input\_extra\_write\_files) | Extra cloud-init write\_files entries. | <pre>list(object({<br/>    path        = string<br/>    content     = string<br/>    permissions = optional(string, "0644")<br/>    owner       = optional(string, "root:root")<br/>    append      = optional(bool, false)<br/>  }))</pre> | `[]` | no |
| <a name="input_hostname"></a> [hostname](#input\_hostname) | VM hostname set through cloud-init. Empty = leave to the platform. | `string` | `""` | no |
| <a name="input_ip_allowlist"></a> [ip\_allowlist](#input\_ip\_allowlist) | CIDR range allowed to access the docker-compose-runner endpoint | `string` | n/a | yes |
| <a name="input_nginx_static_server_extra"></a> [nginx\_static\_server\_extra](#input\_nginx\_static\_server\_extra) | Extra nginx directives inserted into the server block of the static-sites vhost. | `string` | `""` | no |
| <a name="input_ofelia_image"></a> [ofelia\_image](#input\_ofelia\_image) | Ofelia image running the scheduled jobs (backups, registry GC, image prune). Must be the netresearch fork: it follows Docker events and namespaces jobs per container (see docker-compose template). | `string` | `"ghcr.io/netresearch/ofelia:1.0.1"` | no |
| <a name="input_oidc_audience"></a> [oidc\_audience](#input\_oidc\_audience) | Expected OIDC audience for docker-compose-runner | `string` | n/a | yes |
| <a name="input_oidc_expected_subs"></a> [oidc\_expected\_subs](#input\_oidc\_expected\_subs) | List of expected OIDC subjects for docker-compose-runner | `list(string)` | n/a | yes |
| <a name="input_oidc_jwks_url"></a> [oidc\_jwks\_url](#input\_oidc\_jwks\_url) | JWKS URL for docker-compose-runner OIDC authentication | `string` | n/a | yes |
| <a name="input_passwd_hash"></a> [passwd\_hash](#input\_passwd\_hash) | Bcrypt hash of the password for vm\_user. Empty = password login disabled (SSH keys only). | `string` | `""` | no |
| <a name="input_registry_htpasswd"></a> [registry\_htpasswd](#input\_registry\_htpasswd) | htpasswd entries (bcrypt; comma-separated for several users) protecting the built-in registry with basic auth. Used with enable\_registry. When set, the host also logs in to registry.<domain> with registry\_username / registry\_password once the stack is up, so the docker-compose-runner can pull from it. | `string` | `""` | no |
| <a name="input_registry_password"></a> [registry\_password](#input\_registry\_password) | Password for docker login | `string` | `""` | no |
| <a name="input_registry_url"></a> [registry\_url](#input\_registry\_url) | External docker registry hostname to authenticate against (empty to skip). Not needed for the built-in registry: see registry\_htpasswd. | `string` | `""` | no |
| <a name="input_registry_username"></a> [registry\_username](#input\_registry\_username) | Username for docker login | `string` | `""` | no |
| <a name="input_ssh_public_keys"></a> [ssh\_public\_keys](#input\_ssh\_public\_keys) | List of SSH public keys added to vm\_user's authorized\_keys. | `list(string)` | `[]` | no |
| <a name="input_static_extra_labels"></a> [static\_extra\_labels](#input\_static\_extra\_labels) | Extra Docker labels for the nginx-static service (e.g. additional Traefik routers). | `list(string)` | `[]` | no |
| <a name="input_traefik_access_log"></a> [traefik\_access\_log](#input\_traefik\_access\_log) | Enable Traefik access log in JSON format on stdout. | `bool` | `false` | no |
| <a name="input_traefik_entrypoint"></a> [traefik\_entrypoint](#input\_traefik\_entrypoint) | Override the Traefik container entrypoint (compose `entrypoint:` list). Empty = image default. | `list(string)` | `[]` | no |
| <a name="input_traefik_extra_args"></a> [traefik\_extra\_args](#input\_traefik\_extra\_args) | Extra Traefik command-line arguments. | `list(string)` | `[]` | no |
| <a name="input_traefik_extra_environment"></a> [traefik\_extra\_environment](#input\_traefik\_extra\_environment) | Extra environment variables for the Traefik container. | `map(string)` | `{}` | no |
| <a name="input_traefik_extra_volumes"></a> [traefik\_extra\_volumes](#input\_traefik\_extra\_volumes) | Extra Traefik volume mounts (compose short syntax, e.g. /home/ubuntu/creds:/creds:ro). | `list(string)` | `[]` | no |
| <a name="input_use_ecr_credential_helper"></a> [use\_ecr\_credential\_helper](#input\_use\_ecr\_credential\_helper) | Install and configure amazon-ecr-credential-helper instead of static docker login | `bool` | `false` | no |
| <a name="input_vm_user"></a> [vm\_user](#input\_vm\_user) | Login user created on the VM. Its home holds docker-compose.yml and the helper scripts. | `string` | `"ubuntu"` | no |
| <a name="input_walg_env_vars"></a> [walg\_env\_vars](#input\_walg\_env\_vars) | WAL-G environment variables written to /etc/docker-host/walg.env (symlinked from /home/<vm\_user>/walg.env). Empty map = skip file generation. Cloud-agnostic: pass whatever KEY=VALUE pairs your storage backend requires (AWS S3 IAM, S3-compatible endpoint, GCS, Azure Blob, etc.). | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_cloud_init_config"></a> [cloud\_init\_config](#output\_cloud\_init\_config) | Rendered cloud-init configuration to pass as instance user\_data |
<!-- END_TF_DOCS -->

## License

[MIT](LICENSE)
