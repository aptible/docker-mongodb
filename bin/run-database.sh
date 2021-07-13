#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail


# shellcheck disable=SC1091
. /usr/bin/utilities.sh


DEFAULT_USER="aptible"
DEFAULT_HOST="$(hostname)"
DEFAULT_PORT="27017"
DEFAULT_DATABASE="db"


REPL_SET_NAME_FILE="${DATA_DIRECTORY}/.aptible-replica-set-name"
CLUSTER_KEY_FILE="${DATA_DIRECTORY}/.aptible-keyfile"
MEMBER_ID_FILE="${DATA_DIRECTORY}/.aptible-member-id"
PRE_START_FILE="${DATA_DIRECTORY}/.aptible-on-start"

SSL_BUNDLE_FILE="${SSL_DIRECTORY}/mongodb.pem"

function mongo_init_debug () {
  # shellcheck disable=2086
  if [[ -n "${ENABLE_DEBUG:-""}" ]]; then
    set -o xtrace
  fi
}


function mongo_environment_minimal () {
  # shellcheck disable=2086
  {
    : ${SSL_CERTIFICATE:=""}
    : ${SSL_KEY:=""}
    : ${PORT:="$DEFAULT_PORT"}
  }
}


function mongo_environment_full () {
  mongo_environment_minimal

  # Database defaults

  # shellcheck disable=2086
  {
    : ${USERNAME:="$DEFAULT_USER"}
    : ${DATABASE:="$DEFAULT_DATABASE"}
  }

  # Clustering defaults

  EXPOSE_PORT_PTR="EXPOSE_PORT_${PORT}"
  # shellcheck disable=2086
  {
    : ${EXPOSE_HOST:="$DEFAULT_HOST"}
  }

  # Set !EXPOSE_PORT_PTR to a default value of PORT if unset. We can't
  # use ${!EXPOSE_PORT_PTR:=""} because it doesn't work for indirect
  # references.
  local canary="VAR_NOT_SET"
  if [[ "${!EXPOSE_PORT_PTR:-"$canary"}" = "$canary" ]]; then
    eval "${EXPOSE_PORT_PTR}=${PORT}"
  fi

  # Check that PASSPHRASE, which does not support defaults, is set up.
  # shellcheck disable=2086
  {
    : ${PASSPHRASE:?"PASSPHRASE must be set in the environment"}
  }
}

function mongo_environment_prefer_cluster_key () {
  # For compatibility with environments where `--discover` isn't supported,
  # we auto-generate a CLUSTER_KEY at startup, but warn that it'll need to
  # be copied out of this instance.

  if [[ "${CLUSTER_KEY:=""}" = "" ]]; then
    echo "****************************************************************************"
    echo
    echo "WARNING: CLUSTER_KEY is unset. A new random one will be generated."
    echo
    echo "If you intended to form a new cluster around this MongoDB instance, you"
    echo "will need to retrieve the key and ensure it is set in the environment"
    echo "for new instances you provision. Clustering will **NOT** work otherwise."
    echo
    echo "The generated CLUSTER_KEY will be found in ${CLUSTER_KEY_FILE} after"
    echo "initialization completes."
    echo
    echo "****************************************************************************"
    CLUSTER_KEY="$(pwgen -s 64)"
  fi
}


function mongo_environment_require_cluster_key () {
  # When using --initialize-from, we *need* the CLUSTER_KEY: there's no
  # use attempting to join a replica set we don't have the credentials ot
  # participate in.

  # shellcheck disable=2086
  : ${CLUSTER_KEY:?"CLUSTER_KEY must be set in the environment"}
}



function mongo_initialize_certs () {
  local ssl_cert_file="${SSL_DIRECTORY}/mongodb.crt"
  local ssl_key_file="${SSL_DIRECTORY}/mongodb.key"
  mkdir -p "$SSL_DIRECTORY"

  if [ -n "$SSL_CERTIFICATE" ] && [ -n "$SSL_KEY" ]; then
    echo "Certs present in environment - using them"
    echo "$SSL_CERTIFICATE" > "$ssl_cert_file"
    echo "$SSL_KEY" > "$ssl_key_file"
  elif [ -f "$ssl_cert_file" ] && [ -f "$ssl_key_file" ]; then
    echo "Certs present on filesystem - using them"
  else
    echo "No certs found - autogenerating"
    SUBJ="/C=US/ST=New York/L=New York/O=Example/CN=mongodb.example.com"
    OPTS="req -nodes -new -x509 -sha256"
    # shellcheck disable=2086
    openssl $OPTS -subj "$SUBJ" -keyout "$ssl_key_file" -out "$ssl_cert_file" 2> /dev/null
  fi

  cat "$ssl_key_file" "$ssl_cert_file" > "$SSL_BUNDLE_FILE"
}


function mongo_exec_and_extract () {
  # Unfortunately, MongoDB insists on logging SSL verification errors to stdout, which means
  # we can't simply capture the output of our script. Instead, we need our script to prefix
  # the data we're interested in, and then check that prefix.
  local script="$1"
  shift
  local prefix="MONGO_EXTRACT_PREFIX:"
  local mongo_out

  # Execute the command (or script), but send in our prefix so the command / script
  # knows what to prefix its output with so we can find it.
  if ! mongo_out="$(mongo "$@" --eval "var extract_prefix = '$prefix';" "$script")"; then
    # Oops, something failed. Log the output to stderr and exit.
    echo -n "$mongo_out" > 2
    false
  fi

  # Then do some grep & sed to extract what we actually wanted...
  if ! echo "$mongo_out" | grep "$prefix" | sed "s/${prefix}//"; then
    # Oops, the output didn't have the data we were interested in. Here again,
    # log the output and exit.
    echo -n "$mongo_out" > 2
    false
  fi
}


function mongo_exec_foreground_exposed () {
  # Run the "PRE_START_FILE" if provided
  if [ -f "$PRE_START_FILE" ]; then
    "$PRE_START_FILE"
  fi

  # Standalone configuration
  local mongod_options=(
    "--dbpath" "$DATA_DIRECTORY"
    "--bind_ip" "0.0.0.0"
    "--port" "$PORT"
    "--sslMode" "requireSSL"
    "--sslPEMKeyFile" "$SSL_BUNDLE_FILE"
    "--auth"
  )

  # Add autotune configuration
  mongod_options+=(
    $(/usr/local/bin/autotune)
  )

  if [ -f "$REPL_SET_NAME_FILE" ] && [ -f "$CLUSTER_KEY_FILE" ]; then
    # We have replica set configuration! Start with replica set options.
    mongod_options+=(
      "--replSet" "$(cat "$REPL_SET_NAME_FILE")"
      "--keyFile" "$CLUSTER_KEY_FILE"
    )
  else
    echo "WARNING: Starting in STANDALONE mode (${REPL_SET_NAME_FILE} or ${CLUSTER_KEY_FILE} is missing)."
  fi

  unset SSL_CERTIFICATE
  unset SSL_KEY
  exec mongod "${mongod_options[@]}"
}

function mongo_exposed_connection_options {
  local opts=(
    "--host" "$EXPOSE_HOST"
    "--port" "${!EXPOSE_PORT_PTR}"
    "--username" "$USERNAME"
    "--password" "$PASSPHRASE"
    "--authenticationDatabase" "admin"
    "--ssl"
  )

  if [[ -n "${INITIALIZATION_ALLOW_INVALID_CERTIFICATES:-}" ]]; then
    opts+=("--sslAllowInvalidCertificates")
  fi

  echo "${opts[@]}"
}

function mongo_wait {
  for _ in $(seq 1 30); do
    if mongo "$@" --quiet --eval 'quit(0)'; then
      return 0
    fi

    sleep 2
  done

  return 1
}

function mongo_wait_local {
  mongo_wait --port "$PORT"
}

function mongo_wait_exposed {
  # shellcheck disable=SC2046
  mongo_wait $(mongo_exposed_connection_options)
}

function mongo_start_background_local () {
  local pidPath="$1"
  local logPath="$2"

  mongod \
    --dbpath "$DATA_DIRECTORY" \
    --bind_ip "127.0.0.1" \
    --port "$PORT" \
    --fork \
    --logpath "$logPath" \
    --pidfilepath "$pidPath"

  mongo_wait_local
}

function mongo_start_background_exposed () {
  local pidPath="$1"
  local logPath="$2"
  local replSet="$3"

  mongod \
    --dbpath "$DATA_DIRECTORY" \
    --bind_ip "0.0.0.0" \
    --port "$PORT" \
    --fork \
    --logpath "$logPath" \
    --pidfilepath "$pidPath" \
    --replSet "$replSet" \
    --auth \
    --sslMode "requireSSL" \
    --sslPEMKeyFile "$SSL_BUNDLE_FILE"

  mongo_wait_exposed
}

function mongo_shutdown_background () {
  local pidPath="$1"

  # Terminate MongoDB and wait for it to exit
  kill "$(cat "$pidPath")"
  while [ -s "${DATA_DIRECTORY}/mongod.lock" ]; do sleep 0.1; done

  # This above does not always ensure Mongo has fully exited, and we see this error at times:
  # [initandlisten] Failed to set up listener: SocketException: Address already in use
  sleep 3
}

dump_directory="mongodump"

# If requested, enable debug before anything.
mongo_init_debug

if [[ "$#" -eq 0 ]]; then
  mongo_environment_minimal
  mongo_initialize_certs
  mongo_exec_foreground_exposed

elif [[ "$1" == "--initialize" ]]; then
  mongo_environment_full
  mongo_initialize_certs
  mongo_environment_prefer_cluster_key

  # Auto-generate replica set name. We randomize this to ensure multiple MongoDB servers have a different
  # replica set name (as recommended by MongoDB).
  REPL_SET_NAME="rs$(pwgen -s 12)"
  echo "$REPL_SET_NAME" > "$REPL_SET_NAME_FILE"

  # Store the CLUSTER_KEY in a file. There are several reasons why we put it there rather than rely
  # on the environment:
  # + It works with a more limited environment.
  # + The data contains the replica set configuration, which contains other members, to which we
  #   need this key to connect anyway (IOW, the data isn't as useful without the key).
  echo "$CLUSTER_KEY" > "$CLUSTER_KEY_FILE"
  chmod 600 "$CLUSTER_KEY_FILE"

  # Initialize MongoDB
  PID_PATH_STAGE_1=/tmp/mongod-1.pid
  LOG_PATH_STAGE_1=/tmp/mongod-1.log

  PID_PATH_STAGE_2=/tmp/mongod-2.pid
  LOG_PATH_STAGE_2=/tmp/mongod-2.log

  trap 'cat "$LOG_PATH_STAGE_1" "$LOG_PATH_STAGE_2"; rm "$LOG_PATH_STAGE_1" "$LOG_PATH_STAGE_2" "$PID_PATH_STAGE_1" "$PID_PATH_STAGE_2"' EXIT

  mongo_start_background_local \
    "$PID_PATH_STAGE_1" \
    "$LOG_PATH_STAGE_1"

  # Create users using the connection URL that was provided
  mongo --port "$PORT" \
    --eval "var user_db = '${DATABASE}', user_name = '${USERNAME}', user_passphrase = '${PASSPHRASE}';" \
    "/mongo-scripts/primary-add-user-permissions.js"

  mongo_shutdown_background "$PID_PATH_STAGE_1"

  # Reboot MongoDB, this time with auth, replica set configuration, and
  # listening on all interfaces.
  mongo_start_background_exposed \
    "$PID_PATH_STAGE_2" \
    "$LOG_PATH_STAGE_2" \
    "$REPL_SET_NAME"

  mongo_options=($(mongo_exposed_connection_options))

  # Initialize replica set configuration using the host we were provided. Since we're using --initialize,
  # we'll force the host _id to 0 (we're guaranteed that --initialize only runs once per replica set).
  mongo "${mongo_options[@]}" \
    --eval "var replica_set_name = '${REPL_SET_NAME}', primary_member_id = 0, primary_host = '${EXPOSE_HOST}:${!EXPOSE_PORT_PTR}';" \
    "/mongo-scripts/primary-initiate-replica-set.js"

  # Wait until MongoDB node becomes primary
  until mongo "${mongo_options[@]}" --quiet --eval 'quit(db.isMaster()["ismaster"] ? 0 : 1)'; do
    echo "Waiting until new MongoDB instance becomes primary"
    sleep 2
  done

  mongo_shutdown_background "$PID_PATH_STAGE_2"

elif [[ "$1" == "--initialize-backup" ]]; then
  # No need to initialize replica set on a backup from a standalone database
  if [[ ! -f "$REPL_SET_NAME_FILE" ]]; then
    exit 0
  fi

  # There will be no --discover when restoring, so we expect our environment to be pre-configured.
  mongo_environment_full
  mongo_initialize_certs
  mongo_environment_prefer_cluster_key

  # Store the CLUSTER_KEY on disk. It may not have changed during the restore,
  # but there is no reason not to support it. In fact, we would probably want
  # to run some re-discovery process as part of the restore to update these
  # things.
  echo "$CLUSTER_KEY" > "$CLUSTER_KEY_FILE"
  chmod 600 "$CLUSTER_KEY_FILE"

  # Generate a new replica set name
  REPL_SET_NAME="rs$(pwgen -s 12)"
  echo "$REPL_SET_NAME" > "$REPL_SET_NAME_FILE"

  # First, we're going to boot MongoDB without a replSet ID and purge the
  # configuration
  PID_PATH_STAGE_1=/tmp/mongod-1.pid
  LOG_PATH_STAGE_1=/tmp/mongod-1.log

  PID_PATH_STAGE_2=/tmp/mongod-2.pid
  LOG_PATH_STAGE_2=/tmp/mongod-2.log

  trap 'cat "$LOG_PATH_STAGE_1" "$LOG_PATH_STAGE_2"; rm "$LOG_PATH_STAGE_1" "$LOG_PATH_STAGE_2" "$PID_PATH_STAGE_1" "$PID_PATH_STAGE_2"' EXIT

  # Delete the old replica set
  mongo_start_background_local \
    "$PID_PATH_STAGE_1" \
    "$LOG_PATH_STAGE_1"

  mongo --port "$PORT" "/mongo-scripts/remove-replica-set.js"

  mongo_shutdown_background "$PID_PATH_STAGE_1"

  # Boot back up, this time with the new replica set
  mongo_start_background_exposed \
    "$PID_PATH_STAGE_2" \
    "$LOG_PATH_STAGE_2" \
    "$REPL_SET_NAME"

  mongo_options=($(mongo_exposed_connection_options))

  # Initialize the new replica set.
  mongo "${mongo_options[@]}" \
    --eval "var replica_set_name = '${REPL_SET_NAME}', primary_member_id = 0, primary_host = '${EXPOSE_HOST}:${!EXPOSE_PORT_PTR}';" \
    "/mongo-scripts/primary-initiate-replica-set.js"

  # Wait until MongoDB node becomes primary
  until mongo "${mongo_options[@]}" --quiet --eval 'quit(db.isMaster()["ismaster"] ? 0 : 1)'; do
    echo "Waiting until new MongoDB instance becomes primary"
    sleep 2
  done

  mongo_shutdown_background "$PID_PATH_STAGE_2"

elif [[ "$1" == "--initialize-from" ]]; then
  if [[ "$#" -lt 2 ]]; then
    echo "docker run -it aptible/mongodb --initialize-from mongodb://..."
    exit 1
  fi

  # We'll need users, passwords, certificates, cluster key, etc. here. They should all come from the environment.
  mongo_environment_full
  mongo_environment_require_cluster_key

  # We have no guarantee that whatever is in FROM_URL is actually the primary, so we have to actually query the primary.
  # Obviously, this is racy. If there are changes happening on the cluster while we work, we might end up sending cluster
  # commands to the wrong node. There isn't much we can do about it besides not provisioning multiple MongoDB nodes at the
  # same time or during an outage.
  FROM_URL="$2"
  parse_url "$FROM_URL"

  # Now, get the *actual* primary from that URL
  echo "Locating replica set primary"
  # shellcheck disable=2154
  PRIMARY_HOST_PORT="$(mongo_exec_and_extract "/mongo-scripts/secondary-find-primary.js" "${mongo_options[@]}" admin)"

  # Reconstruct primary URL using the credentials we were provided.
  # TODO - Consider using system and keyfile creds?
  # shellcheck disable=2154
  PRIMARY_URL="mongodb://${username}:${password}@${PRIMARY_HOST_PORT}/admin?ssl=true&x-sslVerify=false"

  parse_url "$PRIMARY_URL"
  PRIMARY_OPTIONS=("${mongo_options[@]}")

  # Create key file using cluster key that was provided in the environment.
  echo "$CLUSTER_KEY" > "$CLUSTER_KEY_FILE"
  chmod 600 "$CLUSTER_KEY_FILE"

  # Get the replica set name from the primary, and store it for future restarts. Unfortunately, MongoDB logs
  # things like SSL errors to stdout, so we can't really just get the output of db.runCommand and expect that
  # to match out replica set name.
  echo "Retrieving replica set name"
  REPL_SET_NAME="$(mongo_exec_and_extract "/mongo-scripts/secondary-get-replica-set-name.js" "${PRIMARY_OPTIONS[@]}" admin)"
  echo "$REPL_SET_NAME" > "$REPL_SET_NAME_FILE"

  # Autogenerate a random member ID. This makes it easier for us to update our votes and priority later on,
  # and also happens to be required for MongoDB 2.6. Unfortunately, the member ID needs to be a rather small
  # number. We pick one at random, but on the off chance that we pick the same one twice, the commands below
  # will fail (and exit with an error), and the `--initialize-from` operation needs to be restarted.
  echo "Choosing member ID"
  MEMBER_ID="$(randint_8)"
  until mongo "${PRIMARY_OPTIONS[@]}" admin --eval "var member_id = ${MEMBER_ID};" "/mongo-scripts/primary-test-member-id.js"; do
    echo "Member ID ${MEMBER_ID} is in use - trying another one"
    MEMBER_ID="$(randint_8)"
  done

  echo "$MEMBER_ID" > "$MEMBER_ID_FILE"

  # Start our local MongoDB to kickstart replication. Since we have SSL either set to requireSSL or preferSSL,
  # the slave needs to have SSL enabled when it comes up. This operation might take a while (MongoDB will rsync data
  # over from the slave), so we enable auth to ensure there is no unauthorized access to the replica as it comes up
  # (which means we won't be able to log in until the users DB is replicated).
  PID_PATH=/tmp/mongod.pid
  LOG_PATH=/tmp/mongod.log
  trap 'cat "$LOG_PATH"; rm "$LOG_PATH"' EXIT

  echo "Starting MongoDB"
  mongo_initialize_certs
  mongod \
    --dbpath "$DATA_DIRECTORY" \
    --bind_ip "0.0.0.0" \
    --port "$PORT" \
    --fork --logpath "$LOG_PATH" --pidfilepath "$PID_PATH" \
    --replSet "$REPL_SET_NAME" \
    --keyFile "$CLUSTER_KEY_FILE" \
    --sslMode "requireSSL" --sslPEMKeyFile "$SSL_BUNDLE_FILE" \
    --auth

  # Initate replication, from the primary Point it to the new replica we just launched.
  echo "Registering as nonvoting secondary"
  mongo \
    "${PRIMARY_OPTIONS[@]}" admin \
    --quiet \
    --eval "var secondary_member_id = $MEMBER_ID, secondary_host = '${EXPOSE_HOST}:${!EXPOSE_PORT_PTR}';" \
    "/mongo-scripts/primary-add-nonvoting-secondary.js"

  # Determine the URL this replica will acquire (and check its validity by parsing it - we'll use it later anyway)
  SECONDARY_URL="mongodb://${USERNAME}:${PASSPHRASE}@${EXPOSE_HOST}:${!EXPOSE_PORT_PTR}/admin?ssl=true&x-sslVerify=false"
  parse_url "$SECONDARY_URL"

  # Let's tell our Mongo that it should update itself to become a voting member when it comes back up
  echo "Preparing reconfiguration script"
  cat > "$PRE_START_FILE" <<EOM
#!/bin/bash
/mongo-scripts/reconfig.sh "$PRIMARY_URL" "$SECONDARY_URL" &
mv "\$0" "$\{0}.$\(date --iso-8601=seconds).bak"
EOM
  chmod +x "$PRE_START_FILE"

  # Wait until we actually join the cluster.
  echo "Waiting until initial synchronization completes"

  # shellcheck disable=2154
  until mongo "${mongo_options[@]}" "$database" --quiet --eval 'quit((db.isMaster()["ismaster"] || db.isMaster()["secondary"]) ? 0 : 1)'; do
    echo "Waiting until new MongoDB instance becomes primary or secondary"
    sleep 2
  done

  # Initialization is done, terminate MongoDB
  echo "Initial sync complete. Terminating MongoDB"
  kill "$(cat "$PID_PATH")"
  while [ -s "$DATA_DIRECTORY"/mongod.lock ]; do sleep 0.1; done

elif [[ "$1" == "--discover" ]]; then
  mongo_environment_minimal
  cat <<EOM
{
  "exposed_ports": [
    ${PORT}
  ],
  "suggested_configuration": {
    "CLUSTER_KEY": "$(pwgen -s 64)",
    "PASSPHRASE": "$(pwgen -s 32)"
  }
}
EOM

elif [[ "$1" == "--connection-url" ]]; then
  mongo_environment_full
  cat <<EOM
{
  "url": "mongodb://${USERNAME}:${PASSPHRASE}@${EXPOSE_HOST}:${!EXPOSE_PORT_PTR}/${DATABASE}?ssl=true"
}
EOM

elif [[ "$1" == "--client" ]]; then
  if [[ "$#" -lt 2 ]]; then
    echo "docker run -it aptible/mongodb --client mongodb://... [...]"
    exit 1
  fi
  shift

  parse_url "$1"
  shift

  exec mongo "${mongo_options[@]}" "$database" "$@"

elif [[ "$1" == "--dump" ]]; then
  if [[ "$#" -ne 2 ]]; then
    echo "docker run aptible/mongodb --dump mongodb://... > dump.mongo"
    exit 1
  fi
  # https://jira.mongodb.org/browse/SERVER-7860
  # Can't dump the whole database to stdout in a straightforward way. Instead,
  # dump to a directory and then tar the directory and print the tar to stdout.
  parse_url "$2"

  mongodump "${mongo_options[@]}" --db="$database" --out="/tmp/${dump_directory}" > /dev/null && tar cf - -C /tmp/ "$dump_directory"

elif [[ "$1" == "--restore" ]]; then
  if [[ "$#" -ne 2 ]]; then
    echo "docker run -i aptible/mongodb --restore mongodb://... < dump.mongo"
    exit 1
  fi
  tar xf - -C /tmp/
  parse_url "$2"
  mongorestore "${mongo_options[@]}" --db="$database" "/tmp/${dump_directory}/${database}"

elif [[ "$1" == "--readonly" ]]; then
  # MongoDB only supports read-only mode on a per-user basis. To make that
  # happen, it should be possible to mimic the `--initialize` sequence to set
  # the user's `roles` to [ "read" ].
  #
  # This presents some difficulties:
  # * no $USERNAME is being passed.
  # * normal invocations of the server would need to ensure the user wasn't in
  #     read-only mode.
  # * temporarily starting the daemon to make the change is ugly.
  #
  # With all of that said, leaving off read-only mode for now.
  echo "This image does not support read-only mode. Starting database normally."
  mongo_environment_minimal
  mongo_initialize_certs
  mongo_exec_foreground_exposed
else
  echo "Unrecognized command: $1"
  exit 1
fi
