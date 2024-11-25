# syntax=docker/dockerfile:1

ARG BASE_IMAGE=alpine:3.20
ARG JS_IMAGE=node:20-alpine
ARG JS_PLATFORM=linux/amd64
ARG GO_IMAGE=golang:1.20-alpine

ARG GO_SRC=go-builder
ARG JS_SRC=js-builder

# JavaScript Builder Stage
FROM --platform=${JS_PLATFORM} ${JS_IMAGE} AS js-builder

ENV NODE_OPTIONS=--max_old_space_size=8000

WORKDIR /tmp/grafana

# Copy essential files for Node.js dependencies and build
COPY package.json project.json nx.json yarn.lock .yarnrc.yml ./
COPY .yarn .yarn
COPY packages packages
COPY plugins-bundled plugins-bundled
COPY public public
COPY LICENSE ./
COPY conf/defaults.ini ./conf/defaults.ini

RUN apk add --no-cache make build-base python3

RUN yarn install --immutable

COPY tsconfig.json .eslintrc .editorconfig .browserslistrc .prettierrc.js ./
COPY scripts scripts
COPY emails emails

ENV NODE_ENV=production
RUN yarn build

# Go Builder Stage
FROM ${GO_IMAGE} AS go-builder

ARG COMMIT_SHA=""
ARG BUILD_BRANCH=""
ARG GO_BUILD_TAGS="oss"
ARG WIRE_TAGS="oss"
ARG BINGO="true"

# Install build dependencies
RUN apk add --no-cache \
    binutils-gold \
    bash \
    gcc g++ \
    make git

WORKDIR /tmp/grafana

# Copy go.mod and other related files
COPY go.* ./
COPY .bingo .bingo
COPY pkg/util/xorm/go.* pkg/util/xorm/
COPY pkg/apiserver/go.* pkg/apiserver/
COPY pkg/apimachinery/go.* pkg/apimachinery/
COPY pkg/build/go.* pkg/build/
COPY pkg/build/wire/go.* pkg/build/wire/
COPY pkg/promlib/go.* pkg/promlib/
COPY pkg/storage/unified/resource/go.* pkg/storage/unified/resource/
COPY pkg/storage/unified/apistore/go.* pkg/storage/unified/apistore/
COPY pkg/semconv/go.* pkg/semconv/
COPY pkg/aggregator/go.* pkg/aggregator/
COPY apps/playlist/go.* apps/playlist/

# Download Go modules
RUN go mod download

# Install bingo and build tools if BINGO is true
RUN if [ "$BINGO" = "true" ]; then \
      go install github.com/bwplotka/bingo@latest && \
      bingo get -v; \
    fi

# Copy all sources and build files
COPY embed.go Makefile build.go package.json ./
COPY cue.mod cue.mod
COPY kinds kinds
COPY kindsv2 kindsv2
COPY local local
COPY packages/grafana-schema packages/grafana-schema
COPY public/app/plugins public/app/plugins
COPY public/api-merged.json public/api-merged.json
COPY pkg pkg
COPY scripts scripts
COPY conf conf
COPY .github .github

ENV COMMIT_SHA=${COMMIT_SHA}
ENV BUILD_BRANCH=${BUILD_BRANCH}

# Build Grafana Go binaries
RUN make build-go GO_BUILD_TAGS=${GO_BUILD_TAGS} WIRE_TAGS=${WIRE_TAGS}

# Tarball Extractor Stage
FROM ${BASE_IMAGE} AS tgz-builder

WORKDIR /tmp/grafana

ARG GRAFANA_TGZ="grafana-latest.linux-x64-musl.tar.gz"

COPY ${GRAFANA_TGZ} /tmp/grafana.tar.gz

RUN tar xzf /tmp/grafana.tar.gz --strip-components=1

# Helpers for COPY --from
FROM ${GO_SRC} AS go-src
FROM ${JS_SRC} AS js-src

# Final Stage
FROM ${BASE_IMAGE}

LABEL maintainer="Grafana Labs <hello@grafana.com>"

ARG GF_UID="472"
ARG GF_GID="0"

ENV PATH="/usr/share/grafana/bin:$PATH" \
    GF_PATHS_CONFIG="/etc/grafana/grafana.ini" \
    GF_PATHS_DATA="/var/lib/grafana" \
    GF_PATHS_HOME="/usr/share/grafana" \
    GF_PATHS_LOGS="/var/log/grafana" \
    GF_PATHS_PLUGINS="/var/lib/grafana/plugins" \
    GF_PATHS_PROVISIONING="/etc/grafana/provisioning"

WORKDIR $GF_PATHS_HOME

# Install runtime dependencies
RUN apk add --no-cache \
    ca-certificates \
    bash \
    curl \
    tzdata \
    musl-utils

# Add glibc support for Alpine if on x86_64
RUN if grep -i -q alpine /etc/issue && [ "$(arch)" = "x86_64" ]; then \
      wget -q -O /etc/apk/keys/sgerrand.rsa.pub https://alpine-pkgs.sgerrand.com/sgerrand.rsa.pub && \
      wget https://github.com/sgerrand/alpine-pkg-glibc/releases/download/2.35-r0/glibc-2.35-r0.apk \
        -O /tmp/glibc-2.35-r0.apk && \
      apk add --force-overwrite --no-cache /tmp/glibc-2.35-r0.apk && \
      rm -f /tmp/glibc-2.35-r0.apk; \
    fi

# Set up user and permissions
RUN if ! getent group "$GF_GID"; then \
      addgroup -S -g $GF_GID grafana; \
    fi && \
    GF_GID_NAME=$(getent group $GF_GID | cut -d':' -f1) && \
    adduser -S -u $GF_UID -G "$GF_GID_NAME" grafana && \
    mkdir -p \
      "$GF_PATHS_PROVISIONING/datasources" \
      "$GF_PATHS_PROVISIONING/dashboards" \
      "$GF_PATHS_LOGS" \
      "$GF_PATHS_PLUGINS" \
      "$GF_PATHS_DATA" && \
    chown -R grafana:$GF_GID_NAME "$GF_PATHS_HOME" "$GF_PATHS_DATA" "$GF_PATHS_PROVISIONING" "$GF_PATHS_LOGS"

# Copy built assets
COPY --from=go-src /tmp/grafana/bin/grafana* ./bin/
COPY --from=js-src /tmp/grafana/public ./public
COPY --from=js-src /tmp/grafana/LICENSE ./

EXPOSE 3000

ARG RUN_SH=./packaging/docker/run.sh
COPY ${RUN_SH} /run.sh

USER "$GF_UID"
ENTRYPOINT [ "/run.sh" ]
