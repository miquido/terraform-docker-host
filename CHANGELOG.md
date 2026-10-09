# [2.1.0](https://gitlab.miquido.com/miquido/terraform/docker-host/compare/v2.0.1...v2.1.0) (2026-10-09)


### Features

* **mysql:** pitr-marker and marker:<name> for mysql-walg containers ([4317ac5](https://gitlab.miquido.com/miquido/terraform/docker-host/commit/4317ac56655327ee344010cc565505a2b831d2ea))
* pitr-marker, and marker:<name> as a pitr-restore target ([ca47253](https://gitlab.miquido.com/miquido/terraform/docker-host/commit/ca47253196d900a7dd1f4e7b1b2ef40c1421a1c9))

## [2.0.1](https://gitlab.miquido.com/miquido/terraform/docker-host/compare/v2.0.0...v2.0.1) (2026-10-07)


### Bug Fixes

* write walg.env as root:root and set the login user's group in runcmd ([f54b328](https://gitlab.miquido.com/miquido/terraform/docker-host/commit/f54b3280eb10ae6f44210c042a95950c0e34a26d))

# [2.0.0](https://gitlab.miquido.com/miquido/terraform/docker-host/compare/v1.4.2...v2.0.0) (2026-10-07)


* feat!: v2 — platform-neutral core with extension points, stable host paths, working scheduled backups ([83e4e02](https://gitlab.miquido.com/miquido/terraform/docker-host/commit/83e4e02ef24e4177a6d009ecb80bb23116c20d77))


### Bug Fixes

* review follow-ups — registry validation, pinned images, walg.env group, script hygiene ([d92928f](https://gitlab.miquido.com/miquido/terraform/docker-host/commit/d92928f9f2b2afbaf21fba1ac453da274c8617bf))


### BREAKING CHANGES

* the login user is ubuntu instead of dynamic (/home/ubuntu instead of /home/dynamic);
oidc_expected_subs is a list(string); cloudwatch_region and the CloudWatch agent moved out of the core
(use enable_traefik_metrics and the extra_* inputs in the platform wrapper); the nginx-static template
is rendered (nginx-static.conf.tftpl); passwd_hash is optional.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>

## [1.4.2](https://gitlab.miquido.com/miquido/terraform/docker-host/compare/v1.4.1...v1.4.2) (2026-08-20)


### Bug Fixes

* **cicd:** default validate-terraform ([eabb3fb](https://gitlab.miquido.com/miquido/terraform/docker-host/commit/eabb3fb1793119022442ee49eeffa420fa7eca92))

## [1.4.1](https://gitlab.miquido.com/miquido/terraform/docker-host/compare/v1.4.0...v1.4.1) (2026-08-20)


### Bug Fixes

* CICD ([52149a1](https://gitlab.miquido.com/miquido/terraform/docker-host/commit/52149a1c4c4bd742a97a8c03bb2b11fcce82447e))

# [1.1.0](https://gitlab.miquido.com/miquido/terraform/docker-host/compare/v1.0.0...v1.1.0) (2026-07-27)


### Features

* logs + static pages basic auth ([4da713d](https://gitlab.miquido.com/miquido/terraform/docker-host/commit/4da713d895c3ace742e6c957acfc2050e35059f9))

# 1.0.0 (2026-06-23)


### Bug Fixes

* README ([36118d2](https://gitlab.miquido.com/miquido/terraform/docker-host/commit/36118d21094057a613c61ded2b289a3a0e439e2a))


### Features

* metrics + resotre script ([483bcfd](https://gitlab.miquido.com/miquido/terraform/docker-host/commit/483bcfd19618636cff121bde49b74f98519cd52d))
* run prune on schedule ([eeb24f6](https://gitlab.miquido.com/miquido/terraform/docker-host/commit/eeb24f6e1f1ed0a236077a105bb79d945b5a6546))
* walg ([1e86dda](https://gitlab.miquido.com/miquido/terraform/docker-host/commit/1e86ddae891eddeffe3ea0921b1c084820b8ead7))
