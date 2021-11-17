#!/usr/bin/env bats

source "${BATS_TEST_DIRNAME}/test_helpers.sh"

version='5.0.3'

@test "It should install mongod ${version}" {
  run mongod --version
  [[ "$output" =~ "db version v${version}"  ]]
}
