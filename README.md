# ![](https://gravatar.com/avatar/11d3bc4c3163e3d238d558d5c9d98efe?s=64) aptible/mongodb

[![Docker Repository on Quay.io](https://quay.io/repository/aptible/mongodb/status)](https://quay.io/repository/aptible/mongodb)
[![Build Status](https://travis-ci.org/aptible/docker-mongodb.svg?branch=master)](https://travis-ci.org/aptible/docker-mongodb)

[![](http://dockeri.co/image/aptible/mongodb)](https://registry.hub.docker.com/u/aptible/mongodb/)

MongoDB on Docker

## Installation and Usage

    docker pull quay.io/aptible/mongodb

This is an image conforming to the [Aptible database specification](https://support.aptible.com/topics/paas/deploy-custom-database/). To run a server for development purposes, execute

    docker create --name data quay.io/aptible/mongodb
    docker run --volumes-from data -e USERNAME=aptible -e PASSPHRASE=pass -e DATABASE=db quay.io/aptible/mongodb --initialize
    docker run --volumes-from data -P quay.io/aptible/mongodb

The first command sets up a data container named `data` which will hold the configuration and data for the database. The second command creates a MongoDB instance with a username, passphrase and database name of your choice. The third command starts the database server.

## Available Tags

* `latest`: Currently MongoDB 4.0
* `4.0`: MongoDB 4.0
* `3.6`: MongoDB 3.6
* `3.4`: MongoDB 3.4 - EOL in [January 2020](https://www.mongodb.com/support-policy)

## Deprecated Tags

* `2.6`: MongoDB 2.6 - [DEPRECATED](https://www.aptible.com/documentation/deploy/reference/databases/version-support.html)
* `3.2`: MongoDB 3.2 - [DEPRECATED](https://www.aptible.com/documentation/deploy/reference/databases/version-support.html)

## Tests

Tests are run as part of the `Dockerfile` build. To execute them separately within a container, run:

    bats test

## Deployment

To push the Docker image to Quay, run the following command:

    make release

## Continuous Integration

Images are built and pushed to Docker Hub on every deploy. Because Quay currently only supports build triggers where the Docker tag name exactly matches a GitHub branch/tag name, we must run the following script to synchronize all our remote branches after a merge to master:

    make sync-branches

## Copyright and License

MIT License, see [LICENSE](LICENSE.md) for details.

Copyright (c) 2019 [Aptible](https://www.aptible.com) and contributors.
