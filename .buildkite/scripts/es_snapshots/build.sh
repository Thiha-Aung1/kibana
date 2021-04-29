#!/bin/bash

set -euo pipefail

source "$(dirname "${0}")/../util.sh"

cd ..
destination="$(pwd)/es-build"
mkdir -p "$destination"

mkdir -p elasticsearch && cd elasticsearch

# TODO use mirror from agent image
git init
git remote add origin https://github.com/elastic/elasticsearch.git
git fetch origin --depth 1 master
git reset --hard FETCH_HEAD

export ELASTICSEARCH_BRANCH=master # TODO
export ELASTICSEARCH_GIT_COMMIT="$(git rev-parse HEAD)"
export ELASTICSEARCH_GIT_COMMIT_SHORT="$(git rev-parse --short HEAD)"

# These turn off automation in the Elasticsearch repo
export BUILD_NUMBER=""
export JENKINS_URL=""
export BUILD_URL=""
export JOB_NAME=""
export NODE_NAME=""
export DOCKER_BUILDKIT=""

# Reads the ES_BUILD_JAVA env var out of .ci/java-versions.properties and exports it
export "$(grep '^ES_BUILD_JAVA' .ci/java-versions.properties | xargs)"

export PATH="$HOME/.java/$ES_BUILD_JAVA/bin:$PATH"
export JAVA_HOME="$HOME/.java/$ES_BUILD_JAVA"

echo "--- Build Elasticsearch"
./gradlew -Dbuild.docker=true assemble --parallel

echo "--- Create distribution archives"
find distribution -type f \( -name 'elasticsearch-*-*-*-*.tar.gz' -o -name 'elasticsearch-*-*-*-*.zip' \) -not -path '*no-jdk*' -not -path '*build-context*' -exec cp {} "$destination" \;

ls -alh "$destination"

echo "--- Create docker image archives"
docker images "docker.elastic.co/elasticsearch/elasticsearch"
docker images "docker.elastic.co/elasticsearch/elasticsearch" --format "{{.Tag}}" | xargs -n1 echo 'docker save docker.elastic.co/elasticsearch/elasticsearch:${0} | gzip > ../es-build/elasticsearch-${0}-docker-image.tar.gz'
docker images "docker.elastic.co/elasticsearch/elasticsearch" --format "{{.Tag}}" | xargs -n1 bash -c 'docker save docker.elastic.co/elasticsearch/elasticsearch:${0} | gzip > ../es-build/elasticsearch-${0}-docker-image.tar.gz'

cd "$destination"

find ./* -exec bash -c "shasum -a 512 {} > {}.sha512" \;
ls -alh "$destination"

cd "$BUILDKITE_BUILD_CHECKOUT_PATH"
node "$(dirname "${0}")/create_manifest.js" "$destination"
