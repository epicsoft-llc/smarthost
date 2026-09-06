# Smarthost

This Docker image is managed and kept up to date by [epicsoft LLC](https://epicsoft.one).

Smarthost based on official [alpine](https://hub.docker.com/_/alpine) image.

This Docker image uses [postfix](https://pkgs.alpinelinux.org/packages?name=postfix) to create an SMTP relay.

* Base image: https://hub.docker.com/_/alpine
* Dockerfile: https://gitlab.com/epicsoft-networks/smarthost/blob/master/Dockerfile
* Repository: https://gitlab.com/epicsoft-networks/smarthost/tree/master
* Container-Registry: https://gitlab.com/epicsoft-networks/smarthost/container_registry
* Docker Hub: https://hub.docker.com/r/epicsoft/smarthost

## Description

Docker Image for Smarthost (SMTP relay) based on official Alpine image.

This image can be used
- Central SMTP relay for multiple Docker containers
- If applications cannot establish an encrypted connection to an SMTP server 
- The container is not granted Internet access, but emails should still be sent
- *Other possible uses for forwarding emails*

## Versions

`latest` based on `alpine:latest` - build `weekly`

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
    epicsoft/smarthost:latest
```

## License

MIT License see [LICENSE](https://gitlab.com/epicsoft-networks/smarthost/blob/master/LICENSE)

Please note that the MIT license only applies to the files created by epicsoft LLC. Other software may be licensed under other licenses.
