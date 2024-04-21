# Smarthost

This Docker image is managed and kept up to date by [epicsoft LLC](https://epicsoft.one).

Unlighthouse based on official [alpine](https://hub.docker.com/_/alpine) image.

This Docker image uses [postfix](https://pkgs.alpinelinux.org/packages?name=postfix) to create an SMTP relay.

* Base image: https://hub.docker.com/_/alpine
* Dockerfile: TODO
* Repository: TODO
* Container-Registry: TODO
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
- `SMARTHOST_DOMAIN` The domain to append to mails  ***required***
- `SMARTHOST_USE_TLS` Use TLS for communication with SMTP server (default: `true`)
- `SMARTHOST_NETWORKS` The list of trusted remote SMTP clients  (default: `192.168.0.0/16,172.16.0.0/12`)
- `SMARTHOST_ADD_MISSING_HEADERS` Add headers when not present (default: `true`)
- `SMARTHOST_FORCE_FROM` Replaces the from address with the specified one (default: *empty*)
- `SMARTHOST_INIT_ALIAS_DATABASE` Initialize the alias database (default: `true`)
- `TZ` Defines the time zone for the Docker container (default: *unset*)

## Example

```bash
docker run --rm -it \
  --name smarthost \
  -e SMARTHOST_HOST=mail.example.com \
  -e SMARTHOST_PORT=465 \
  -e SMARTHOST_USER=user@example.com \   
  -e SMARTHOST_PASSWORD=mySecretPassword \
  -e SMARTHOST_DOMAIN=example.com \
  -e SMARTHOST_FORCE_FROM="Firstname Lastname <user@example.com>" \
  -e SMARTHOST_ADD_MISSING_HEADERS="true" \
    registry.gitlab.com/epicdocker/smarthost:latest
```

## License

MIT License see [LICENSE](LICENSE)

Please note that the MIT license only applies to the files created by epicsoft LLC. Other software may be licensed under other licenses.
