locals {
  domain_escaped = replace(var.domain, ".", "\\\\.")

  docker_compose_content = templatefile("${path.module}/templates/docker-compose.yml.tftpl", {
    domain                      = var.domain
    domain_escaped              = local.domain_escaped
    dns_challenge_provider      = var.dns_challenge_provider
    dns_challenge_env           = var.dns_challenge_env
    acme_email                  = var.acme_email
    oidc_jwks_url               = var.oidc_jwks_url
    oidc_audience               = var.oidc_audience
    oidc_expected_subs          = var.oidc_expected_subs
    ip_allowlist                = var.ip_allowlist
    docker_compose_runner_image = var.docker_compose_runner_image
    registry_url                = var.registry_url
    use_ecr_credential_helper   = var.use_ecr_credential_helper
    walg_s3_endpoint            = var.walg_s3_endpoint
  })

  startup_sh_content = templatefile("${path.module}/templates/startup.sh.tftpl", {
    block_device = var.block_device
  })

  cloud_init_config = templatefile("${path.module}/templates/cloud-init.yml.tftpl", {
    passwd                     = var.passwd_hash
    registry_url               = var.registry_url
    registry_username          = var.registry_username
    registry_password          = var.registry_password
    use_ecr_credential_helper  = var.use_ecr_credential_helper
    walg_s3_endpoint           = var.walg_s3_endpoint
    walg_s3_access_key_id      = var.walg_s3_access_key_id
    walg_s3_secret_access_key  = var.walg_s3_secret_access_key
    walg_s3_region             = var.walg_s3_region
    docker_compose_content     = local.docker_compose_content
    startup_sh_content         = local.startup_sh_content
    traefik_tls_content        = file("${path.module}/templates/traefik-tls.yml")
    nginx_static_content       = file("${path.module}/templates/nginx-static.conf")
  })
}
