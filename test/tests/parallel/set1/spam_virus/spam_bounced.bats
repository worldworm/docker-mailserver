load "${REPOSITORY_ROOT}/test/helper/setup"
load "${REPOSITORY_ROOT}/test/helper/common"

BATS_TEST_NAME_PREFIX='[Spam] (bounced) '
CONTAINER_NAME='dms-test_spam-bounced'

function setup_file() {
  _init_with_defaults

  local CUSTOM_SETUP_ARGUMENTS=(
    --env ENABLE_AMAVIS=1
    --env ENABLE_SPAMASSASSIN=1
    --env PERMIT_DOCKER=container
    --env SPAMASSASSIN_SPAM_TO_INBOX=0
  )

  _common_container_setup 'CUSTOM_SETUP_ARGUMENTS'
  _wait_for_smtp_port_in_container_to_respond
}

function teardown_file() { _default_teardown ; }

# Test case
# ---------
# When SPAMASSASSIN_SPAM_TO_INBOX=0, spam messages must be bounced (rejected).
# SPAMASSASSIN_SPAM_TO_INBOX=1 is covered in `mail_spam_junk_folder.bats`.
# Original test PR: https://github.com/docker-mailserver/docker-mailserver/pull/1485
@test "spam message is bounced (rejected)" {
  # send a spam message
  _run_in_container /bin/sh -c "nc 0.0.0.0 25 < /tmp/docker-mailserver-test/email-templates/amavis-spam.txt"
  assert_success

  # message will be added to a queue with varying delay until amavis receives it
  run _repeat_until_success_or_timeout 60 sh -c "docker logs ${CONTAINER_NAME} | grep 'Blocked SPAM {NoBounceInbound,Quarantined}'"
  assert_success
}
