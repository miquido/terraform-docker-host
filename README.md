# docker-host <a href="https://miquido.com"><img align="right" src="https://cdn.miquido.dev/miquido-logo.png" width="150" /></a>

Terraform module that generates a cloud-init configuration for a Docker host with Traefik reverse proxy, OIDC-authenticated docker-compose-runner, and optional CloudWatch/Grafana Alloy observability.

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
| <a name="input_alloy_remote_write_token"></a> [alloy\_remote\_write\_token](#input\_alloy\_remote\_write\_token) | Basic auth password / token for Alloy remote\_write. | `string` | `""` | no |
| <a name="input_alloy_remote_write_url"></a> [alloy\_remote\_write\_url](#input\_alloy\_remote\_write\_url) | Full Prometheus remote\_write URL for Grafana Alloy (e.g. https://metrics.../api/v1/push). Empty string disables Alloy. | `string` | `""` | no |
| <a name="input_alloy_remote_write_username"></a> [alloy\_remote\_write\_username](#input\_alloy\_remote\_write\_username) | Basic auth username for Alloy remote\_write. Scaleway Cockpit uses 'scaleway'. | `string` | `"scaleway"` | no |
| <a name="input_block_device"></a> [block\_device](#input\_block\_device) | Block device path for the persistent data volume | `string` | `"/dev/sdb"` | no |
| <a name="input_cloudwatch_region"></a> [cloudwatch\_region](#input\_cloudwatch\_region) | AWS region for CloudWatch (logs + metrics). Empty string disables both. | `string` | `""` | no |
| <a name="input_dns_challenge_env"></a> [dns\_challenge\_env](#input\_dns\_challenge\_env) | Environment variables required by the DNS challenge provider | `map(string)` | n/a | yes |
| <a name="input_dns_challenge_provider"></a> [dns\_challenge\_provider](#input\_dns\_challenge\_provider) | Traefik ACME DNS challenge provider (e.g. route53, cloudflare) | `string` | `"route53"` | no |
| <a name="input_docker_compose_runner_image"></a> [docker\_compose\_runner\_image](#input\_docker\_compose\_runner\_image) | Docker image for the docker-compose-runner service | `string` | `"ghcr.io/miquido/gitlab-docker-compose-host:199983-be07bdc3"` | no |
| <a name="input_docker_prune_schedule"></a> [docker\_prune\_schedule](#input\_docker\_prune\_schedule) | Cron schedule for Docker image pruning via Ofelia. Set to empty string to disable. | `string` | `"0 3 * * *"` | no |
| <a name="input_domain"></a> [domain](#input\_domain) | Base domain for wildcard certificate and routing (e.g. dmc.miquido.dev) | `string` | n/a | yes |
| <a name="input_ip_allowlist"></a> [ip\_allowlist](#input\_ip\_allowlist) | CIDR range allowed to access the docker-compose-runner endpoint | `string` | n/a | yes |
| <a name="input_oidc_audience"></a> [oidc\_audience](#input\_oidc\_audience) | Expected OIDC audience for docker-compose-runner | `string` | n/a | yes |
| <a name="input_oidc_expected_subs"></a> [oidc\_expected\_subs](#input\_oidc\_expected\_subs) | Comma-separated list of expected OIDC subjects for docker-compose-runner | `string` | n/a | yes |
| <a name="input_oidc_jwks_url"></a> [oidc\_jwks\_url](#input\_oidc\_jwks\_url) | JWKS URL for docker-compose-runner OIDC authentication | `string` | n/a | yes |
| <a name="input_passwd_hash"></a> [passwd\_hash](#input\_passwd\_hash) | Bcrypt hash of the password for the dynamic user | `string` | n/a | yes |
| <a name="input_registry_password"></a> [registry\_password](#input\_registry\_password) | Password for docker login | `string` | `""` | no |
| <a name="input_registry_url"></a> [registry\_url](#input\_registry\_url) | Docker registry hostname to authenticate against (empty to skip) | `string` | `""` | no |
| <a name="input_registry_username"></a> [registry\_username](#input\_registry\_username) | Username for docker login | `string` | `""` | no |
| <a name="input_ssh_public_keys"></a> [ssh\_public\_keys](#input\_ssh\_public\_keys) | List of SSH public keys added to the dynamic user's authorized\_keys. | `list(string)` | `[]` | no |
| <a name="input_use_ecr_credential_helper"></a> [use\_ecr\_credential\_helper](#input\_use\_ecr\_credential\_helper) | Install and configure amazon-ecr-credential-helper instead of static docker login | `bool` | `false` | no |
| <a name="input_walg_env_vars"></a> [walg\_env\_vars](#input\_walg\_env\_vars) | WAL-G environment variables written to /home/dynamic/walg.env. Empty map = skip file generation. Cloud-agnostic: pass whatever KEY=VALUE pairs your storage backend requires (AWS S3 IAM, S3-compatible endpoint, GCS, Azure Blob, etc.). | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_cloud_init_config"></a> [cloud\_init\_config](#output\_cloud\_init\_config) | Rendered cloud-init configuration to pass as instance user\_data |
<!-- END_TF_DOCS -->

## License

[MIT](LICENSE)
