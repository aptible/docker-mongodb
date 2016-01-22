#!/usr/bin/env bats
setup() {
  export OLD_DATA_DIRECTORY="$DATA_DIRECTORY"
  export OLD_SSL_DIRECTORY="$SSL_DIRECTORY"
  export DATA_DIRECTORY=/tmp/datadir
  export SSL_DIRECTORY=/tmp/ssldir
  export QUERY="JSON.stringify(db.getCollectionNames())"
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
  [[ "$output" =~ "db version v2.6.11"  ]]
}

@test "It should install mongo tools to /usr/local/bin" {
  test -x /usr/local/bin/mongod
  test -x /usr/local/bin/mongo
  test -x /usr/local/bin/mongorestore
  test -x /usr/local/bin/mongodump
}

@test "It should accept non-SSL connections" {
  USERNAME=aptible PASSPHRASE=password run-database.sh --initialize
  wait_for_mongodb
  run mongo --username aptible --password password db --eval "$QUERY"
  [ "$status" -eq "0" ]
  [[ "$output" =~ "[]" ]]
}

@test "It should accept SSL connections" {
  USERNAME=aptible PASSPHRASE=password run-database.sh --initialize
  wait_for_mongodb
  run mongo --ssl --sslAllowInvalidCertificates --username aptible --password password db --eval "$QUERY"
  [ "$status" -eq "0" ]
  [[ "$output" =~ "[]" ]]
}
