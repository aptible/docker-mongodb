#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail

MONGO_NAME="mongodb-src-r${MONGO_VERSION}"
MONGO_ARCHIVE="${MONGO_NAME}.tar.gz"
MONGO_URL="https://fastdl.mongodb.org/src/${MONGO_ARCHIVE}"
MONGO_PACKAGE="$(basename "${MONGO_URL}")"
MONGO_BUILD_DEPS=(build-essential scons libssl-dev wget checkinstall)
MONGO_INSTALL_GROUP="core"

MONGO_PACKAGES_PKGLIST="mongodb-org, mongodb-org-server, mongodb-org-shell, mongodb-org-mongos"
MONGO_RUNDEPS_PKGLIST="libc6, libgcc1, libssl1.0.0, libstdc++6, adduser"

apt-get update
apt-get install -y adduser  # Runtime dep
apt-get install -y "${MONGO_BUILD_DEPS[@]}"  # Build-time deps

mongo_build_dir="/tmp/mongo-build"
mkdir "${mongo_build_dir}"
cd "${mongo_build_dir}"

wget "${MONGO_URL}"
tar -xf "${MONGO_ARCHIVE}"
cd "${MONGO_NAME}"

echo "MongoDB build from source by Aptible" > description-pak

checkinstall \
  --type=debian \
  --install=yes \
  --pkgname="mongodb-aptible-${MONGO_INSTALL_GROUP}" \
  --pkgversion="${MONGO_VERSION}" \
  --pkggroup="database" \
  --maintainer="thomas@aptible.com" \
  --replaces="${MONGO_PACKAGES_PKGLIST}" \
  --provides="${MONGO_PACKAGES_PKGLIST}" \
  --conflicts="${MONGO_PACKAGES_PKGLIST}" \
  --requires="${MONGO_RUNDEPS_PKGLIST}" \
  --nodoc --fstrans=no -y \
  scons -j "$(nproc)" "${MONGO_INSTALL_GROUP}" install --ssl

cd /
rm -rf "${mongo_build_dir}"

apt-get remove -y "${MONGO_BUILD_DEPS[@]}"
apt-get autoremove -y
rm -rf /var/lib/apt/lists/*

