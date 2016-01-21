#!/usr/bin/env bats

setup() {
  export OLD_DATA_DIRECTORY="$DATA_DIRECTORY"
  export OLD_SSL_DIRECTORY="$SSL_DIRECTORY"
  export DATA_DIRECTORY=/tmp/datadir
  export SSL_DIRECTORY=/tmp/ssldir
  export QUERY="db.getCollectionNames()"
  rm -rf "$DATA_DIRECTORY"
  rm -rf "$SSL_DIRECTORY"
  mkdir -p "$DATA_DIRECTORY"
  mkdir -p "$SSL_DIRECTORY"
}

teardown() {
  export DATA_DIRECTORY="$OLD_DATA_DIRECTORY"
  export SSL_DIRECTORY="$OLD_SSL_DIRECTORY"
  unset OLD_DATA_DIRECTORY
  unset OLD_SSL_DIRECTORY
  PID=$(pgrep mongod) || return 0
  run pkill mongod
  while [ -n "$PID" ] && [ -e /proc/$PID ]; do sleep 0.1; done
}

wait_for_mongodb() {
  run-database.sh > $BATS_TEST_DIRNAME/mongodb.log &
  while  ! grep "waiting for connections" $BATS_TEST_DIRNAME/mongodb.log ; do sleep 0.1; done
}

@test "It should install mongod " {
  run mongod --version
  [[ "$output" =~ "db version v3.2.1"  ]]
}

@test "It should install mongod to /usr/bin/mongod" {
  test -x /usr/bin/mongod
}

@test "It should reject non-SSL connections" {
  USERNAME=aptible PASSPHRASE=password run-database.sh --initialize
  wait_for_mongodb
  run mongo --username aptible --password password db --eval "$QUERY"
  [ "$status" -ne "0" ]
}

@test "It should accept SSL connections" {
  USERNAME=aptible PASSPHRASE=password run-database.sh --initialize
  wait_for_mongodb
  run mongo --ssl --sslAllowInvalidCertificates --username aptible --password password db --eval "$QUERY"
  [ "$status" -eq "0" ]
  [[ "$output" =~ "[ ]" ]]
}
