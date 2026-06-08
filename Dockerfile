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

# --immutable omitted: yarn Berry updates peer-dep state entries across environments,
# causing false failures. The committed yarn.lock still pins all package versions.
RUN yarn install

# Install tsx for TypeScript loading — avoids --experimental-strip-types which
# alters webpack's module concatenation order causing runtime undefined exports.
RUN npm install -g tsx

# Patch import.meta.dirname/filename in the plugin webpack config (undefined via tsx loader).
RUN sed -i "s|import\.meta\.dirname|fileURLToPath(new URL('.', import.meta.url))|g" \
        packages/grafana-plugin-configs/webpack.config.ts && \
    sed -i "s|import\.meta\.filename|fileURLToPath(import.meta.url)|g" \
        packages/grafana-plugin-configs/webpack.config.ts && \
    sed -i '1s|^|import { fileURLToPath } from "url";\n|' \
        packages/grafana-plugin-configs/webpack.config.ts

COPY tsconfig.json .eslintrc .editorconfig .browserslistrc .prettierrc.js ./
COPY scripts scripts
COPY emails emails

ENV NODE_ENV=production
# Clear webpack filesystem cache to prevent stale chunks from cached yarn install layer
RUN rm -rf node_modules/.cache
# Strip the react19 build step — it overwrites the main build's runtime chunk with one
# that references a different set of chunk hashes, causing the wrong modules to load.
RUN node -e "const fs=require('fs');const p=JSON.parse(fs.readFileSync('package.json','utf8'));p.scripts['build']=p.scripts['build'].replace(' && yarn build:react19','');fs.writeFileSync('package.json',JSON.stringify(p,null,2));"
RUN NODE_OPTIONS="--max_old_space_size=8000 --import tsx" yarn build

# ── Final image ───────────────────────────────────────────────────────────────
FROM grafana/grafana:${GRAFANA_VERSION}

LABEL maintainer="it@enflux.io"

# Clear the official frontend build to prevent chunk mixing between
# our compiled JS and the official image's pre-built chunks.
USER root
RUN rm -rf /usr/share/grafana/public/build

# Replace with our fully custom-branded build
COPY --from=js-builder /tmp/grafana/public/build /usr/share/grafana/public/build
COPY --from=js-builder /tmp/grafana/public/img/grafana_icon.svg /usr/share/grafana/public/img/grafana_icon.svg

USER grafana
