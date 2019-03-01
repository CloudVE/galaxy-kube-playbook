# Build image-1: 
# - Stage 1: install python-virtualenv; to be used as base for final stage
# - Stage 2: install build tools; to be used as (optional) base for stage 3 
# - Stage 3: 
#   - base: stage 2 OR prebuilt image0
#   - run playbook (image0 avoids rerunning lengthy tasks)
#   - remove build artifacts + files not needed in container
# - Stage 4: 
#   - base: stage 1
#   - create galaxy user + group + directory
#   - copy galaxy files from stage 3
#   - finalize container (set path, user...)

# Init ARGs 
ARG ROOT_DIR=/galaxy
ARG SERVER_DIR=$ROOT_DIR/server
# NOTE: the value of GALAXY_USER must be also hardcoded in COPY in stage 4
ARG GALAXY_USER=galaxy
# For much faster build time override this with image0 (Dockerfile.0 build)
#docker build --build-arg STAGE2=<image0 name>...
ARG STAGE2=stage2_tools


# Stage-1
FROM ubuntu:18.04 AS stage1_virtualenv
ARG DEBIAN_FRONTEND=noninteractive

# Install python-virtualenv
RUN set -xe; \
    apt-get -qq update \
    && apt-get install -y --no-install-recommends \
        python-virtualenv \
    && apt-get autoremove -y \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/*


# Stage-2
FROM ubuntu:18.04 AS stage2_tools
ARG DEBIAN_FRONTEND=noninteractive

# Install build dependencies + ansible
RUN set -xe; \
    apt-get -qq update \
    && apt-get install -y --no-install-recommends \
        apt-transport-https \
        git \
        make \
        python-virtualenv \
        software-properties-common \
    \
    && apt-add-repository -y ppa:ansible/ansible \
    && apt-get -qq update \
    && apt-get install -y --no-install-recommends \
        ansible \
    \
    && apt-get autoremove -y && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/*


# Stage-3 
FROM $STAGE2 AS stage3_playbook
ARG DEBIAN_FRONTEND=noninteractive
ARG SERVER_DIR

# Remove context from previous build; copy current context; run playbook
WORKDIR /tmp/ansible
RUN rm -rf *
COPY . .
RUN ansible-playbook -i localhost, playbook.yml

# Remove build artifacts + files not needed in container
WORKDIR $SERVER_DIR
RUN rm -rf \
        .ci \
        .git \
        .venv/bin/node \
        .venv/include/node \
        .venv/lib/node_modules \
        .venv/src/node* \
        client/node_modules \
        doc \
        test \
        test-data


# Stage-4 
FROM stage1_virtualenv AS build_final
ARG DEBIAN_FRONTEND=noninteractive
ARG ROOT_DIR
ARG SERVER_DIR
ARG GALAXY_USER

# Create Galaxy user, group, directory; chown
RUN set -xe; \
      adduser --system --group $GALAXY_USER \
      && mkdir -p $SERVER_DIR \
      && chown $GALAXY_USER:$GALAXY_USER $ROOT_DIR -R

WORKDIR $ROOT_DIR
# Copy galaxy files to final image
# The chown value MUST be hardcoded (see #35018 at github.com/moby/moby)
COPY --chown=galaxy:galaxy --from=stage3_playbook $ROOT_DIR .

WORKDIR $SERVER_DIR
EXPOSE 8080
USER $GALAXY_USER
ENV PATH="$SERVER_DIR/.venv/bin:${PATH}"

# [optional] to run:
#CMD uwsgi --yaml config/galaxy.yml
