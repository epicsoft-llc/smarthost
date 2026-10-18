# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
the versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

| Part | Raised when |
|---|---|
| **MAJOR** | an existing configuration stops working — a removed or renamed variable, a changed exit code or default |
| **MINOR** | a variable or a feature is added without changing existing configurations |
| **PATCH** | a rebuild with updated packages or a fix |

**A release is a git tag `X.Y.Z`.** CI builds `X.Y.Z`, `X.Y` and `X` from it for `linux/amd64` and `linux/arm64`, moves
`latest` and creates the GitHub release from the entry below. Each release entry names the contained versions:
Postfix, OpenSSL and Alpine. The weekly `latest` builds are not listed here.

## [1.0.0] - 2026-10-18

### Contents

- Postfix `3.11.7`, OpenSSL `3.5.9`, Alpine `3.24.2`

### Added

- Releases from git tags `X.Y.Z` with the image tags `X.Y.Z`, `X.Y` and `X`, and a GitHub release from this changelog
- A mirror on GitHub: `github.com/epicsoft-llc/smarthost`
- A local test environment under `test/`: `bash test/test.sh all` runs the relay against an SMTP sink in containers

### Changed

- Each platform is built and tested before the push - `postconf` has to answer, and a missing `SMARTHOST_HOST` has to
  stop the start with `101`. The versions used to be checked only after the image was published
- The packages of the base image are upgraded as well (`apk upgrade`), so security fixes such as OpenSSL `3.5.9` reach
  the image before the next Alpine point release
- Registry logins and the Docker Hub description upload take their tokens over stdin or the environment instead of the
  command line
- The base image is selected with the build argument `ALPINE_VERSION`; `IMAGE_TAG` only fills the version labels
