load "${REPOSITORY_ROOT}/test/helper/setup"
load "${REPOSITORY_ROOT}/test/helper/common"

TEST_NAME_PREFIX='Fail2Ban:'
CONTAINER1_NAME='dms-test-fail2ban'
CONTAINER2_NAME='dms-test-fail2ban-fail_auth_mailer'
CONTAINER_NAME=${CONTAINER1_NAME}

function setup() {
  CONTAINER2_IP=$(docker inspect --format '{{ .NetworkSettings.IPAddress }}' "${CONTAINER2_NAME}")
}

function setup_file() {
  local CONTAINER_NAME=${CONTAINER1_NAME}
  local CUSTOM_SETUP_ARGUMENTS=(
    --env ENABLE_FAIL2BAN=1
    --env POSTSCREEN_ACTION=ignore
    --cap-add=NET_ADMIN
    --ulimit "nofile=$(ulimit -Sn):$(ulimit -Hn)"
  )
  init_with_defaults
  common_container_setup 'CUSTOM_SETUP_ARGUMENTS'
  wait_for_smtp_port_in_container "${CONTAINER_NAME}"

  local CONTAINER_NAME=${CONTAINER2_NAME}
  local CUSTOM_SETUP_ARGUMENTS=(--env MAIL_FAIL2BAN_IP="$(docker inspect --format '{{ .NetworkSettings.IPAddress }}' ${CONTAINER1_NAME})")
  init_with_defaults
  common_container_setup 'CUSTOM_SETUP_ARGUMENTS'
}

function teardown_file() {
  docker rm -f "${CONTAINER1_NAME}" "${CONTAINER2_NAME}"
}

@test "${TEST_NAME_PREFIX} Fail2Ban is running" {
  _run_in_container /bin/bash -c "ps aux --forest | grep -v grep | grep '/usr/bin/python3 /usr/bin/fail2ban-server'"
  assert_success
}

@test "${TEST_NAME_PREFIX} localhost is not banned because ignored" {
  _run_in_container /bin/sh -c "fail2ban-client status postfix-sasl | grep 'IP list:.*127.0.0.1'"
  assert_failure
  _run_in_container grep 'ignoreip = 127.0.0.1/8' /etc/fail2ban/jail.conf
  assert_success
}

@test "${TEST_NAME_PREFIX} fail2ban-fail2ban.cf overrides" {
  _run_in_container fail2ban-client get loglevel
  assert_success
  assert_output --partial 'DEBUG'
}

@test "${TEST_NAME_PREFIX} fail2ban-jail.cf overrides" {
  for FILTER in 'dovecot' 'postfix' 'postfix-sasl'
  do
    _run_in_container /bin/sh -c "fail2ban-client get ${FILTER} bantime"
    assert_output 1234

    _run_in_container /bin/sh -c "fail2ban-client get ${FILTER} findtime"
    assert_output 321

    _run_in_container /bin/sh -c "fail2ban-client get ${FILTER} maxretry"
    assert_output 2

    _run_in_container /bin/sh -c "fail2ban-client -d | grep -F \"['set', 'dovecot', 'addaction', 'nftables-multiport']\""
    assert_output "['set', 'dovecot', 'addaction', 'nftables-multiport']"

    _run_in_container /bin/sh -c "fail2ban-client -d | grep -F \"['set', 'postfix', 'addaction', 'nftables-multiport']\""
    assert_output "['set', 'postfix', 'addaction', 'nftables-multiport']"

    _run_in_container /bin/sh -c "fail2ban-client -d | grep -F \"['set', 'postfix-sasl', 'addaction', 'nftables-multiport']\""
    assert_output "['set', 'postfix-sasl', 'addaction', 'nftables-multiport']"
  done
}

@test "${TEST_NAME_PREFIX} ban ip on multiple failed login" {
  # can't pipe the file as usual due to postscreen
  # respecting postscreen_greet_wait time and talking in turn):

  # shellcheck disable=SC1004
  for _ in {1,2}
  do
    docker exec "${CONTAINER2_NAME}" /bin/bash -c \
    'exec 3<>/dev/tcp/${MAIL_FAIL2BAN_IP}/25 && \
    while IFS= read -r cmd; do \
      head -1 <&3; \
      [[ ${cmd} == "EHLO"* ]] && sleep 6; \
      echo ${cmd} >&3; \
    done < "/tmp/docker-mailserver-test/auth/smtp-auth-login-wrong.txt"'
  done

  # need a bit more sleep as the test below that ´
  # restarts F2B might interfere otherwise
  sleep 30

  # Checking that CONTAINER2_IP is banned in "${CONTAINER1_NAME}"
  _run_in_container fail2ban-client status postfix-sasl
  assert_success
  assert_output --partial "${CONTAINER2_IP}"

  # Checking that CONTAINER2_IP is banned by nftables
  _run_in_container nft list set inet f2b-table addr-set-postfix-sasl
  # BATS can reorder tests when running in parallel, which means we cannot use
  # 'elements = { ${CONTAINER2_IP} }' because there might be other IPs already
  # banned.
  assert_output --partial "${CONTAINER2_IP}"
}

@test "${TEST_NAME_PREFIX} unban ip works" {
  _run_in_container fail2ban-client set postfix-sasl unbanip "${CONTAINER2_IP}"
  assert_success
  sleep 5

  _run_in_container fail2ban-client status postfix-sasl
  assert_success
  refute_output "IP list:.*${CONTAINER2_IP}"

  # Checking that CONTAINER2_IP is unbanned by nftables
  _run_in_container /bin/bash -c "nft list set inet f2b-table addr-set-postfix-sasl"
  refute_output --partial "${CONTAINER2_IP}"
}

@test "${TEST_NAME_PREFIX} bans work properly" {
  # Ban single IP address
  _run_in_container fail2ban ban 192.0.66.7
  assert_success
  assert_output 'Banned custom IP: 1'

  _run_in_container fail2ban
  assert_success
  assert_output --regexp 'Banned in custom:.*192\.0\.66\.7'

  _run_in_container nft list set inet f2b-table addr-set-custom
  assert_success
  assert_output --partial 'elements = { 192.0.66.7 }'

  _run_in_container fail2ban unban 192.0.66.7
  assert_success
  assert_output --partial 'Unbanned IP from custom: 1'

  _run_in_container nft list set inet f2b-table addr-set-custom
  refute_output --partial '192.0.66.7'

  # Ban IP network
  _run_in_container fail2ban ban 192.0.66.0/24
  assert_success
  assert_output 'Banned custom IP: 1'

  _run_in_container fail2ban
  assert_success
  assert_output --regexp 'Banned in custom:.*192\.0\.66\.0/24'

  _run_in_container nft list set inet f2b-table addr-set-custom
  assert_success
  assert_output --partial 'elements = { 192.0.66.0/24 }'

  _run_in_container fail2ban unban 192.0.66.0/24
  assert_success
  assert_output --partial 'Unbanned IP from custom: 1'

  _run_in_container nft list set inet f2b-table addr-set-custom
  refute_output --partial '192.0.66.0/24'
}

@test "${TEST_NAME_PREFIX} FAIL2BAN_BLOCKTYPE is really set to drop" {
  _run_in_container fail2ban-client set dovecot banip 192.33.44.55
  _run_in_container fail2ban-client set postfix-sasl banip 192.33.44.55
  _run_in_container fail2ban-client set custom banip 192.33.44.55

  _run_in_container nft list table inet f2b-table
  assert_success
  assert_output --partial 'tcp dport { 110, 143, 465, 587, 993, 995, 4190 } ip saddr @addr-set-dovecot drop'
  assert_output --partial 'tcp dport { 25, 110, 143, 465, 587, 993, 995 } ip saddr @addr-set-postfix-sasl drop'
  assert_output --partial 'tcp dport { 25, 110, 143, 465, 587, 993, 995, 4190 } ip saddr @addr-set-custom drop'
}

@test "${TEST_NAME_PREFIX} setup.sh fail2ban" {
  _run_in_container fail2ban-client set dovecot banip 192.0.66.4
  _run_in_container fail2ban-client set dovecot banip 192.0.66.5

  sleep 10

  run ./setup.sh -c "${CONTAINER1_NAME}" fail2ban
  assert_output --regexp 'Banned in dovecot:.*192\.0\.66\.4.*'
  assert_output --regexp 'Banned in dovecot:.*192\.0\.66\.5.*'

  run ./setup.sh -c "${CONTAINER1_NAME}" fail2ban unban 192.0.66.4
  assert_output --partial "Unbanned IP from dovecot: 1"

  run ./setup.sh -c "${CONTAINER1_NAME}" fail2ban
  assert_output --regexp "Banned in dovecot:.*192\.0\.66\.5.*"

  run ./setup.sh -c "${CONTAINER1_NAME}" fail2ban unban 192.0.66.5
  assert_output --partial "Unbanned IP from dovecot: 1"

  run ./setup.sh -c "${CONTAINER1_NAME}" fail2ban unban
  assert_output --partial "You need to specify an IP address: Run"
}

@test "${TEST_NAME_PREFIX} restart of Fail2Ban" {
  _run_in_container /bin/bash -c "pkill fail2ban && sleep 10 && ps aux --forest | grep -v grep | grep '/usr/bin/python3 /usr/bin/fail2ban-server'"
  assert_success
}
