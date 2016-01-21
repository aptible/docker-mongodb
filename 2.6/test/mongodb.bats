#!/usr/bin/env bats

@test "It should install mongod " {
  run mongod --version
  [[ "$output" =~ "db version v2.6.11"  ]]
}

@test "It should install mongod to /usr/bin/mongod" {
  test -x /usr/bin/mongod
}
