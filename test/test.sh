#!/bin/bash

#### Local test environment for the smarthost image. Everything happens in containers:
#### the relay, the SMTP sink it delivers to and the clients that submit mail. Nothing is
#### written to the host except the logs under 'test/.logs'.
####
####   bash test/test.sh all              every group ('default' is an alias for it)
####   bash test/test.sh relay tls        only these groups
####   bash test/test.sh --keep relay     leave the containers up afterwards
####   bash test/test.sh --list           print the group names
####   bash test/test.sh --help           this text
####
#### Called without an argument it prints this help: the run builds the image and pulls
#### the sink, so it is not what an accidental call should start.
####
#### Clean up with 'bash test/clean.sh env', which this script also does on its own at
#### the end of a run and on an interrupt.

# Everything created here carries the docker label 'smarthost-test'. That is what lets
# 'clean.sh' remove the leftovers of an interrupted run without knowing what ran.
#
# Deliberately without 'set -e': a failed assertion has to be counted and the run has to
# continue, otherwise the first failure hides all the others.

# Git Bash rewrites arguments that look like a unix path into a windows path before
# docker sees them, which would turn '/etc/postfix' into a path inside the git install
export MSYS_NO_PATHCONV=1

readonly TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly PROJECT_DIR="$(cd "${TEST_DIR}/.." && pwd)"
readonly LOG_DIR="${TEST_DIR}/.logs"

readonly LABEL="smarthost-test"
readonly PREFIX="smarthost-test"
readonly IMAGE="smarthost:test"
readonly NETWORK="${PREFIX}-net"

readonly ALPINE_IMAGE="alpine:latest"
# the sink accepts SMTP AUTH from anyone and exposes what arrived over HTTP
readonly SINK_IMAGE="axllent/mailpit:latest"
# busybox has no SMTP client that can be pointed at a host, python's smtplib can and also
# hands back the server's rejection code instead of just failing
readonly CLIENT_IMAGE="python:3-alpine"

readonly SINK_HOST="${PREFIX}-sink"
readonly SINK_SMTP_PORT="1025"
readonly SINK_API="http://${PREFIX}-sink:8025/api/v1"

# Throwaway credentials for containers that exist for the length of one run, are only
# reachable on this machine's own docker network and are removed at the end. They are
# fixtures, not secrets - nothing here is or has ever been a real credential.
#
# The password carries the characters that would break the generated map file if the
# script stopped quoting: a space, the map comment character, and a colon - which is also
# the separator between user and password on that line.
readonly RELAY_USER='relay@example.com'
readonly RELAY_PASSWORD='pa ss#wo:rd1'
readonly RELAY_DOMAIN='example.com'

# what has to come out the other end - proves a mail went through and is not just a log line
readonly MARKER='smarthost-marker-42'

readonly ALL_GROUPS="validation injection config quoting credentials headers tls relay lifecycle"

readonly COLOR_RESET='\033[0m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[0;33m'
readonly COLOR_RED='\033[0;31m'

KEEP="false"
TESTS_RUN=0
TESTS_FAILED=0
TESTS_SKIPPED=0
FAILED_NAMES=()
RUN_OUTPUT=""
RUN_LOG=""

###############################################################################
#### Reporting
###############################################################################

section() {
  printf '\n\033[1m%s\033[0m\n' "${1}"
}

info() {
  printf '  ..   %s\n' "${1}"
}

pass() {
  TESTS_RUN=$((TESTS_RUN + 1))
  printf "  ${COLOR_GREEN}PASS${COLOR_RESET} %s\n" "${1}"
}

# the reason is printed right here, the container log only on a failure - that is what
# keeps a green run to one line per case
fail() {
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_FAILED=$((TESTS_FAILED + 1))
  FAILED_NAMES+=("${1}")

  printf "  ${COLOR_RED}FAIL${COLOR_RESET} %s\n" "${1}"

  if [ ! -z "${2}" ]; then
    printf '       %s\n' "${2}"
  fi

  if [ ! -z "${RUN_LOG}" ] && [ -f "${RUN_LOG}" ]; then
    printf '       log: %s\n' "${RUN_LOG}"
  fi
}

skip() {
  TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
  printf "  ${COLOR_YELLOW}SKIP${COLOR_RESET} %s (%s)\n" "${1}" "${2}"
}

assertEquals() {
  if [ "${2}" == "${3}" ]; then
    pass "${1}"
  else
    fail "${1}" "expected '${2}', got '${3}'"
  fi
}

# compared with 'grep -F' and not with a case pattern: the needles include the test
# password, and a backslash in a case pattern escapes the next character, which would
# turn a leak into a pass
containsText() {
  printf '%s' "${1}" | grep -q -F -- "${2}"
}

# the haystack goes into the message: 'not found' alone does not say whether the value
# was wrong or whether the command that produced it failed and returned its error instead
assertContains() {
  if containsText "${2}" "${3}"; then
    pass "${1}"
  else
    fail "${1}" "'${3}' not found in: ...$(printf '%s' "${2}" | tr '\n' ' ' | tail -c 200)"
  fi
}

assertNotContains() {
  if containsText "${2}" "${3}"; then
    fail "${1}" "'${3}' should not appear in: ...$(printf '%s' "${2}" | tr '\n' ' ' | tail -c 200)"
  else
    pass "${1}"
  fi
}

###############################################################################
#### Docker helpers
###############################################################################

# pulled ahead of the run: the progress of a pull goes to stderr and would bury the one
# line per test case that the report is supposed to be
pullImage() {
  if [ ! -z "$(docker image ls -q "${1}")" ]; then
    return 0
  fi

  info "pulling ${1}"
  docker pull -q "${1}" >> "${LOG_DIR}/docker.log" 2>&1
}

# runs the image once and lets it exit. the output goes to a log file and into
# RUN_OUTPUT, the exit code is the return value - this is how the validation cases are
# checked, they never get as far as starting postfix
runOnce() {
  local _NAME=${1}
  local _CODE=0
  local _CONTAINER="${PREFIX}-once"

  shift

  RUN_LOG="${LOG_DIR}/${_NAME}.log"

  docker rm -f "${_CONTAINER}" > /dev/null 2>&1

  # Under a timeout, and started with a name so it can be removed again. Every caller
  # here expects the configuration to be rejected, and a rejection that stops working
  # does not turn into a failed assertion on its own: the image would start postfix in
  # the foreground, 'docker run' would never return and the whole run would hang. The
  # timeout turns that into exit 124 and an assertion that says what happened.
  timeout 60 docker run --rm --name "${_CONTAINER}" --label "${LABEL}" \
    "${@}" "${IMAGE}" > "${RUN_LOG}" 2>&1 || _CODE=$?

  if [ "${_CODE}" == "124" ]; then
    docker rm -f "${_CONTAINER}" > /dev/null 2>&1
    echo "--- the container was still running after 60s, so it was not rejected ---" \
      >> "${RUN_LOG}"
  fi

  RUN_OUTPUT="$(cat "${RUN_LOG}")"

  return ${_CODE}
}

# Starts a relay in the background with a working base configuration. A later '-e' wins
# over an earlier one, so a caller can override any of these without repeating the rest.
startRelay() {
  local _NAME=${1}

  shift

  docker rm -f "${_NAME}" > /dev/null 2>&1

  docker run -d --name "${_NAME}" --network "${NETWORK}" --label "${LABEL}" \
    -e "SMARTHOST_HOST=${SINK_HOST}" \
    -e "SMARTHOST_PORT=${SINK_SMTP_PORT}" \
    -e "SMARTHOST_USER=${RELAY_USER}" \
    -e "SMARTHOST_PASSWORD=${RELAY_PASSWORD}" \
    -e "SMARTHOST_DOMAIN=${RELAY_DOMAIN}" \
    "${@}" "${IMAGE}" > /dev/null 2>> "${LOG_DIR}/docker.log"
}

# 'postfix status' is the readiness probe rather than the log line 'Starting Smarthost':
# the script prints that before it execs postfix, so it says nothing about whether the
# mail system actually came up.
waitForRelay() {
  local _NAME=${1}
  local _TRIES=${2:-45}
  local _I=0

  RUN_LOG="${LOG_DIR}/${_NAME}.log"

  while [ ${_I} -lt ${_TRIES} ]; do
    if docker exec "${_NAME}" postfix status > /dev/null 2>&1; then
      docker logs "${_NAME}" > "${RUN_LOG}" 2>&1
      return 0
    fi

    if [ -z "$(docker ps -q --filter "name=^/${_NAME}$")" ]; then
      break
    fi

    sleep 1
    _I=$((_I + 1))
  done

  docker logs "${_NAME}" > "${RUN_LOG}" 2>&1
  info "'${_NAME}' was not ready after ${_I}s, see ${RUN_LOG}"

  return 1
}

removeRelay() {
  docker rm -f "${1}" > /dev/null 2>&1
}

# reads one main.cf value out of a running relay. '-h' prints the bare value, so an
# assertion compares what postfix really resolved and not a 'key = value' line that would
# also match a different key
postconfOf() {
  docker exec "${1}" postconf -h "${2}" 2>&1 | tr -d '\r'
}

# every command that touches a path or a glob goes through 'sh -c': without it the glob
# is expanded on the host, against the host's file system
inRelay() {
  docker exec "${1}" sh -c "${2}" 2>&1 | tr -d '\r'
}

###############################################################################
#### The SMTP sink
###############################################################################

startSink() {
  docker rm -f "${SINK_HOST}" > /dev/null 2>&1

  # accept-any plus allow-insecure: the relay authenticates over a plain connection, and
  # without both the sink would answer the AUTH with a failure and nothing would arrive
  docker run -d --name "${SINK_HOST}" --network "${NETWORK}" --label "${LABEL}" \
    -e MP_SMTP_AUTH_ACCEPT_ANY=true \
    -e MP_SMTP_AUTH_ALLOW_INSECURE=true \
    "${SINK_IMAGE}" > /dev/null 2>> "${LOG_DIR}/docker.log"
}

# read through a throwaway alpine container: the sink image has no shell, and this keeps
# the API on the docker network instead of needing a published port on the host
sinkGet() {
  docker run --rm --network "${NETWORK}" --label "${LABEL}" "${ALPINE_IMAGE}" \
    wget -qO- "${SINK_API}${1}" 2>/dev/null
}

sinkMessages() {
  sinkGet "/messages"
}

sinkTotal() {
  sinkMessages | grep -o '"total":[0-9]*' | head -1 | cut -d: -f2
}

waitForSink() {
  local _TRIES=${1:-45}
  local _I=0

  while [ ${_I} -lt ${_TRIES} ]; do
    if [ ! -z "$(sinkTotal)" ]; then
      return 0
    fi

    sleep 1
    _I=$((_I + 1))
  done

  docker logs "${SINK_HOST}" > "${LOG_DIR}/sink.log" 2>&1
  info "the sink was not ready after ${_I}s, see ${LOG_DIR}/sink.log"

  return 1
}

# Delivery is asynchronous - postfix accepts the mail, answers the client and only then
# contacts the sink. Asserting right after the submit would read the count of the moment
# before the relay got round to it.
waitForSinkCount() {
  local _WANT=${1}
  local _TRIES=${2:-30}
  local _I=0
  local _HAVE

  while [ ${_I} -lt ${_TRIES} ]; do
    _HAVE="$(sinkTotal)"

    if [ ! -z "${_HAVE}" ] && [ "${_HAVE}" -ge "${_WANT}" ]; then
      return 0
    fi

    sleep 1
    _I=$((_I + 1))
  done

  return 1
}

# hands the mail to the relay's own sendmail, which is the path a container on the same
# host uses when it is configured to relay through this image
submitViaSendmail() {
  local _RELAY=${1}
  local _FROM=${2}
  local _TO=${3}
  local _SUBJECT=${4}

  # the values are arguments to sh, not pasted into the script it runs: they carry
  # spaces and a '#', either of which would be read as syntax inside the command line
  docker exec "${_RELAY}" sh -c \
    'printf "From: %s\nTo: %s\nSubject: %s\n\n%s\n" "$1" "$2" "$3" "$4" | sendmail -f "$1" "$2"' \
    sh "${_FROM}" "${_TO}" "${_SUBJECT}" "${MARKER}" > /dev/null 2>&1
}

# submits over the network like a separate container would, and reports what the relay
# answered - that is what makes the mynetworks check meaningful
submitViaSmtp() {
  docker run --rm --network "${NETWORK}" --label "${LABEL}" "${CLIENT_IMAGE}" python -c '
import smtplib, sys

host, sender, rcpt, subject, marker = sys.argv[1:6]
body = "From: %s\r\nTo: %s\r\nSubject: %s\r\n\r\n%s\r\n" % (sender, rcpt, subject, marker)

try:
    server = smtplib.SMTP(host, 25, timeout=30)
    server.sendmail(sender, [rcpt], body)
    server.quit()
    print("ACCEPTED")
except smtplib.SMTPRecipientsRefused as refused:
    # the value is a (code, message) pair and the message is bytes - printing the pair
    # raw would report "REFUSED 454" and hide which refusal it was
    code, message = list(refused.recipients.values())[0]
    print("REFUSED %s %s" % (code, message.decode("utf-8", "replace")))
except Exception as error:
    print("ERROR %s" % (error,))
' "${1}" "${2}" "${3}" "${4}" "${MARKER}" 2>&1 | tail -1
}

###############################################################################
#### Group: validation - configuration is rejected before postfix is started
###############################################################################

group_validation() {
  section "validation - a missing variable stops the container with its own exit code"

  local _CODE=0

  runOnce "validation-nothing" || _CODE=$?
  assertEquals "a container without any configuration exits 101" "101" "${_CODE}"
  assertContains "  and names the variable" "${RUN_OUTPUT}" "'SMARTHOST_HOST'"

  # Every case sets a full configuration and then blanks one variable. That is what
  # separates 'this variable is checked' from 'some earlier check fired first': the codes
  # are ordered, so a missing HOST would mask all of them.
  local _CASE
  local _NAME
  local _WANT

  for _CASE in \
    "SMARTHOST_HOST:101" \
    "SMARTHOST_PORT:102" \
    "SMARTHOST_USER:103" \
    "SMARTHOST_PASSWORD:104" \
    "SMARTHOST_TLS_SECURITY_LEVEL:105" \
    "SMARTHOST_NETWORKS:106" \
    "SMARTHOST_DOMAIN:107" \
    "SMARTHOST_ADD_MISSING_HEADERS:108"
  do
    _NAME="${_CASE%:*}"
    _WANT="${_CASE#*:}"
    _CODE=0

    runOnce "validation-${_WANT}" \
      -e "SMARTHOST_HOST=${SINK_HOST}" \
      -e "SMARTHOST_USER=${RELAY_USER}" \
      -e "SMARTHOST_PASSWORD=${RELAY_PASSWORD}" \
      -e "SMARTHOST_DOMAIN=${RELAY_DOMAIN}" \
      -e "${_NAME}=" || _CODE=$?

    assertEquals "an empty ${_NAME} exits ${_WANT}" "${_WANT}" "${_CODE}"
    assertContains "  and says which variable" "${RUN_OUTPUT}" "'${_NAME}'"
  done

  # the four without a default in the Dockerfile are the ones a user can leave out
  # entirely rather than blank, and that has to be rejected the same way
  _CODE=0
  runOnce "validation-unset-user" \
    -e "SMARTHOST_HOST=${SINK_HOST}" \
    -e "SMARTHOST_PASSWORD=${RELAY_PASSWORD}" \
    -e "SMARTHOST_DOMAIN=${RELAY_DOMAIN}" || _CODE=$?
  assertEquals "an unset SMARTHOST_USER exits 103" "103" "${_CODE}"

  assertNotContains "no failing run prints the password" "${RUN_OUTPUT}" "${RELAY_PASSWORD}"
}

###############################################################################
#### Group: injection - a value that spans two lines is refused
###############################################################################

group_injection() {
  section "injection - no value may carry a second line"

  local _CODE
  local _VARIABLE

  # Every variable here ends up in a generated map file or on a postconf command line,
  # where a second line is not more text but a second entry.
  for _VARIABLE in \
    SMARTHOST_HOST \
    SMARTHOST_PORT \
    SMARTHOST_USER \
    SMARTHOST_PASSWORD \
    SMARTHOST_DOMAIN \
    SMARTHOST_TLS_SECURITY_LEVEL \
    SMARTHOST_NETWORKS \
    SMARTHOST_FORCE_FROM
  do
    _CODE=0

    runOnce "injection-${_VARIABLE}" \
      -e "SMARTHOST_HOST=${SINK_HOST}" \
      -e "SMARTHOST_USER=${RELAY_USER}" \
      -e "SMARTHOST_PASSWORD=${RELAY_PASSWORD}" \
      -e "SMARTHOST_DOMAIN=${RELAY_DOMAIN}" \
      -e "$(printf '%s=first\nsecond' "${_VARIABLE}")" || _CODE=$?

    assertEquals "a two line ${_VARIABLE} exits 109" "109" "${_CODE}"
    assertContains "  and names the variable" "${RUN_OUTPUT}" "'${_VARIABLE}'"
  done

  ## the payloads the check exists for ##
  _CODE=0
  runOnce "injection-header-rule" \
    -e "SMARTHOST_HOST=${SINK_HOST}" \
    -e "SMARTHOST_USER=${RELAY_USER}" \
    -e "SMARTHOST_PASSWORD=${RELAY_PASSWORD}" \
    -e "SMARTHOST_DOMAIN=${RELAY_DOMAIN}" \
    -e "$(printf 'SMARTHOST_FORCE_FROM=Ok <a@example.com>\n/^To:.*$/ REDIRECT elsewhere@nowhere.test')" \
    || _CODE=$?
  assertEquals "a second header_checks rule cannot be smuggled in" "109" "${_CODE}"

  _CODE=0
  runOnce "injection-sasl-entry" \
    -e "SMARTHOST_HOST=${SINK_HOST}" \
    -e "SMARTHOST_USER=${RELAY_USER}" \
    -e "SMARTHOST_DOMAIN=${RELAY_DOMAIN}" \
    -e "$(printf 'SMARTHOST_PASSWORD=pw\n[evil.example.com]:25 attacker:secret')" \
    || _CODE=$?
  assertEquals "a second set of relay credentials cannot be smuggled in" "109" "${_CODE}"

  # a carriage return does not end a line here, but it travels into the password unseen
  # and turns an authentication failure into a puzzle
  _CODE=0
  runOnce "injection-carriage-return" \
    -e "SMARTHOST_HOST=${SINK_HOST}" \
    -e "SMARTHOST_USER=${RELAY_USER}" \
    -e "SMARTHOST_DOMAIN=${RELAY_DOMAIN}" \
    -e "$(printf 'SMARTHOST_PASSWORD=pw\r')" || _CODE=$?
  assertEquals "a trailing carriage return is refused too" "109" "${_CODE}"

  # The counterpart: the check must reject a second line, not punctuation. Every one of
  # these characters is legal in the value and the relay has to come up with them.
  local _NAME="${PREFIX}-injection-ok"

  startRelay "${_NAME}" -e 'SMARTHOST_FORCE_FROM=A #1 $ Corp: Ltd <a@example.com>'

  if waitForRelay "${_NAME}"; then
    pass "punctuation in a single line value is still accepted"
  else
    fail "punctuation in a single line value is still accepted" "the relay did not come up"
  fi

  removeRelay "${_NAME}"
}

###############################################################################
#### Group: config - the environment is translated into main.cf
###############################################################################

group_config() {
  section "config - environment variables reach postfix"

  local _NAME="${PREFIX}-config"

  startRelay "${_NAME}" -e "SMARTHOST_NETWORKS=10.1.0.0/16,10.2.0.0/16"

  if ! waitForRelay "${_NAME}"; then
    skip "config" "the relay did not come up"
    removeRelay "${_NAME}"
    return 0
  fi

  assertEquals "the relay host and port become relayhost" \
    "[${SINK_HOST}]:${SINK_SMTP_PORT}" "$(postconfOf "${_NAME}" relayhost)"
  assertEquals "the domain becomes mydomain" \
    "${RELAY_DOMAIN}" "$(postconfOf "${_NAME}" mydomain)"
  assertEquals "the domain becomes myorigin" \
    "${RELAY_DOMAIN}" "$(postconfOf "${_NAME}" myorigin)"
  assertEquals "myhostname gets the 'mail.' prefix" \
    "mail.${RELAY_DOMAIN}" "$(postconfOf "${_NAME}" myhostname)"
  assertEquals "mydestination stays local only" \
    "localhost" "$(postconfOf "${_NAME}" mydestination)"
  assertEquals "the networks become mynetworks" \
    "10.1.0.0/16,10.2.0.0/16" "$(postconfOf "${_NAME}" mynetworks)"

  assertEquals "the mail log goes to stdout" \
    "/dev/stdout" "$(postconfOf "${_NAME}" maillog_file)"
  assertEquals "postfix listens on every interface" \
    "all" "$(postconfOf "${_NAME}" inet_interfaces)"
  assertEquals "and only on ipv4" \
    "ipv4" "$(postconfOf "${_NAME}" inet_protocols)"
  assertEquals "host lookup uses the container resolver first" \
    "native,dns" "$(postconfOf "${_NAME}" smtp_host_lookup)"

  assertEquals "sasl authentication is on" \
    "yes" "$(postconfOf "${_NAME}" smtp_sasl_auth_enable)"
  assertEquals "the password map is declared as lmdb" \
    "lmdb:/etc/postfix/sasl_passwd" "$(postconfOf "${_NAME}" smtp_sasl_password_maps)"
  assertEquals "anonymous authentication is refused" \
    "noanonymous" "$(postconfOf "${_NAME}" smtp_sasl_security_options)"

  # the map type is not spelled out on the postmap call, so it comes from this default -
  # if it ever stops being lmdb, the map postfix opens is not the one postmap wrote
  assertEquals "the default database type matches that declaration" \
    "lmdb" "$(postconfOf "${_NAME}" default_database_type)"

  removeRelay "${_NAME}"

  ## the loose boolean, both ways ##
  local _VALUE
  local _WANT
  local _CASE

  for _CASE in "true:yes" "TRUE:yes" "yes:yes" "1:yes" "false:no" "no:no" "NO:no" "0:no"; do
    _VALUE="${_CASE%:*}"
    _WANT="${_CASE#*:}"
    _NAME="${PREFIX}-bool"

    startRelay "${_NAME}" -e "SMARTHOST_ADD_MISSING_HEADERS=${_VALUE}"

    if waitForRelay "${_NAME}"; then
      assertEquals "SMARTHOST_ADD_MISSING_HEADERS='${_VALUE}' becomes '${_WANT}'" \
        "${_WANT}" "$(postconfOf "${_NAME}" always_add_missing_headers)"
    else
      skip "SMARTHOST_ADD_MISSING_HEADERS='${_VALUE}'" "the relay did not come up"
    fi

    removeRelay "${_NAME}"
  done
}

###############################################################################
#### Group: quoting - a value with a space must not tear the configuration apart
###############################################################################

group_quoting() {
  section "quoting - values with spaces survive"

  local _NAME="${PREFIX}-quoting"

  # This is the case that used to kill the container: unquoted, the value was split on
  # the space and postconf aborted with "missing '=' after attribute name" - an exit 1
  # that named neither the variable nor the reason.
  startRelay "${_NAME}" -e "SMARTHOST_NETWORKS=192.168.0.0/16, 172.16.0.0/12"

  if waitForRelay "${_NAME}"; then
    pass "a space in SMARTHOST_NETWORKS does not stop the container"
    assertEquals "  and the value arrives whole" \
      "192.168.0.0/16, 172.16.0.0/12" "$(postconfOf "${_NAME}" mynetworks)"
    assertNotContains "  without a postconf error in the log" \
      "$(cat "${RUN_LOG}")" "missing '=' after attribute name"
  else
    fail "a space in SMARTHOST_NETWORKS does not stop the container" \
      "the container did not come up: $(tail -c 200 "${RUN_LOG}" 2>/dev/null | tr '\n' ' ')"
  fi

  removeRelay "${_NAME}"

  # A domain with a space is not a valid one, and postfix says so. That it complains
  # about the whole value is the point: the space reached postfix instead of splitting
  # the command, which is the difference between a rejected configuration and a shell
  # accident that half-configures the relay.
  local _CODE=0

  runOnce "quoting-domain" \
    -e "SMARTHOST_HOST=${SINK_HOST}" \
    -e "SMARTHOST_USER=${RELAY_USER}" \
    -e "SMARTHOST_PASSWORD=${RELAY_PASSWORD}" \
    -e "SMARTHOST_DOMAIN=two words.example.com" || _CODE=$?

  if [ "${_CODE}" == "0" ]; then
    fail "an invalid domain stops the container" "the run succeeded"
  else
    pass "an invalid domain stops the container"
  fi

  assertContains "  and postfix rejects the value whole" \
    "${RUN_OUTPUT}" "mail.two words.example.com"
  assertNotContains "  not as two split arguments" \
    "${RUN_OUTPUT}" "missing '=' after attribute name"
}

###############################################################################
#### Group: credentials - the password map is written and kept readable but private
###############################################################################

group_credentials() {
  section "credentials - the sasl map is correct and not world readable"

  local _NAME="${PREFIX}-credentials"

  startRelay "${_NAME}"

  if ! waitForRelay "${_NAME}"; then
    skip "credentials" "the relay did not come up"
    removeRelay "${_NAME}"
    return 0
  fi

  assertEquals "the map holds host, user and password" \
    "[${SINK_HOST}]:${SINK_SMTP_PORT} ${RELAY_USER}:${RELAY_PASSWORD}" \
    "$(inRelay "${_NAME}" 'cat /etc/postfix/sasl_passwd')"

  # read back through postfix's own lookup: the file content could be right while the
  # compiled map that postfix actually opens is stale or was built from a different file
  assertEquals "and postfix looks the password up again unchanged" \
    "${RELAY_USER}:${RELAY_PASSWORD}" \
    "$(inRelay "${_NAME}" "postmap -q '[${SINK_HOST}]:${SINK_SMTP_PORT}' lmdb:/etc/postfix/sasl_passwd")"

  assertEquals "the map is not world readable" \
    "640" "$(inRelay "${_NAME}" 'stat -c %a /etc/postfix/sasl_passwd')"
  assertEquals "the compiled map is not world readable either" \
    "640" "$(inRelay "${_NAME}" 'stat -c %a /etc/postfix/sasl_passwd.lmdb')"
  assertEquals "both belong to the postfix group" \
    "root:postfix root:postfix" \
    "$(inRelay "${_NAME}" 'stat -c %U:%G /etc/postfix/sasl_passwd /etc/postfix/sasl_passwd.lmdb | tr "\n" " " | sed "s/ $//"')"

  # 0600 would pass the 'not world readable' check and still be wrong: smtp(8) runs as
  # mail_owner and opens the map itself, so it has to stay readable for that user
  assertEquals "the postfix user can still read it" \
    "${RELAY_USER}:${RELAY_PASSWORD}" \
    "$(inRelay "${_NAME}" "su postfix -s /bin/sh -c \"postmap -q '[${SINK_HOST}]:${SINK_SMTP_PORT}' lmdb:/etc/postfix/sasl_passwd\"")"

  assertContains "any other user cannot" \
    "$(inRelay "${_NAME}" 'su nobody -s /bin/sh -c "cat /etc/postfix/sasl_passwd"')" \
    "Permission denied"

  assertNotContains "the password is not in the container log" \
    "$(cat "${RUN_LOG}")" "${RELAY_PASSWORD}"

  removeRelay "${_NAME}"
}

###############################################################################
#### Group: headers - the from rewrite and the missing header option
###############################################################################

group_headers() {
  section "headers - SMARTHOST_FORCE_FROM builds the rewrite map"

  local _NAME="${PREFIX}-headers"
  local _FORCE_FROM='Example LLC <info@example.com>'

  startRelay "${_NAME}" -e "SMARTHOST_FORCE_FROM=${_FORCE_FROM}"

  if ! waitForRelay "${_NAME}"; then
    skip "headers" "the relay did not come up"
    removeRelay "${_NAME}"
    return 0
  fi

  assertEquals "the rewrite is wired up as a regexp map" \
    "regexp:/etc/postfix/header_check" "$(postconfOf "${_NAME}" smtp_header_checks)"

  assertEquals "the map holds the replacement with its original casing" \
    "/^From:.*\$/ REPLACE From: ${_FORCE_FROM}" \
    "$(inRelay "${_NAME}" 'cat /etc/postfix/header_check')"

  # A regexp map is read as plain text. Compiling one produced a file postfix never
  # opens, in which postmap lowercased the pattern to '/^from:.*$/' - so its absence is
  # what says the pointless compile is gone.
  assertContains "the regexp map is not compiled" \
    "$(inRelay "${_NAME}" 'ls /etc/postfix/header_check.lmdb')" \
    "No such file or directory"

  removeRelay "${_NAME}"

  ## a '$' is a back-reference in the replacement and has to be doubled ##
  _NAME="${PREFIX}-headers-dollar"
  startRelay "${_NAME}" -e 'SMARTHOST_FORCE_FROM=Acme $1 Corp <a@example.com>'

  if waitForRelay "${_NAME}"; then
    assertEquals "a '\$' in the value reaches the map doubled" \
      '/^From:.*$/ REPLACE From: Acme $$1 Corp <a@example.com>' \
      "$(inRelay "${_NAME}" 'cat /etc/postfix/header_check')"
  else
    fail "a '\$' in the value reaches the map doubled" "the relay did not come up"
  fi

  removeRelay "${_NAME}"

  ## without the variable there must be no rewrite at all ##
  _NAME="${PREFIX}-headers-off"
  startRelay "${_NAME}"

  if waitForRelay "${_NAME}"; then
    assertEquals "without SMARTHOST_FORCE_FROM nothing is rewritten" \
      "" "$(postconfOf "${_NAME}" smtp_header_checks)"
    assertContains "  and no map is written" \
      "$(inRelay "${_NAME}" 'ls /etc/postfix/header_check')" \
      "No such file or directory"
  else
    skip "without SMARTHOST_FORCE_FROM nothing is rewritten" "the relay did not come up"
  fi

  removeRelay "${_NAME}"
}

###############################################################################
#### Group: tls - the security level and the implicit TLS port
###############################################################################

group_tls() {
  section "tls - security level and port 465"

  local _NAME="${PREFIX}-tls"
  local _LEVEL

  for _LEVEL in may encrypt none verify; do
    startRelay "${_NAME}" -e "SMARTHOST_TLS_SECURITY_LEVEL=${_LEVEL}"

    if waitForRelay "${_NAME}"; then
      assertEquals "SMARTHOST_TLS_SECURITY_LEVEL='${_LEVEL}' reaches postfix" \
        "${_LEVEL}" "$(postconfOf "${_NAME}" smtp_tls_security_level)"
    else
      skip "SMARTHOST_TLS_SECURITY_LEVEL='${_LEVEL}'" "the relay did not come up"
    fi

    removeRelay "${_NAME}"
  done

  ## the default from the Dockerfile ##
  startRelay "${_NAME}"

  if waitForRelay "${_NAME}"; then
    assertEquals "the default level is opportunistic TLS" \
      "may" "$(postconfOf "${_NAME}" smtp_tls_security_level)"
    assertEquals "and a normal port does not wrap the connection" \
      "no" "$(postconfOf "${_NAME}" smtp_tls_wrappermode)"
  else
    skip "the default level is opportunistic TLS" "the relay did not come up"
  fi

  removeRelay "${_NAME}"

  ## port 465 is implicit TLS and deliberately overrides the level ##
  _NAME="${PREFIX}-tls-465"
  startRelay "${_NAME}" -e "SMARTHOST_PORT=465" -e "SMARTHOST_TLS_SECURITY_LEVEL=may"

  if waitForRelay "${_NAME}"; then
    assertEquals "port 465 wraps the connection in TLS" \
      "yes" "$(postconfOf "${_NAME}" smtp_tls_wrappermode)"
    assertEquals "  and overrides a weaker security level" \
      "encrypt" "$(postconfOf "${_NAME}" smtp_tls_security_level)"
  else
    skip "port 465 wraps the connection in TLS" "the relay did not come up"
  fi

  removeRelay "${_NAME}"
}

###############################################################################
#### Group: relay - a mail actually goes through, and only from a trusted client
###############################################################################

group_relay() {
  section "relay - mail is delivered and the relay is not open"

  startSink

  if ! waitForSink; then
    skip "relay" "the sink did not come up"
    return 0
  fi

  ## a mail handed in locally reaches the far side unchanged ##
  local _NAME="${PREFIX}-relay"

  startRelay "${_NAME}"

  if ! waitForRelay "${_NAME}"; then
    skip "relay" "the relay did not come up"
    removeRelay "${_NAME}"
    return 0
  fi

  local _BEFORE="$(sinkTotal)"

  submitViaSendmail "${_NAME}" "sender@${RELAY_DOMAIN}" "rcpt@example.org" "plain-${MARKER}"

  if waitForSinkCount "$((_BEFORE + 1))"; then
    pass "a mail submitted to the relay arrives at the far side"

    local _MESSAGES="$(sinkMessages)"

    assertContains "  with its subject" "${_MESSAGES}" "plain-${MARKER}"
    assertContains "  and its original sender" "${_MESSAGES}" "sender@${RELAY_DOMAIN}"

    docker logs "${_NAME}" > "${RUN_LOG}" 2>&1

    # the delivery log only reaches 'docker logs' because maillog_file points at stdout,
    # so this is also what proves that setting works
    assertContains "the delivery is logged to stdout" "$(cat "${RUN_LOG}")" "status=sent"
    assertNotContains "  and the log does not carry the password" \
      "$(cat "${RUN_LOG}")" "${RELAY_PASSWORD}"
  else
    docker logs "${_NAME}" > "${RUN_LOG}" 2>&1
    fail "a mail submitted to the relay arrives at the far side" \
      "the sink still holds ${_BEFORE} message(s)"
  fi

  removeRelay "${_NAME}"

  ## with SMARTHOST_FORCE_FROM the delivered mail carries the replacement ##
  _NAME="${PREFIX}-relay-rewrite"
  startRelay "${_NAME}" -e "SMARTHOST_FORCE_FROM=Example LLC <info@example.com>"

  if waitForRelay "${_NAME}"; then
    _BEFORE="$(sinkTotal)"

    submitViaSendmail "${_NAME}" "rewrite-me@nowhere.test" "rcpt@example.org" "rewrite-${MARKER}"

    if waitForSinkCount "$((_BEFORE + 1))"; then
      local _REWRITTEN="$(sinkGet "/search?query=subject%3Arewrite-${MARKER}")"

      assertContains "SMARTHOST_FORCE_FROM replaces the From of a delivered mail" \
        "${_REWRITTEN}" "info@example.com"
      assertContains "  including the display name" "${_REWRITTEN}" "Example LLC"
      assertNotContains "  and the original address is gone from the header" \
        "${_REWRITTEN}" "rewrite-me@nowhere.test"
    else
      fail "SMARTHOST_FORCE_FROM replaces the From of a delivered mail" "nothing arrived"
    fi
  else
    skip "SMARTHOST_FORCE_FROM replaces the From of a delivered mail" "the relay did not come up"
  fi

  removeRelay "${_NAME}"

  ## A '$' in the replacement used to cost the rewrite without costing the delivery:
  ## postfix logged 'out of range replacement index', skipped the rule, and sent the mail
  ## on with its original From. Only a delivered mail can tell those two apart.
  _NAME="${PREFIX}-relay-dollar"
  startRelay "${_NAME}" -e 'SMARTHOST_FORCE_FROM=Acme $1 Corp <a@example.com>'

  if waitForRelay "${_NAME}"; then
    _BEFORE="$(sinkTotal)"

    submitViaSendmail "${_NAME}" "dollar-me@nowhere.test" "rcpt@example.org" "dollar-${MARKER}"

    if waitForSinkCount "$((_BEFORE + 1))"; then
      local _DELIVERED="$(sinkGet "/search?query=subject%3Adollar-${MARKER}")"

      assertContains "a '\$' in the replacement still rewrites the From" \
        "${_DELIVERED}" 'Acme $1 Corp'
      assertNotContains "  and does not leave the original address on the mail" \
        "${_DELIVERED}" "dollar-me@nowhere.test"

      docker logs "${_NAME}" > "${RUN_LOG}" 2>&1

      assertNotContains "  and postfix does not skip the rule" \
        "$(cat "${RUN_LOG}")" "out of range replacement index"
    else
      fail "a '\$' in the replacement still rewrites the From" "nothing arrived"
    fi
  else
    fail "a '\$' in the replacement still rewrites the From" "the relay did not come up"
  fi

  removeRelay "${_NAME}"

  ## a client on the trusted network may relay ##
  _NAME="${PREFIX}-relay-net"
  startRelay "${_NAME}" -e "SMARTHOST_NETWORKS=0.0.0.0/0"

  if waitForRelay "${_NAME}"; then
    _BEFORE="$(sinkTotal)"

    local _ANSWER="$(submitViaSmtp "${_NAME}" "client@${RELAY_DOMAIN}" "rcpt@example.org" "net-${MARKER}")"

    assertEquals "a client inside mynetworks may relay" "ACCEPTED" "${_ANSWER}"

    if waitForSinkCount "$((_BEFORE + 1))"; then
      pass "  and its mail is delivered"
    else
      fail "  and its mail is delivered" "the sink still holds ${_BEFORE} message(s)"
    fi
  else
    skip "a client inside mynetworks may relay" "the relay did not come up"
  fi

  removeRelay "${_NAME}"

  ## a client outside it may not - this is what keeps the image from being an open relay ##
  _NAME="${PREFIX}-relay-closed"
  startRelay "${_NAME}" -e "SMARTHOST_NETWORKS=10.99.99.0/24"

  if waitForRelay "${_NAME}"; then
    local _REFUSED="$(submitViaSmtp "${_NAME}" "outsider@nowhere.test" "rcpt@example.org" "closed-${MARKER}")"

    assertContains "a client outside mynetworks is refused" "${_REFUSED}" "REFUSED"
    assertContains "  with a relay access denial" "${_REFUSED}" "Relay access denied"
  else
    skip "a client outside mynetworks is refused" "the relay did not come up"
  fi

  removeRelay "${_NAME}"
}

###############################################################################
#### Group: lifecycle - how the container starts, runs and stops
###############################################################################

group_lifecycle() {
  section "lifecycle - start, signals and the alias database"

  local _NAME="${PREFIX}-lifecycle"

  startRelay "${_NAME}" -e "TZ=Europe/Berlin"

  if ! waitForRelay "${_NAME}"; then
    skip "lifecycle" "the relay did not come up"
    removeRelay "${_NAME}"
    return 0
  fi

  assertContains "the start is reported as successful" \
    "$(cat "${RUN_LOG}")" "Configuration success"

  # 'exec postfix' is what makes postfix pid 1. Without it the shell stays in front, and
  # a SIGTERM from 'docker stop' would reach the shell instead of the mail system.
  assertContains "postfix runs as pid 1" \
    "$(inRelay "${_NAME}" 'tr "\\0" " " < /proc/1/cmdline')" "postfix/master"

  assertContains "it listens on port 25" \
    "$(inRelay "${_NAME}" 'netstat -ltn')" "0.0.0.0:25"

  assertEquals "TZ reaches the container" "CEST" "$(inRelay "${_NAME}" 'date +%Z')"

  assertContains "the alias database is initialised by default" \
    "$(cat "${RUN_LOG}")" "Initialize the alias database"
  assertEquals "  and the database exists" \
    "/etc/postfix/aliases.lmdb" "$(inRelay "${_NAME}" 'ls /etc/postfix/aliases.lmdb')"

  # A SIGTERM that is not handled costs the full 10 second timeout and then a SIGKILL,
  # which would cut a delivery in progress. Anything under that means postfix took it.
  local _START="$(date +%s)"
  docker stop "${_NAME}" > /dev/null 2>&1
  local _TOOK=$(( $(date +%s) - _START ))

  if [ ${_TOOK} -lt 8 ]; then
    pass "the container stops on SIGTERM instead of being killed (${_TOOK}s)"
  else
    fail "the container stops on SIGTERM instead of being killed" \
      "'docker stop' needed ${_TOOK}s, so the signal was not handled"
  fi

  removeRelay "${_NAME}"

  ## the alias database can be turned off ##
  _NAME="${PREFIX}-lifecycle-noalias"
  startRelay "${_NAME}" -e "SMARTHOST_INIT_ALIAS_DATABASE=false"

  if waitForRelay "${_NAME}"; then
    pass "the relay also starts with the alias database turned off"
    assertNotContains "  and does not initialise it" \
      "$(cat "${RUN_LOG}")" "Initialize the alias database"
    assertContains "  so the database is absent" \
      "$(inRelay "${_NAME}" 'ls /etc/postfix/aliases.lmdb')" "No such file or directory"
  else
    fail "the relay also starts with the alias database turned off" "it did not come up"
  fi

  removeRelay "${_NAME}"
}

###############################################################################
#### Main
###############################################################################

cleanup() {
  if [ "${KEEP}" == "true" ]; then
    printf '\n--keep: the containers are left running, remove them with bash test/clean.sh env\n'
    return 0
  fi

  printf '\n'
  bash "${TEST_DIR}/clean.sh" env
}

# only the leading '####' block, not every line starting with it - the section banners
# further down do too
usage() {
  awk '
    /^####/ { started = 1; sub(/^#### ?/, ""); print; next }
    started { exit }
  ' "$0"
}

main() {
  local _GROUPS=""
  local _ARG

  if [ ${#} == 0 ]; then
    usage
    exit 0
  fi

  for _ARG in "${@}"; do
    case "${_ARG}" in
      --list ) echo "${ALL_GROUPS}"; exit 0 ;;
      --help | -h ) usage; exit 0 ;;
      --keep ) KEEP="true" ;;
      # Both select everything - there is no group worth leaving out of a normal run.
      # 'default' means less than 'all' in the sibling image repositories, where it skips
      # the groups that pull a database image, so it is accepted here rather than being
      # an error for someone coming from those.
      default | all ) _GROUPS="${_GROUPS} ${ALL_GROUPS}" ;;
      -* ) echo "unknown option '${_ARG}'"; exit 1 ;;
      * ) _GROUPS="${_GROUPS} ${_ARG}" ;;
    esac
  done

  # reached by something like '--keep' on its own, which selects no group at all
  if [ -z "${_GROUPS}" ]; then
    echo "no group given"
    echo
    usage
    exit 1
  fi

  if [ -z "$(docker info --format '{{.ServerVersion}}' 2>/dev/null)" ]; then
    echo "docker is not reachable"
    exit 1
  fi

  # This repository has no .gitattributes and git is configured with core.autocrlf=true,
  # so a fresh clone on windows can put CRLF into the script. ADD copies it as it is and
  # the container then dies with "$'\r': command not found" - a confusing failure to hunt
  # down from a test.
  if grep -q $'\r' "${PROJECT_DIR}/smarthost.sh" 2>/dev/null; then
    echo "smarthost.sh has CRLF line endings - the image will not run"
    echo "run: dos2unix smarthost.sh   (or check out the file with LF endings)"
    exit 1
  fi

  # Two runs at once destroy each other: they share the network and the container names,
  # and the cleanup of whichever finishes first pulls them out from under the other. That
  # surfaces as 'network not found' in the middle of an unrelated test, which costs far
  # more time to understand than this check costs to run.
  if [ ! -z "$(docker ps -q --filter "label=${LABEL}")" ]; then
    echo "containers of another run are still up:"
    docker ps --filter "label=${LABEL}" --format '  {{.Names}} ({{.Status}})'
    echo
    echo "wait for that run to finish, or remove them with 'bash test/clean.sh env'"
    exit 1
  fi

  mkdir -p "${LOG_DIR}"
  rm -f "${LOG_DIR}"/*.log

  trap cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM

  section "building ${IMAGE}"

  # built from inside the project with '.' as the context: MSYS_NO_PATHCONV keeps git
  # bash from rewriting container paths, but it would then also hand docker - a windows
  # binary - a '/c/...' build context it cannot resolve. A relative path needs no
  # rewriting either way.
  if ! ( cd "${PROJECT_DIR}" && docker build -t "${IMAGE}" . ) > "${LOG_DIR}/build.log" 2>&1; then
    echo "  the build failed, see ${LOG_DIR}/build.log"
    exit 1
  fi

  info "built"

  pullImage "${ALPINE_IMAGE}"
  pullImage "${SINK_IMAGE}"
  pullImage "${CLIENT_IMAGE}"

  docker network create --label "${LABEL}" "${NETWORK}" > /dev/null 2>&1

  local _GROUP

  # 'all relay' names a group twice, and running one of them twice costs time for nothing
  local _UNIQUE=""

  for _GROUP in ${_GROUPS}; do
    case " ${_UNIQUE} " in
      *" ${_GROUP} "* ) continue ;;
    esac

    _UNIQUE="${_UNIQUE} ${_GROUP}"
  done

  for _GROUP in ${_UNIQUE}; do
    if [ -z "$(type -t "group_${_GROUP}")" ]; then
      echo "unknown group '${_GROUP}', known are: ${ALL_GROUPS}"
      exit 1
    fi

    "group_${_GROUP}"
  done

  section "summary"

  printf '  %s test(s), %s failed, %s skipped\n' "${TESTS_RUN}" "${TESTS_FAILED}" "${TESTS_SKIPPED}"

  if [ ${TESTS_FAILED} != 0 ]; then
    local _FAILED

    for _FAILED in "${FAILED_NAMES[@]}"; do
      printf "  ${COLOR_RED}failed${COLOR_RESET} %s\n" "${_FAILED}"
    done

    printf '  logs: %s\n' "${LOG_DIR}"
    exit 1
  fi

  printf "  ${COLOR_GREEN}everything passed${COLOR_RESET}\n"
}

main "${@}"
