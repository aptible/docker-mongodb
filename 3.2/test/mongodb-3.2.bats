#!/usr/bin/env bats

source "${BATS_TEST_DIRNAME}/test_helpers.sh"

@test "It should install mongod 3.2.21" {
  run mongod --version
  [[ "$output" =~ "db version v3.2.21"  ]]
}

@test "It should install mongo tools to /usr/bin" {
  test -x /usr/bin/mongod
  test -x /usr/bin/mongo
  test -x /usr/bin/mongorestore
  test -x /usr/bin/mongodump
}

@test "It should reject non-SSL connections" {
  start_mongodb
  run run-database.sh --client "$DATABASE_URL_NO_SSL" --eval "$QUERY"
  [ "$status" -ne "0" ]
}

@test "It should autotune for a 2GB container" {
  initialize_mongodb
  APTIBLE_CONTAINER_SIZE=2048 wait_for_mongodb
  run-database.sh --client "$ADMIN_DATABASE_URL" --eval "$PRINT_RAM_QUERY" | grep 1024
}

@test "It should autotune for a 4GB container" {
  initialize_mongodb
  APTIBLE_CONTAINER_SIZE=4096 wait_for_mongodb
  run-database.sh --client "$ADMIN_DATABASE_URL" --eval "$PRINT_RAM_QUERY" | grep 2048
}
