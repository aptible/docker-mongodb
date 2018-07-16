#!/usr/bin/env bats

source "${BATS_TEST_DIRNAME}/test_helpers.sh"


local_s_client() {
  openssl s_client -connect localhost:27017 "$@" < /dev/null
}

@test "It should allow connections using TLS1.2" {
  start_mongodb

  local_s_client -tls1_2
}

@test "It should allow connections using TLS1.1" {
  start_mongodb

  local_s_client -tls1_1
}

@test "MongoDB <4.0 should allow connections using TLS1.0" {
  if dpkg --compare-versions "$MONGO_VERSION" ge 4; then
    skip "MongoDB "$MONGO_VERSION" does not support TLS1.0"
  fi

  start_mongodb

  local_s_client -tls1
}

@test "MongoDB >=4.0 should disallow connections using TLS1.0" {
  if dpkg --compare-versions "$MONGO_VERSION" lt 4; then
    skip "MongoDB "$MONGO_VERSION" does support TLS1.0"
  fi

  start_mongodb

  ! local_s_client -tls1
}


@test "It should disallow connections using SSLv3" {
  start_mongodb

  ! local_s_client -ssl3
}