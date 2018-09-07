#!/bin/bash
set -o errexit
set -o nounset

# We have to specify all the dependencies to ensure the right versions
# get installed for all the packages (the mongodb-org package doesn't
# specify versions for the packages it depends on).

apt-install \
  "mongodb-org=${MONGO_VERSION}" \
  "mongodb-org-server=${MONGO_VERSION}" \
  "mongodb-org-shell=${MONGO_VERSION}" \
  "mongodb-org-mongos=${MONGO_VERSION}" \
  "mongodb-org-tools=${MONGO_VERSION}"
