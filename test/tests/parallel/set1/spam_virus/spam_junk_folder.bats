load "${REPOSITORY_ROOT}/test/helper/setup"
load "${REPOSITORY_ROOT}/test/helper/common"

TEST_NAME_PREFIX='Spam junk folder:'

# Test case
# ---------
# When SPAMASSASSIN_SPAM_TO_INBOX=1, spam messages must be delivered
# and eventually (MOVE_SPAM_TO_JUNK=1) moved to the Junk folder.

@test "${TEST_NAME_PREFIX} (Amavis) spam message delivered & moved to Junk folder" {
  CONTAINER_NAME='dms-test-spam_junk_folder-1'
  local CUSTOM_SETUP_ARGUMENTS=(
    --env ENABLE_AMAVIS=1
    --env ENABLE_SPAMASSASSIN=1
    --env MOVE_SPAM_TO_JUNK=1
    --env PERMIT_DOCKER=container
    --env SA_SPAM_SUBJECT="SPAM: "
    --env SPAMASSASSIN_SPAM_TO_INBOX=1
  )
  init_with_defaults
  common_container_setup 'CUSTOM_SETUP_ARGUMENTS'
  wait_for_smtp_port_in_container "${CONTAINER_NAME}"

  function teardown() { _default_teardown ; }

  # send a spam message
  _run_in_container /bin/bash -c "nc 0.0.0.0 25 < /tmp/docker-mailserver-test/email-templates/amavis-spam.txt"
  assert_success

  # message will be added to a queue with varying delay until amavis receives it
  run repeat_until_success_or_timeout 60 sh -c "docker logs ${CONTAINER_NAME} | grep 'Passed SPAM {RelayedTaggedInbound,Quarantined}'"
  assert_success

  # spam moved to Junk folder
  run repeat_until_success_or_timeout 20 sh -c "docker exec ${CONTAINER_NAME} sh -c 'grep \"Subject: SPAM: \" /var/mail/localhost.localdomain/user1/.Junk/new/ -R'"
  assert_success
}

@test "${TEST_NAME_PREFIX} (Amavis) spam message delivered to INBOX" {
  CONTAINER_NAME='dms-test-spam_junk_folder-2'
  local CUSTOM_SETUP_ARGUMENTS=(
    --env ENABLE_AMAVIS=1
    --env ENABLE_SPAMASSASSIN=1
    --env MOVE_SPAM_TO_JUNK=0
    --env PERMIT_DOCKER=container
    --env SA_SPAM_SUBJECT="SPAM: "
    --env SPAMASSASSIN_SPAM_TO_INBOX=1
  )
  init_with_defaults
  common_container_setup 'CUSTOM_SETUP_ARGUMENTS'
  wait_for_smtp_port_in_container "${CONTAINER_NAME}"

  function teardown() { _default_teardown ; }

  # send a spam message
  _run_in_container /bin/bash -c "nc 0.0.0.0 25 < /tmp/docker-mailserver-test/email-templates/amavis-spam.txt"
  assert_success

  # message will be added to a queue with varying delay until amavis receives it
  run repeat_until_success_or_timeout 60 sh -c "docker logs ${CONTAINER_NAME} | grep 'Passed SPAM {RelayedTaggedInbound,Quarantined}'"
  assert_success

  # spam moved to INBOX
  run repeat_until_success_or_timeout 20 sh -c "docker exec ${CONTAINER_NAME} sh -c 'grep \"Subject: SPAM: \" /var/mail/localhost.localdomain/user1/new/ -R'"
  assert_success
}
