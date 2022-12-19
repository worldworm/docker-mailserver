load "${REPOSITORY_ROOT}/test/helper/setup"
load "${REPOSITORY_ROOT}/test/helper/common"

TEST_NAME_PREFIX='Clam + SA disabled:'
CONTAINER_NAME='dms-test-disabled_clamav_spamassasin'

function setup_file() {
  init_with_defaults

  local CUSTOM_SETUP_ARGUMENTS=(
    --env ENABLE_AMAVIS=1
    --env ENABLE_CLAMAV=0
    --env ENABLE_SPAMASSASSIN=0
    --env AMAVIS_LOGLEVEL=2
  )

  common_container_setup 'CUSTOM_SETUP_ARGUMENTS'
  wait_for_smtp_port_in_container "${CONTAINER_NAME}"

  _run_in_container /bin/bash -c "nc 0.0.0.0 25 < /tmp/docker-mailserver-test/email-templates/existing-user1.txt"
  assert_success
  wait_for_empty_mail_queue_in_container "${CONTAINER_NAME}"
}

function teardown_file() { _default_teardown ; }

@test "${TEST_NAME_PREFIX} ClamAV disabled by ENABLED_CLAMAV=0" {
  _run_in_container /bin/bash -c "ps aux --forest | grep -v grep | grep '/usr/sbin/clamd'"
  assert_failure
}

@test "${TEST_NAME_PREFIX} SA should not be listed in Amavis when disabled" {
  _run_in_container /bin/sh -c "grep -i 'ANTI-SPAM-SA code' /var/log/mail/mail.log | grep 'NOT loaded'"
  assert_success
}

@test "${TEST_NAME_PREFIX} ClamAV should not be listed in Amavis when disabled" {
  _run_in_container grep -i 'Found secondary av scanner ClamAV-clamscan' /var/log/mail/mail.log
  assert_failure
}

@test "${TEST_NAME_PREFIX} SA should not be called when disabled" {
  _run_in_container grep -i 'connect to /var/run/clamav/clamd.ctl failed' /var/log/mail/mail.log
  assert_failure
}

@test "${TEST_NAME_PREFIX} restart of process ClamAV when disabled" {
  _run_in_container /bin/bash -c "pkill -f clamd && sleep 10 && ps aux --forest | grep -v grep | grep '/usr/sbin/clamd'"
  assert_failure
}
