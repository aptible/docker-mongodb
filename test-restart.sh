#!/bin/bash
set -o errexit
set -o nounset

. ./test-helpers.sh

function _wait_for_mongo_exec {
  local container="$1"
  local command="$2"

  local mongo_args=(
    "--ssl" "--sslAllowInvalidCertificates"
    "--quiet"
    "--eval" "$command"
  )

  for _ in $(seq 1 1000); do
    if docker exec -it "$container" mongo "${mongo_args[@]}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.1
  done

  return 1;
}

function wait_for_mongo {
  local container="$1"

  if _wait_for_mongo_exec "$container" "quit(0)"; then
    return 0
  fi

  echo "DB never came online"
  docker logs "$container"
  return 1
}

IMG="$1"

MONGO_CONTAINER="mongo"
DATA_CONTAINER="${MONGO_CONTAINER}-data"

function cleanup {
  echo "Cleaning up"
  docker rm -f "$MONGO_CONTAINER" "$DATA_CONTAINER" >/dev/null 2>&1 || true
}

trap cleanup EXIT
quietly cleanup

echo "Creating data container"
docker create --name "$DATA_CONTAINER" "$IMG"

echo "Starting DB"
quietly docker run -it --rm \
  -e USERNAME=user -e PASSPHRASE=pass -e DATABASE=db \
  -e INITIALIZATION_ALLOW_INVALID_CERTIFICATES=1 \
  -e EXPOSE_HOST=127.0.0.1 -e EXPOSE_PORT_27217=27217 \
  --volumes-from "$DATA_CONTAINER" \
  "$IMG" --initialize

quietly docker run -d --name="$MONGO_CONTAINER" \
  -e EXPOSE_HOST=127.0.0.1 -e EXPOSE_PORT_27217=27217 \
  --volumes-from "$DATA_CONTAINER" \
  "$IMG"

echo "Waiting for DB to come online"
wait_for_mongo "$MONGO_CONTAINER"

echo "Verifying DB shutdown message isn't present"
docker logs "$MONGO_CONTAINER" 2>&1 | grep -vqiE "dbexit.*(rc: 0|really exit)"
docker logs "$MONGO_CONTAINER" 2>&1 | grep -vqiE "(this node is.*in the config|replSet I am)"

echo "Restarting DB container"
date
docker top "$MONGO_CONTAINER"
docker restart -t 20 "$MONGO_CONTAINER"

echo "Waiting for DB to come back online"
wait_for_mongo "$MONGO_CONTAINER"

echo "DB came back online; checking for clean shutdown and recovery"
date
docker logs "$MONGO_CONTAINER" 2>&1 | grep -qiE "(dbexit.*(rc: 0|really exit))|(shutting down with code:0)"
docker logs "$MONGO_CONTAINER" 2>&1 | grep -qiE "(this node is.*in the config|replSet I am)"
docker logs "$MONGO_CONTAINER" 2>&1 | grep -vqiE "(recovering data from the last clean checkpoint|recover done)"

echo "Attempting unclean shutdown"
docker kill -s KILL "$MONGO_CONTAINER"
docker start "$MONGO_CONTAINER"

echo "Waiting for DB to come back online"
wait_for_mongo "$MONGO_CONTAINER"
docker logs "$MONGO_CONTAINER" 2>&1 | grep -qiE "(recovering data from the last clean checkpoint|recover done)"
