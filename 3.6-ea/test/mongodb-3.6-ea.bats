#!/usr/bin/env bats

source "${BATS_TEST_DIRNAME}/test_helpers.sh"

@test "It should install mongod 3.6.17" {
  run mongod --version
  [[ "$output" =~ "db version v3.6.17"  ]]
}
