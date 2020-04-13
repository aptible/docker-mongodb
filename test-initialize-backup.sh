#!/bin/bash
set -o errexit
set -o nounset

. ./test-helpers.sh

IMG="$1"

MONGO_CONTAINER="mongo"
MONGO_PORT=27117
MONGO_DATA="${MONGO_CONTAINER}-data"

MONGO_FIRST_NAME="mongo-first"
MONGO_FIRST_IP=172.18.0.21
MONGO_FIRST_URL="mongo://user:pass@${MONGO_FIRST_NAME}:${MONGO_PORT}/db?ssl=true&x-sslVerify=false"

MONGO_SECOND_NAME="mongo-second"
MONGO_SECOND_IP=172.18.0.22
MONGO_SECOND_URL="mongo://user:pass@${MONGO_SECOND_NAME}:${MONGO_PORT}/db?ssl=true&x-sslVerify=false"

MONGO_NET="mongonet"

# NOTE: It's important not to set the --hostname here, to properly reflect how this on Enclave.
SHARED_RUN_OPTS=(
  "-e" "EXPOSE_PORT_27017=${MONGO_PORT}"
  "-e" "PORT=${MONGO_PORT}"
  "--volumes-from" "$MONGO_DATA"
  "-e" "INITIALIZATION_ALLOW_INVALID_CERTIFICATES=1"
)

FIRST_RUN_NET_OPTS=(
  "--net" "$MONGO_NET"
  "--add-host" "${MONGO_FIRST_NAME}:${MONGO_FIRST_IP}"
)

FIRST_RUN_OPTS=(
  "${SHARED_RUN_OPTS[@]}"
  "${FIRST_RUN_NET_OPTS[@]}"
  "--ip" "$MONGO_FIRST_IP"
  "-e" "EXPOSE_HOST=${MONGO_FIRST_NAME}"
)

SECOND_RUN_NET_OPTS=(
  "--net" "$MONGO_NET"
  "--add-host" "${MONGO_SECOND_NAME}:${MONGO_SECOND_IP}"
)

SECOND_RUN_OPTS=(
  "${SHARED_RUN_OPTS[@]}"
  "${SECOND_RUN_NET_OPTS[@]}"
  "--ip" "$MONGO_SECOND_IP"
  "-e" "EXPOSE_HOST=${MONGO_SECOND_NAME}"
)

INIT_EXTRA_OPTS=(
  "-e" "USERNAME=user"
  "-e" "PASSPHRASE=pass"
  "-e" "DATABASE=db"
)

function cleanup {
  echo "Cleaning up"
  docker rm -f "$MONGO_CONTAINER" "$MONGO_DATA" || true
  docker network rm "$MONGO_NET" || true
}

trap cleanup EXIT
quietly cleanup

echo "Creating network"
quietly docker network create --subnet=172.18.0.0/16 "$MONGO_NET"

echo "Creating data container"
docker create --name "$MONGO_DATA" "$IMG"

echo "Initialize DB"
quietly docker run -it --rm \
  "${FIRST_RUN_OPTS[@]}" \
  "${INIT_EXTRA_OPTS[@]}" \
  "$IMG" --initialize

echo "Start DB"
quietly docker run -d --name="$MONGO_CONTAINER" \
  "${FIRST_RUN_OPTS[@]}" \
  "$IMG"

echo "Wait for DB to transition to PRIMARY"
until docker run --rm -i "${FIRST_RUN_NET_OPTS[@]}" "$IMG" --client "$MONGO_FIRST_URL" --quiet --eval 'quit(db.isMaster()["ismaster"] ? 0 : 1)'; do sleep 2; done

echo "Insert data"
docker run --rm -i "${FIRST_RUN_NET_OPTS[@]}" "$IMG" --client "$MONGO_FIRST_URL" \
  --quiet --eval "db.test.insert({ 'FOO': 'CANARY' }, { w: 1, j: true});"

echo "Stop DB"
docker stop -t 20 "$MONGO_CONTAINER"
docker rm "$MONGO_CONTAINER"

echo "Initialize restore"
quietly docker run -it --rm \
  "${SECOND_RUN_OPTS[@]}" \
  "${INIT_EXTRA_OPTS[@]}" \
  "$IMG" --initialize-backup 

echo "Start DB after restore"
quietly docker run -d --name="$MONGO_CONTAINER" \
  "${SECOND_RUN_OPTS[@]}" \
  --volumes-from "$MONGO_DATA" \
  "$IMG"

echo "Wait for DB to transition to PRIMARY after restore"
until docker run --rm -i "${SECOND_RUN_NET_OPTS[@]}" "$IMG" --client "$MONGO_SECOND_URL" --quiet --eval 'quit(db.isMaster()["ismaster"] ? 0 : 1)'; do sleep 2; done

echo "Check data is preserved"
docker run --rm -i "${SECOND_RUN_NET_OPTS[@]}" "$IMG" --client "$MONGO_SECOND_URL" \
  --quiet --eval "printjson(db.test.find()[0])"  | grep CANARY

echo "TEST OK"
