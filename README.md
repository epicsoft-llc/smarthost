# Smarthost

<!-- vscode-markdown-toc -->
* 1. [Versions](#Versions)
* 2. [Requirements](#Requirements)
* 3. [Environment variables](#Environmentvariables)
* 4. [Example](#Example)
* 5. [Project-License](#Project-License)

<!-- vscode-markdown-toc-config
	numbering=true
	autoSave=true
	/vscode-markdown-toc-config -->
<!-- /vscode-markdown-toc -->

Docker Image for Smarthost (SMTP relay) based on Alpine Linux

##  1. <a name='Versions'></a>Versions

Two current versions `latest` and `edge` of this project are always built weekly.  
If you need special versions, please feel free to contact me or create a fork.

`latest` and `edge` [Dockerfile](https://gitlab.com/epicdocker/smarthost/-/blob/master/Dockerfile)

##  2. <a name='Requirements'></a>Requirements

- Docker installed - https://www.docker.com/get-started

##  3. <a name='Environmentvariables'></a>Environment variables

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

##  4. <a name='Example'></a>Example

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

##  5. <a name='Project-License'></a>Project-License

MIT License see [LICENSE](LICENSE)
