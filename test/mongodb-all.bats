#!/usr/bin/env bats

source "${BATS_TEST_DIRNAME}/test_helpers.sh"

@test "It should accept SSL connections" {
  initialize_mongodb
  wait_for_mongodb
  run run-database.sh --client "$DATABASE_URL" --eval "$QUERY"
  [ "$status" -eq "0" ]
  [[ "$output" =~ "[ ]" ]]
}

@test "It should successfully backup and restore" {
  test_data="APTIBLE_TEST"

  start_mongodb

  wait_for_master "$DATABASE_URL"
  run-database.sh --client "$DATABASE_URL" --eval "db.test.insert({\"$test_data\": null})"

  run-database.sh --dump "$DATABASE_URL" > "$BATS_TEST_DIRNAME/backup"

  run-database.sh --client "$DATABASE_URL" --eval "db.dropDatabase()"
  run-database.sh --restore "$DATABASE_URL" < "$BATS_TEST_DIRNAME/backup"

  run run-database.sh --client "$DATABASE_URL" --eval "printjson(db.test.find()[0])"
  [ "$status" -eq "0" ]
  [[ "$output" =~ "$test_data" ]]
}

@test "It should pass parse_mongo_url.py unit tests" {
  python -B -m doctest /usr/bin/parse_mongo_url.py
}

@test "It should return valid JSON for --discover and --connection-url" {
  run-database.sh --discover | python -c 'import sys, json; json.load(sys.stdin)'
  CLUSTER_KEY=test PASSPHRASE=test run-database.sh --connection-url | python -c 'import sys, json; json.load(sys.stdin)'
}

@test "It should return a valid connection URL for --connection-url" {
  start_mongodb

  USERNAME="$DATABASE_USER" PASSPHRASE="$DATABASE_PASSWORD" DATABASE=db run run-database.sh --connection-url
  [ "$status" -eq "0" ]
  URL="$(echo "$output" | python -c "import sys, json; print json.load(sys.stdin)['url']")"
  URL="${URL}&x-sslVerify=false"  # Certs are invalid in test, but --connection-url doesn't know that.
  run-database.sh --client "$URL" --eval 'quit(0);'
}

@test "It should allow --initialize without CLUSTER_KEY" {
  USERNAME="$DATABASE_USER" PASSPHRASE="$DATABASE_PASSWORD" DATABASE=db run run-database.sh --initialize
  [ "$status" -eq 0 ]
  echo "$output" | grep "WARNING: CLUSTER_KEY is unset"
}

@test "It should not allow --initialize-from without CLUSTER_KEY" {
  USERNAME="$DATABASE_USER" PASSPHRASE="$DATABASE_PASSWORD" DATABASE=db run run-database.sh --initialize-from "mongodb://dummy:dummy@dummy@dummy/dummy"
  [ "$status" -eq 1 ]
  echo "$output" | grep "CLUSTER_KEY must be set"
}

@test "It should start standalone without a key file" {
  wait_for_mongodb
  grep "STANDALONE" "$BATS_TEST_DIRNAME/mongodb.log"
}

@test "It should start standalone without a replica set name file" {
  wait_for_mongodb
  grep "STANDALONE" "$BATS_TEST_DIRNAME/mongodb.log"
}

@test "It should reuse existing ssl cert / key files" {
  initialize_mongodb
  make_certs "TESTMONGODB"
  wait_for_mongodb

  grep "Certs present on filesystem" "$BATS_TEST_DIRNAME/mongodb.log"
  # Curl isn't exactly the right tool to talk to MongoDB, but it works
  # well and predictably (whereas openssl s_client refuses to close the
  # connection and hangs).
  curl -kv https://localhost:27017 2>&1 | grep "TESTMONGODB"
}

@test "It should prioritize ssl cert / key files from the environment" {
  initialize_mongodb

  make_certs "TESTMONGODB"
  export SSL_CERTIFICATE="$(cat "${SSL_DIRECTORY}/mongodb.crt")"
  export SSL_KEY="$(cat "${SSL_DIRECTORY}/mongodb.key")"
  rm "${SSL_DIRECTORY}/mongodb.key" "${SSL_DIRECTORY}/mongodb.crt"

  make_certs "WRONGMONGODB"
  wait_for_mongodb

  grep "Certs present in environment" "$BATS_TEST_DIRNAME/mongodb.log"
  curl -kv https://localhost:27017 2>&1 | grep "TESTMONGODB"
}

@test "It should auto-generate certs when none are provided" {
  initialize_mongodb
  rm "${SSL_DIRECTORY}/mongodb.key" "${SSL_DIRECTORY}/mongodb.crt"
  wait_for_mongodb
  grep "No certs found" "$BATS_TEST_DIRNAME/mongodb.log"
  curl -kv https://localhost:27017 2>&1 | grep "mongodb.example.com"
}

@test "It should read or generate certs as part of --initialize" {
  initialize_mongodb
  [ -f "${SSL_DIRECTORY}/mongodb.crt" ]
  [ -f "${SSL_DIRECTORY}/mongodb.key" ]
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

@test "It should autotune for a 512MB container" {
  initialize_mongodb
  APTIBLE_CONTAINER_SIZE=512 wait_for_mongodb
  run-database.sh --client "$ADMIN_DATABASE_URL" --eval "$PRINT_RAM_QUERY" | grep 256
}

@test "It should autotune for a 1GB container" {
  initialize_mongodb
  APTIBLE_CONTAINER_SIZE=1024 wait_for_mongodb
  run-database.sh --client "$ADMIN_DATABASE_URL" --eval "$PRINT_RAM_QUERY" | grep 512
}

@test "It should autotune for a 2GB container" {
  initialize_mongodb
  APTIBLE_CONTAINER_SIZE=2048 wait_for_mongodb
  run-database.sh --client "$ADMIN_DATABASE_URL" --eval "$PRINT_RAM_QUERY" | grep 1024
}

@test "It should use an appropirately licensed version of MongoDB" {

  if [[ "$TAG" =~ .*-ea ]]; then
    start_mongodb
    grep "modules: enterprise" $BATS_TEST_DIRNAME/mongodb.log
  else
    start_mongodb
    grep "modules: none" $BATS_TEST_DIRNAME/mongodb.log
    ! zgrep "Server Side Public License" /usr/share/doc/mongodb-org-server/LICENSE-Community.txt.gz
    [[ -f /usr/share/doc/mongodb-org-server/GNU-AGPL-3.0.gz ]]
  fi
}
