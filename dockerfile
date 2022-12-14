#ARG ARCH=arm64
ARG NODE_VERSION=16
ARG OS=bullseye

FROM node:${NODE_VERSION}-${OS} AS base

# Copy scripts
COPY scripts/*.sh /tmp/
RUN /bin/bash -c 'chmod +x /tmp/*.sh'
RUN ls -la /tmp

# Install tools, create Node-RED app and data dir, add user and set rights
RUN set -ex
RUN apt-get update && apt-get install -y \
        bash \
        tzdata \
        curl \
        nano \
        wget \
        git \
        openssl \
        openssh-client \
        ca-certificates \
        chromium \
        nmap \
        net-tools && \
    curl -s https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh | bash && \
    apt-get install speedtest && \
    mkdir -p /usr/src/node-red /data && \
    deluser --remove-home node && \
    # adduser --home /usr/src/node-red --disabled-password --no-create-home node-red --uid 1000 && \
    useradd --home-dir /usr/src/node-red --uid 1000 node-red && \
    chown -R node-red:root /data && chmod -R g+rwX /data && \
    chown -R node-red:root /usr/src/node-red && chmod -R g+rwX /usr/src/node-red
    # chown -R node-red:node-red /data && \
    # chown -R node-red:node-red /usr/src/node-red

# Set work directory
WORKDIR /usr/src/node-red-docker
RUN ls -la /usr/src/node-red-docker

# Setup SSH known_hosts file
COPY known_hosts.sh .
RUN /bin/bash -c 'chmod +x ./known_hosts.sh'
RUN ./known_hosts.sh /etc/ssh/ssh_known_hosts
RUN rm /usr/src/node-red-docker/known_hosts.sh
RUN echo "PubkeyAcceptedKeyTypes +ssh-rsa" >> /etc/ssh/ssh_config

# package.json contains Node-RED NPM module and node dependencies
COPY package.json .
COPY flows.json /data
COPY scripts/entrypoint.sh .
RUN /bin/bash -c 'chmod 755 entrypoint.sh'

#### Stage BUILD #######################################################################################################
FROM base AS build

# Install Build tools
RUN apt-get update && apt-get install -y build-essential python 
RUN npm install --unsafe-perm --no-update-notifier --no-fund --omit=dev
RUN npm uninstall node-red-node-gpio
RUN npm ls --omit=dev
#RUN npm audit fix --force
RUN cp -R node_modules prod_node_modules
RUN ls -la prod_node_modules
RUN pwd

#### Stage RELEASE #####################################################################################################
FROM base AS RELEASE
ARG BUILD_DATE
ARG BUILD_VERSION
ARG BUILD_REF
ARG NODE_RED_VERSION
#ARG ARCH
ARG TAG_SUFFIX=default

LABEL org.label-schema.build-date=${BUILD_DATE} \
    org.label-schema.docker.dockerfile=".docker/dockerfile" \
    org.label-schema.license="Apache-2.0" \
    org.label-schema.name="Node-RED" \
    org.label-schema.version=${BUILD_VERSION} \
    org.label-schema.description="Low-code programming for event-driven applications." \
    org.label-schema.url="https://nodered.org" \
    org.label-schema.vcs-ref=${BUILD_REF} \
    org.label-schema.vcs-type="Git" \
    org.label-schema.vcs-url="https://github.com/barcar/node-red-docker" \
    org.label-schema.arch=${ARCH} \
    authors="Dave Conway-Jones, Nick O'Leary, James Thomas, Raymond Mouthaan"

COPY --from=build /usr/src/node-red-docker/prod_node_modules ./node_modules
RUN ls -la node_modules

# Chown, install devtools & Clean up
RUN chown -R node-red:root /usr/src/node-red && \
    apt-get update && apt-get install -y build-essential python-dev python3 && \
    rm -r /tmp/*

RUN npm config set cache /data/.npm --global

USER node-red

RUN speedtest --accept-license --accept-gdpr --progress=NO

# Env variables
ENV NODE_RED_VERSION=$NODE_RED_VERSION \
    NODE_PATH=/usr/src/node-red/node_modules:/data/node_modules \
    PATH=/usr/src/node-red/node_modules/.bin:${PATH} \
    FLOWS=flows.json

# ENV NODE_RED_ENABLE_SAFE_MODE=true    # Uncomment to enable safe start mode (flows not running)
ENV NODE_RED_ENABLE_PROJECTS=true

# Expose the listening port of node-red
EXPOSE 1880

# Add a healthcheck (default every 30 secs)
#HEALTHCHECK CMD curl http://localhost:1880/ || exit 1

ENTRYPOINT ["./entrypoint.sh"]
