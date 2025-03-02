load "${REPOSITORY_ROOT}/test/helper/setup"
load "${REPOSITORY_ROOT}/test/helper/common"

# Tests the `setup.sh` companion script.
# Only test coverage below is that the config path `-p` and image `-i` options work as intended.
# NOTE: Must be run in serial mode, as no existing containers should be present.
BATS_TEST_NAME_PREFIX='[No Existing Container] '

function setup_file() {
  # Fail early if the testing image is already running:
  assert_not_equal "$(docker ps | grep -o "${IMAGE_NAME}")" "${IMAGE_NAME}"

  # Copy the base config that `setup.sh` will volume mount to a container it runs:
  export TEST_TMP_CONFIG
  TEST_TMP_CONFIG=$(_duplicate_config_for_container . 'no_container')
}

@test "'setup.sh -p <PATH> -i <IMAGE>' should correctly use options" {
  # Create a `postfix-virtual.cf` config to verify the container can access it:
  local MAIL_ALIAS='no_container@example.test no_container@forward.test'
  echo "${MAIL_ALIAS}" > "${TEST_TMP_CONFIG}/postfix-virtual.cf"

  # Should run the testing image with a volume mount to the provided path:
  run ./setup.sh -p "${TEST_TMP_CONFIG}" -i "${IMAGE_NAME}" alias list
  assert_success
  assert_output --partial "* ${MAIL_ALIAS}"
}
