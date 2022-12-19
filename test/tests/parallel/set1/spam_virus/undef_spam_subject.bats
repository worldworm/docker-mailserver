load "${REPOSITORY_ROOT}/test/helper/setup"
load "${REPOSITORY_ROOT}/test/helper/common"

TEST_NAME_PREFIX='Undefined spam subject:'

CONTAINER1_NAME='dms-test-undef_spam_subject-1'
CONTAINER2_NAME='dms-test-undef_spam_subject-2'
CONTAINER_NAME=${CONTAINER2_NAME}

function setup() {
  local CONTAINER_NAME=${CONTAINER1_NAME}
  local CUSTOM_SETUP_ARGUMENTS=(
    --env ENABLE_AMAVIS=1
    --env ENABLE_SPAMASSASSIN=1
    --env SA_SPAM_SUBJECT='undef'
  )
  init_with_defaults
  common_container_setup 'CUSTOM_SETUP_ARGUMENTS'
  wait_for_smtp_port_in_container "${CONTAINER_NAME}"

  local CONTAINER_NAME=${CONTAINER2_NAME}
  local CUSTOM_SETUP_ARGUMENTS=(
    --env ENABLE_CLAMAV=1
    --env SPOOF_PROTECTION=1
    --env ENABLE_SPAMASSASSIN=1
    --env REPORT_RECIPIENT=user1@localhost.localdomain
    --env REPORT_SENDER=report1@mail.my-domain.com
    --env SA_TAG=-5.0
    --env SA_TAG2=2.0
    --env SA_KILL=3.0
    --env SA_SPAM_SUBJECT="SPAM: "
    --env VIRUSMAILS_DELETE_DELAY=7
    --env ENABLE_SRS=1
    --env SASL_PASSWD="external-domain.com username:password"
    --env ENABLE_MANAGESIEVE=1
    --env PERMIT_DOCKER=host
    --ulimit "nofile=$(ulimit -Sn):$(ulimit -Hn)"
  )
  init_with_defaults
  common_container_setup 'CUSTOM_SETUP_ARGUMENTS'
  wait_for_smtp_port_in_container "${CONTAINER_NAME}"
}

function teardown_file() {
  docker rm -f "${CONTAINER1_NAME}" "${CONTAINER2_NAME}"
}

@test "${TEST_NAME_PREFIX} Docker env variables are set correctly (custom)" {
  _run_in_container /bin/bash -c "grep '\$sa_tag_level_deflt' /etc/amavis/conf.d/20-debian_defaults | grep '= -5.0'"
  assert_success

  _run_in_container /bin/bash -c "grep '\$sa_tag2_level_deflt' /etc/amavis/conf.d/20-debian_defaults | grep '= 2.0'"
  assert_success

  _run_in_container /bin/bash -c "grep '\$sa_kill_level_deflt' /etc/amavis/conf.d/20-debian_defaults | grep '= 3.0'"
  assert_success

  _run_in_container /bin/bash -c "grep '\$sa_spam_subject_tag' /etc/amavis/conf.d/20-debian_defaults | grep '= .SPAM: .'"
  assert_success

  run docker exec "${CONTAINER1_NAME}" /bin/sh -c "grep '\$sa_spam_subject_tag' /etc/amavis/conf.d/20-debian_defaults | grep '= undef'"
  assert_success
}
