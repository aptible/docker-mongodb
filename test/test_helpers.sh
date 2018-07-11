#!/bin/bash

setup() {
  export OLD_DATA_DIRECTORY="$DATA_DIRECTORY"
  export OLD_SSL_DIRECTORY="$SSL_DIRECTORY"
  export DATA_DIRECTORY=/tmp/datadir
  export SSL_DIRECTORY=/tmp/ssldir
  export QUERY="rs.slaveOk(); printjson(db.getCollectionNames())"
  export DATABASE_USER="aptible"
  export DATABASE_PASSWORD="password12345"
  export DATABASE_CLUSTER_KEY="key1234"
  export DATABASE_URL_NO_SSL="mongodb://$DATABASE_USER:$DATABASE_PASSWORD@localhost/db"
  export DATABASE_URL="$DATABASE_URL_NO_SSL?ssl=true&x-sslVerify=false"
  export ADMIN_DATABASE_URL="mongodb://$DATABASE_USER:$DATABASE_PASSWORD@localhost/admin?ssl=true&x-sslVerify=false"
  export PRINT_RAM_QUERY="print(db.serverStatus()['wiredTiger']['cache']['maximum bytes configured'] / 1024 / 1024)"
  export INITIALIZATION_ALLOW_INVALID_CERTIFICATES=1
  rm -rf "$DATA_DIRECTORY"
  rm -rf "$SSL_DIRECTORY"
  mkdir -p "$DATA_DIRECTORY"
  mkdir -p "$SSL_DIRECTORY"
}

teardown() {
  # Dump log, if any (facilitates troubleshooting)
  cat "$BATS_TEST_DIRNAME/mongodb.log" || true
  # Actually teardown
  rm -rf "$DATA_DIRECTORY"
  rm -rf "$SSL_DIRECTORY"
  export DATA_DIRECTORY="$OLD_DATA_DIRECTORY"
  export SSL_DIRECTORY="$OLD_SSL_DIRECTORY"
  unset OLD_DATA_DIRECTORY
  unset OLD_SSL_DIRECTORY
  unset QUERY
  unset DATABASE_USER
  unset DATABASE_PASSWORD
  unset DATABASE_CLUSTER_KEY
  unset DATABASE_URL
  PID=$(pgrep mongod) || return 0
  run pkill mongod
  while [ -n "$PID" ] && [ -e "/proc/${PID}" ]; do sleep 0.1; done
}

initialize_mongodb() {
  USERNAME="$DATABASE_USER" CLUSTER_KEY="$DATABASE_CLUSTER_KEY" PASSPHRASE="$DATABASE_PASSWORD" DATABASE=db run-database.sh --initialize
}

wait_for_mongodb() {
  run-database.sh > "$BATS_TEST_DIRNAME/mongodb.log" &

  # Try to connect as "DATABASE_USER" or without user (depending on how we started)
  for i in $(seq 10 -1 0); do
    if mongo --ssl --sslAllowInvalidCertificates -u "$DATABASE_USER" -p "$DATABASE_PASSWORD" db  --eval 'quit(0)'; then
      break
    fi

    if mongo db --ssl --sslAllowInvalidCertificates --eval 'quit(0)'; then
      break
    fi

    if [ "$i" -eq 0 ]; then
      echo "MongoDB never came online"
      false
    fi

    echo "Waiting until MongoDB comes online"
    sleep 2
  done
}

start_mongodb() {
  initialize_mongodb
  wait_for_mongodb
}

wait_for_master() {
  local database_url="$1"
  for i in $(seq 10 -1 0); do
    if run-database.sh --client "$database_url" --eval 'quit(db.isMaster()["ismaster"] ? 0 : 1)'; then
      break
    fi
    echo "Waiting until MongoDB becomes master"
    sleep 2
  done
}

make_certs () {
  local name="$1"
  SUBJ="/C=US/ST=New York/L=New York/O=Example/CN=${name}"
  openssl req -nodes -new -x509 -sha256 -subj "$SUBJ" \
    -keyout "${SSL_DIRECTORY}/mongodb.key" \
    -out "${SSL_DIRECTORY}/mongodb.crt"
}
