#!/bin/bash
set -o errexit
set -o nounset

# We have to specify all the dependencies to ensure the right versions
# get installed for all the packages (the mongodb-X package doesn't
# specify versions for the packages it depends on).

apt-install \
  "mongodb-${MONGO_FLAVOR}=${MONGO_VERSION}" \
  "mongodb-${MONGO_FLAVOR}-server=${MONGO_VERSION}" \
  "mongodb-${MONGO_FLAVOR}-shell=${MONGO_VERSION}" \
  "mongodb-${MONGO_FLAVOR}-mongos=${MONGO_VERSION}" \
  "mongodb-${MONGO_FLAVOR}-tools=${MONGO_VERSION}"
