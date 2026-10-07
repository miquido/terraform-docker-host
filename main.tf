locals {
  # Trusted (host-side) scheduler config. The docker-prune job lives here, not in container labels:
  # label-defined job-run jobs that mount docker.sock are dropped by Ofelia's security policy.
  ofelia_ini_content = <<-EOT
    [global]
    job-exec-label-scope = container
    # The fork defaults to `nobody`; the previous Ofelia ran jobs as root, and the backup/binlog
    # jobs need to read the database data directory.
    default-user = root
    %{if var.docker_prune_schedule != ""~}

    [job-run "docker-prune"]
    schedule = ${var.docker_prune_schedule}
    image = docker:cli
    volume = /var/run/docker.sock:/var/run/docker.sock
    command = docker image prune -af
    %{endif~}
  EOT

  # The built-in registry, once protected, is also the registry the host itself pulls from.
  local_registry_login = var.registry_url == "" && var.enable_registry && var.registry_htpasswd != ""
  registry_url         = local.local_registry_login ? "registry.${var.domain}" : var.registry_url

  domain_escaped = replace(var.domain, ".", "\\\\.")

  alloy_config_content = (var.alloy_remote_write_url != "" || var.alloy_loki_write_url != "") ? templatefile("${path.module}/templates/alloy-config.alloy.tftpl", {
    alloy_remote_write_url      = var.alloy_remote_write_url
    alloy_remote_write_username = var.alloy_remote_write_username
    alloy_remote_write_token    = var.alloy_remote_write_token
    alloy_loki_write_url        = var.alloy_loki_write_url
    alloy_loki_write_username   = var.alloy_loki_write_username
    alloy_loki_write_token      = var.alloy_loki_write_token
  }) : ""

  docker_compose_content = templatefile("${path.module}/templates/docker-compose.yml.tftpl", {
    domain                      = var.domain
    domain_escaped              = local.domain_escaped
    dns_challenge_provider      = var.dns_challenge_provider
    dns_challenge_env           = var.dns_challenge_env
    acme_email                  = var.acme_email
    oidc_jwks_url               = var.oidc_jwks_url
    oidc_audience               = var.oidc_audience
    oidc_expected_subs          = join(",", var.oidc_expected_subs)
    ip_allowlist                = var.ip_allowlist
    docker_compose_runner_image = var.docker_compose_runner_image
    registry_url                = local.registry_url
    registry_htpasswd           = var.registry_htpasswd
    registry_deferred_login     = local.local_registry_login
    vm_user                     = var.vm_user
    enable_registry             = var.enable_registry
    traefik_access_log          = var.traefik_access_log
    traefik_entrypoint          = var.traefik_entrypoint
    traefik_extra_volumes       = var.traefik_extra_volumes
    traefik_extra_environment   = var.traefik_extra_environment
    traefik_extra_args          = var.traefik_extra_args
    static_extra_labels         = var.static_extra_labels
    extra_compose_services      = var.extra_compose_services
    use_ecr_credential_helper   = var.use_ecr_credential_helper
    walg_env_vars               = var.walg_env_vars
    docker_prune_schedule       = var.docker_prune_schedule
    ofelia_image                = var.ofelia_image
    alloy_remote_write_url      = var.alloy_remote_write_url
    alloy_loki_write_url        = var.alloy_loki_write_url
    enable_traefik_metrics      = var.enable_traefik_metrics
  })

  nginx_static_content = templatefile("${path.module}/templates/nginx-static.conf.tftpl", {
    server_extra = var.nginx_static_server_extra
  })

  startup_sh_content = templatefile("${path.module}/templates/startup.sh.tftpl", {
    block_device = var.block_device
  })

  pitr_restore_sh_content       = file("${path.module}/templates/pitr-restore.sh")
  pitr_restore_mysql_sh_content = file("${path.module}/templates/pitr-restore-mysql.sh")

  cloud_init_config = templatefile("${path.module}/templates/cloud-init.yml.tftpl", {
    vm_user                       = var.vm_user
    hostname                      = var.hostname
    ofelia_ini_content            = local.ofelia_ini_content
    passwd                        = var.passwd_hash
    enable_registry               = var.enable_registry
    extra_packages                = var.extra_packages
    extra_write_files             = var.extra_write_files
    extra_runcmd                  = var.extra_runcmd
    ssh_public_keys               = var.ssh_public_keys
    registry_url                  = local.registry_url
    registry_deferred_login       = local.local_registry_login
    registry_username             = var.registry_username
    registry_password             = var.registry_password
    use_ecr_credential_helper     = var.use_ecr_credential_helper
    walg_env_vars                 = var.walg_env_vars
    domain                        = var.domain
    docker_compose_content        = local.docker_compose_content
    alloy_config_content          = local.alloy_config_content
    startup_sh_content            = local.startup_sh_content
    pitr_restore_sh_content       = local.pitr_restore_sh_content
    pitr_restore_mysql_sh_content = local.pitr_restore_mysql_sh_content
    traefik_tls_content           = file("${path.module}/templates/traefik-tls.yml")
    nginx_static_content          = local.nginx_static_content
  })
}
