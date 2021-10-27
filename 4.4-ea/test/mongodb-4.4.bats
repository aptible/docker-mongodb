#!/usr/bin/env bats

source "${BATS_TEST_DIRNAME}/test_helpers.sh"

version='4.4.10'

@test "It should install mongod ${version}" {
  run mongod --version
  [[ "$output" =~ "db version v${version}"  ]]
}
