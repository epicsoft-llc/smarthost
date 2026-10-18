# Smarthost

This Docker image is managed and kept up to date by [epicsoft LLC](https://epicsoft.one).

[Postfix](https://www.postfix.org/) as an SMTP relay (smarthost) on the official [Alpine image](https://hub.docker.com/_/alpine):
containers hand their mail to it, and it delivers the mail to your mail server with authentication and TLS.

* Base image: https://hub.docker.com/_/alpine, platforms `linux/amd64` and `linux/arm64`
* Dockerfile: https://gitlab.com/epicsoft-networks/smarthost/-/blob/master/Dockerfile
* Repository: https://gitlab.com/epicsoft-networks/smarthost, mirrored to [GitHub](https://github.com/epicsoft-llc/smarthost) — issues are welcome on both; code changes only as merge requests on GitLab, the mirror overwrites anything pushed to GitHub
* Container registry: https://gitlab.com/epicsoft-networks/smarthost/container_registry
* Docker Hub: https://hub.docker.com/r/epicsoft/smarthost
* Changelog: https://gitlab.com/epicsoft-networks/smarthost/-/blob/master/CHANGELOG.md
* License: MIT

## Description

This image can be used as
- Central SMTP relay for multiple Docker containers
- If applications cannot establish an encrypted connection to an SMTP server 
- The container is not granted Internet access, but emails should still be sent
- *Other possible uses for forwarding emails*

## Versions

Released through a git tag `X.Y.Z`, which publishes `X.Y.Z`, `X.Y` and `X` and moves `latest`. Changes and the
contained versions are listed in the [changelog](https://gitlab.com/epicsoft-networks/smarthost/-/blob/master/CHANGELOG.md).

| Tag | Content |
|---|---|
| `1.0.0` | exactly this build - **use this in production** |
| `1.0`, `1` | newest release of that line |
| `latest` | the `master` branch, rebuilt weekly on `alpine:latest`, also moved by every release |
| `develop` | current state of the `develop` branch, GitLab registry only, not for production |

`1.0.0` contains Postfix `3.11.7`, OpenSSL `3.5.9` and Alpine `3.24.2`.

## Environment variables

- `SMARTHOST_HOST` The remote SMTP server address ***required***
- `SMARTHOST_PORT` The remote SMTP server port (default: `587`)
- `SMARTHOST_USER` The username to authenticate with the remote SMTP server ***required***
- `SMARTHOST_PASSWORD` The password to authenticate with the remote SMTP server ***required***
- `SMARTHOST_DOMAIN` The domain to append to mails ***required***
- `SMARTHOST_TLS_SECURITY_LEVEL` Configuring TLS support (default `may`)
- `SMARTHOST_NETWORKS` The list of trusted remote SMTP clients, comma separated **without spaces**  (default: `192.168.0.0/16,172.16.0.0/12`)
- `SMARTHOST_ADD_MISSING_HEADERS` Add headers when not present (default: `true`)
- `SMARTHOST_FORCE_FROM` Replaces the from address with the specified one (default: *empty*)  
  Rewrites the visible `From:` header only, not the envelope sender  
  A `$` in the value is taken literally, no escaping needed
- `SMARTHOST_INIT_ALIAS_DATABASE` Initialize the alias database (default: `true`)
- `TZ` Defines the time zone for the Docker container (default: *unset*)

**SMARTHOST_TLS_SECURITY_LEVEL** - possible values:
- `none` - No TLS
- `may` - Opportunistic TLS
- `encrypt` - Mandatory TLS encryption
- `dane` - Opportunistic DANE TLS
- `dane-only` - Mandatory DANE TLS
- `fingerprint` - Certificate fingerprint verification
- `verify` - Mandatory server certificate verification
- `secure` - Secure-channel TLS

Every variable listed with a default must not be set to an empty value - the container
refuses to start. On port `465` (implicit TLS) `SMARTHOST_TLS_SECURITY_LEVEL` is ignored:
the connection is always wrapped in TLS and the level is forced to `encrypt`.

## Exit codes

The container validates its configuration before starting Postfix and exits with a
distinct code per missing variable:

| Code | Variable |
| ---- | -------- |
| `101` | `SMARTHOST_HOST` |
| `102` | `SMARTHOST_PORT` |
| `103` | `SMARTHOST_USER` |
| `104` | `SMARTHOST_PASSWORD` |
| `105` | `SMARTHOST_TLS_SECURITY_LEVEL` |
| `106` | `SMARTHOST_NETWORKS` |
| `107` | `SMARTHOST_DOMAIN` |
| `108` | `SMARTHOST_ADD_MISSING_HEADERS` |
| `109` | any of the above, or `SMARTHOST_FORCE_FROM`, given as more than one line |

No value may span more than one line. A second line would become a further entry in the
generated Postfix map - another set of relay credentials, or another header rewrite rule.

## Example

```bash
docker run --rm -it \
  --name smarthost \
  -e SMARTHOST_HOST=mail.your-business.ge \
  -e SMARTHOST_PORT=465 \
  -e SMARTHOST_USER=info@your-business.ge \
  -e SMARTHOST_PASSWORD=mySecretPassword \
  -e SMARTHOST_DOMAIN=your-business.ge \
  -e SMARTHOST_FORCE_FROM="Your Business LLC <info@your-business.ge>" \
  -e SMARTHOST_ADD_MISSING_HEADERS="true" \
    epicsoft/smarthost:1.0
```

## Reporting problems

Issues are welcome on [GitLab](https://gitlab.com/epicsoft-networks/smarthost/-/issues) and
[GitHub](https://github.com/epicsoft-llc/smarthost/issues). Please report a security problem as a
**confidential issue** on GitLab instead of a public one.

## License

[MIT](https://gitlab.com/epicsoft-networks/smarthost/-/blob/master/LICENSE) — Copyright (c) 2022-2026 epicsoft LLC / Alexander Schwarz

The MIT license applies only to files created by epicsoft LLC. Third-party software in the image — Postfix, the Alpine
packages and the official `alpine` image — remains under its own licenses.
