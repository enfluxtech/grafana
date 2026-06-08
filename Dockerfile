# syntax=docker/dockerfile:1
#
# Enflux Grafana image — builds only the frontend from source so custom
# branding (Branding.tsx + grafana_icon.svg) is compiled into the JS bundle.
# The Go backend is taken from the official grafana/grafana:13.0.1 image,
# avoiding the import-cycle bug in the security-01 source tree.

ARG GRAFANA_VERSION=13.0.1
ARG JS_IMAGE=node:22-alpine
ARG JS_PLATFORM=linux/amd64

# ── Frontend build ────────────────────────────────────────────────────────────
FROM --platform=${JS_PLATFORM} ${JS_IMAGE} AS js-builder

ENV NODE_OPTIONS=--max_old_space_size=8000

WORKDIR /tmp/grafana

COPY package.json project.json nx.json yarn.lock .yarnrc.yml ./
COPY .yarn .yarn
COPY packages packages
COPY plugins-bundled plugins-bundled
COPY public public
COPY LICENSE ./
COPY conf/defaults.ini ./conf/defaults.ini

# Inject Enflux branding before the build
COPY enflux/Branding.tsx public/app/core/components/Branding/Branding.tsx
COPY enflux/grafana_icon.svg public/img/grafana_icon.svg

RUN apk add --no-cache make build-base python3

# Use plain yarn install (security-01 lockfile is out of sync with package.json)
RUN yarn install

# tsx is needed for webpack-cli to load ESM TypeScript config files (Grafana 13+)
RUN npm install -g tsx

COPY tsconfig.json .eslintrc .editorconfig .browserslistrc .prettierrc.js ./
COPY scripts scripts
COPY emails emails

ENV NODE_ENV=production
# Import tsx only for the build step so webpack-cli can load .ts webpack configs
RUN NODE_OPTIONS="--max_old_space_size=8000 --import tsx" yarn build

# ── Final image ───────────────────────────────────────────────────────────────
FROM grafana/grafana:${GRAFANA_VERSION}

LABEL maintainer="it@enflux.io"

# Replace upstream frontend with our custom-branded build
COPY --from=js-builder /tmp/grafana/public/build /usr/share/grafana/public/build
COPY --from=js-builder /tmp/grafana/public/img/grafana_icon.svg /usr/share/grafana/public/img/grafana_icon.svg
