# See here for more information on multi stage builds with BUILDKIT
# https://docs.docker.com/develop/develop-images/build_enhancements/#to-enable-buildkit-builds
# https://www.docker.com/blog/advanced-dockerfiles-faster-builds-and-smaller-images-using-buildkit-and-multistage-builds/
# https://github.com/docker/cli/issues/1134#issuecomment-405946645
#
# The multi stage builds run in this order:
#
# 1. Install all fundamental OS dependencies onto the BASE IMAGE.
# 2. Install and configure the image as per our JupyterHub requirements
# 3. Do any Target specific installation and/or configuration.
#
# You can run the multistage build command for a custom image using this command:
#
# DOCKER_BUILDKIT=1 docker build \
#     -t uodcvip/<image-name>:<tag> \
#     --no-cache \
#     --buildarg BASE_CONTAINER=<username>/<name-of-original-image>:<tag> \
#     -f <path/to/custom>/Dockerfile \
#     --target custom \
#     .
#

### 1. === Base image

# Ubuntu 18.04 (bionic) from 2019-06-12
# https://github.com/tianon/docker-brew-ubuntu-core/commit/3c462555392cb188830b7c91e29311b5fad90cfe
# MR 29/03/21 is this ^ a stale comment?

ARG BASE_CONTAINER
FROM $BASE_CONTAINER as base
LABEL maintainer="Mike Robeson <mrobeson@dundee.ac.uk>"

USER root
ENV DEBIAN_FRONTEND noninteractive

# Install all our OS dependencies

RUN apt-get update \
 && apt-get install -yq \
    wget \
    curl \
    bzip2 \
    ca-certificates \
    sudo \
    locales \
    fonts-liberation \
    run-one \
    python3-pip \
    mercurial \
    git \
    cmake \
    p7zip-full \
    unrar \
    npm \
    gcc \
    g++ \
    make \
    openssh-server \
 && apt clean \
 && rm -rf /var/lib/apt/lists/* \
 && apt autoremove -yqq

# configure and enable ssh access
# don't put config inside /home/ as that conflicts with /home/NB_USER
RUN sed -i /etc/ssh/sshd_config \
 -e 's/#PermitRootLogin.*/PermitRootLogin no/' \
 -e 's/#PubkeyAuthentication.*/PubkeyAuthentication yes/' \
 -e 's/#RSAAuthentication.*/RSAAuthentication yes/'  \
 -e 's/#PasswordAuthentication.*/PasswordAuthentication yes/' \
 -e 's/PasswordAuthentication.*/PasswordAuthentication yes/' \
 -e 's/#SyslogFacility.*/SyslogFacility AUTH/' \
 -e 's/#LogLevel.*/LogLevel INFO/' \
 -e 's|#AuthorizedKeysFile.*|AuthorizedKeysFile /ssh/authorized_keys|' \
 -e 's|#UserKnownHostsFile.*|UserKnownHostsFile /ssh/knownhosts/|' \
 -e 's/#PermitTunnel.*/PermitTunnel yes/' \
 -e 's/#AllowTcpForwarding.*/AllowTcpForwarding yes/' \
 -e 's/#AllowAgentForwarding.*/AllowAgentForwarding yes/' \
 && mkdir /var/run/sshd /ssh/ \
 && touch /ssh/authorized_keys
RUN service ssh start && ssh-keygen -A
EXPOSE 22

# Install nodejs 10.0
# https://joshtronic.com/2018/05/08/how-to-install-nodejs-10-on-ubuntu-1804-lts/
# TODO: node 10 is EOL
RUN curl -sL https://deb.nodesource.com/setup_10.x | bash -
RUN apt install -yqq nodejs

# Install yarn dependency for jupyterhub

RUN curl -sL https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add -
RUN echo "deb https://dl.yarnpkg.com/debian/ stable main" > /etc/apt/sources.list.d/yarn.list
RUN apt update \
 && apt install -yqq  yarn


# Install opencv2 dependencies (incl. optionals)
# https://docs.opencv.org/2.4/doc/tutorials/introduction/linux_install/linux_install.html
# libjasper and python-* deps are left out 
# -> libjasper-dev no longer exists

RUN apt update \
 && apt install -yqq \
    build-essential \
    libgtk2.0-dev \
    pkg-config \
    libavcodec-dev \
    libavformat-dev \
    libswscale-dev \
    libtbb2 \
    libtbb-dev \
    libjpeg-dev \
    libpng-dev \
    libtiff-dev \
    libdc1394-22-dev \
 && apt clean \
 && rm -rf /var/lib/apt/lists/* \
 && apt autoremove -yqq

ENV TINI_VERSION v0.18.0
ADD https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini /tini
RUN chmod +x /tini

# Use tini -s to sub reap when tini won't be running as PID 1 (we use --pid=host at runtime)
# use tini -g to process groups to make sure subprocess close on exit.
ENTRYPOINT ["/tini", "-g", "-s", "--"]

### 2. ==== Jupyter Base image set up
# Copyright (c) Jupyter Development Team.
# Distributed under the terms of the Modified BSD License.

FROM base AS jupyter
LABEL maintainer="Mike Robeson <mrobeson@dundee.ac.uk>"

# N.B. we have to use the `--force` flag because npm doesn't trust it's users

RUN npm install -g configurable-http-proxy \
 && npm cache clean --force


# Install python requirements for jupyter
# This includes the jupyterhub notebook server, jupyter lab etc.

ADD Jupyter/jupyterhub-requirements.txt /tmp/

# Tensorflow 1.13.1 uses Python 3.5.2 which is EOL

RUN if [ "$(python3 --version)" = "Python 3.5.2" ] \
  ; then curl https://bootstrap.pypa.io/3.5/get-pip.py -o /get-pip.py \
  ; else curl https://bootstrap.pypa.io/get-pip.py -o /get-pip.py \
  ; fi
RUN python3 /get-pip.py --force-reinstall
RUN python3 -m pip install -U -r /tmp/jupyterhub-requirements.txt \
 && rm -f /tmp/*-requirements.txt \
 && rm -f /get-pip.py

# Add the bash kernel
# https://github.com/takluyver/bash_kernel

RUN python3 -m pip install bash_kernel && python3 -m bash_kernel.install

# Configure container environment
# N.B. We actually *need* to use the jovyan `user` at build time.
# SystemUserSpawner is configured to start the containers as a root user, the `start.sh` script will
# then switch to the correct user (modify permissions etc.) before the jupyterlab process starts

ARG NB_USER="jovyan"
ARG NB_UID="1000"
ARG NB_GID="100"

ENV SHELL=/bin/bash \
    NB_USER=$NB_USER \
    NB_UID=$NB_UID \
    NB_GID=$NB_GID \
    LC_ALL=en_US.UTF-8 \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US.UTF-8 \
    HOME=/home/$NB_USER

RUN echo "en_US.UTF-8 UTF-8" > /etc/locale.gen \
 && locale-gen

# Enable prompt color in the skeleton .bashrc before creating the default NB_USER

RUN sed -i 's/^#force_color_prompt=yes/force_color_prompt=yes/' /etc/skel/.bashrc

# Create NB_USER wtih name jovyan user with UID=1000 and in the 'users' group
# and make sure these dirs are writable by the `users` group.
# If this is the matlab image               ===> modify the existing `matlab` user
# elif this is an existing jupyter image    ===> add the jovyan user

RUN echo "auth requisite pam_deny.so" >> /etc/pam.d/su \
   && sed -i.bak -e 's/^%admin/#%admin/' /etc/sudoers \
   && sed -i.bak -e 's/^%sudo/#%sudo/' /etc/sudoers \
   && if [ $(grep -c '^matlab' /etc/passwd) -eq 1 ] \
      ; then usermod -l $NB_USER -u $NB_UID -g $NB_GID -m -d /home/$NB_USER -s $SHELL matlab \
      ; else useradd -m -s $SHELL -N -u $NB_UID $NB_USER \
      ; fi \
   && chmod g+w /etc/passwd 

# Let user accounts in the "users" group to use sudo for apt commands ONLY.

RUN mkdir -p /etc/sudoers.d/ \
 && echo '%users ALL = NOPASSWD : /usr/bin/apt-get , /usr/bin/apt, /usr/bin/apt-key, /usr/bin/add-apt-repository' > /etc/sudoers.d/apt \
 && chmod 0444 /etc/sudoers.d/apt


# Additional directories can be added to CHOWN_EXTRA to give shared user access
# Note that CHOWN_EXTRA is only called if the container strarts as root.
# See: ServerConfig/jupyyterhub/config.py

RUN mkdir -p /shares/local/tensorboard && chown -R ${NB_UID}:${NB_GID} /shares/local/tensorboard
RUN mkdir -p /shares/local/cvip && chown -R ${NB_UID}:${NB_GID} /shares/local/cvip
RUN mkdir -p /shares/network/share && chown -R ${NB_UID}:${NB_GID} /shares/network/share
RUN mkdir -p /shares/network/studentshare && chown -R ${NB_UID}:${NB_GID} /shares/network/studentshare
ENV CHOWN_EXTRA="/shares/local/tensorboard,/shares/local/cvip,/shares/network/share,/shares/network/studentshare"


# Set up the user's environment

USER $NB_USER:users
ARG PYTHON_VERSION=default
ENV JUPYTER_ENABLE_LAB=true
WORKDIR $HOME

# Repeat the CHOWN extra for some reason.

ENV CHOWN_EXTRA="/shares/local/tensorboard,/shares/local/cvip,/shares/network/share,/shares/network/studentshare"

# Configure container startup and settings.

EXPOSE 8888
CMD ["entrypoint.sh"]

# Add local files as late as possible to avoid cache busting
COPY Jupyter/entrypoint.sh /usr/local/bin/
COPY Jupyter/start.sh /usr/local/bin/
COPY Jupyter/start-notebook.sh /usr/local/bin/
COPY Jupyter/start-singleuser.sh /usr/local/bin/

### 3. =========== BUILD TARGETS ============ ####

### ==== CPU TARGET: BASH, PYTHON and R only
FROM jupyter as cpu
USER root
# Required dependencies
RUN apt update && apt install -yqq \
  r-base \
  r-base-dev \
  libzmq3-dev \
  libcurl4-openssl-dev \
  libssl-dev \
  libxml2 \
  libxml2-dev \
  libxml2-utils \
  jupyter-core \
  jupyter-client \
  libudunits2-dev \
 && apt clean \
 && rm -rf /var/lib/apt/lists/* \
 && apt autoremove -yqq

# Install the R jupyter kernel 
# https://irkernel.github.io/installation/
# pbdZMQ doesn't install properly on ubuntu for some unknown reason, so install from github source.
# https://github.com/RBigData/pbdZMQ#installation

RUN R -e "options(warn=2); install.packages('devtools'); library(devtools); install_github('RBigData/pbdZMQ');"
RUN R -e "options(warn=2); install.packages(c('IRdisplay', 'IRkernel')); IRkernel::installspec(user = FALSE);"

# Install some helpful start packages.
# https://towardsdatascience.com/top-r-libraries-for-data-science-9b24f658e243

#RUN R -e "options(warn=2); install.packages('ggplot2');" && rm -rf /tmp/*
#RUN R -e "options(warn=2); install.packages('RCurl');" && rm -rf /tmp/*
#RUN R -e "options(warn=2); install.packages('rmarkdown');" && rm -rf /tmp/*
#RUN R -e "options(warn=2); install.packages('plotly');" && rm -rf /tmp/*
#RUN R -e "options(warn=2); install.packages('tidymodels');" && rm -rf /tmp/*
#RUN R -e "options(warn=2); install.packages('dplyr');" && rm -rf /tmp/*
#RUN R -e "options(warn=2); install.packages('esquisse');" && rm -rf /tmp/*
#RUN R -e "options(warn=2); install.packages('lubridate');" && rm -rf /tmp/*
#RUN R -e "options(warn=2); install.packages('knitr');" && rm -rf /tmp/*
#RUN R -e "options(warn=2); install.packages('mlr');" && rm -rf /tmp/*
#RUN R -e "options(warn=2); install.packages('DT');" && rm -rf /tmp/*
#RUN R -e "options(warn=2); install.packages('Rcrawler');" && rm -rf /tmp/*

# Install a bunch of python3 packages for stuff and things
# TODO: requirements.txt

RUN python3 -m pip install matplotlib scipy numpy pandas bokeh patsy nltk tqdm h5py beautifulsoup4 cython scikit-learn

# Gives users access to R's system installation directory

ENV CHOWN_EXTRA "${CHOWN_EXTRA},/usr/local/lib/R/site-library/"
USER ${NB_USER}

### ==== MATLAB TARGET

FROM jupyter as matlab
LABEL maintainer="Mike Robeson <mrobeson@dundee.ac.uk>"

USER root

# Install the pyython engine
# https://uk.mathworks.com/help/matlab/matlab-engine-for-python.html
# https://github.com/calysto/matlab_kernel

RUN cd /opt/matlab/*/extern/engines/python/ \
 && python3 setup.py install
RUN python3 -m pip install matlab_kernel

# Set up the licensing.
# See "Network License" under "Run Options" from here:
# https://uk.mathworks.com/help/cloudcenter/ug/matlab-deep-learning-container-on-dgx.html

USER $NB_USER:users
ARG MLM_LICENSE
ENV MLM_LICENSE_FILE=$MLM_LICENSE

### ==== PYTORCH TARGET

FROM jupyter as pytorch
LABEL maintainer="Mike Robeson <mrobeson@dundee.ac.uk>"

# Hack the path because pytorch base image uses conda
# If the Conda path is preprended, conda packages will be preferred
# and we don't want that at build time

ENV PATH="/usr/local/nvidia/bin:/usr/local/cuda/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/opt/conda/bin:"

# TODO: Vision requires torch version >= 1.4
# Do *not* run `--upgrade` here as it will upgrade pytorch.
#USER root
#RUN python3 -m pip install torchvision torchaudio
#USER $NB_USER:users

### === TENSORFLOW TARGET

FROM jupyter as tensorflow
LABEL maintainer="Mike Robeson <mrobeson@dundee.ac.uk>"

# Force users to only user as much GPU memory as their graph actualy needs
# Otherwise it's 1 active tf user session per GPU.

ENV TF_FORCE_GPU_ALLOW_GROWTH true

### === CUSTOM TARGET

# Use this comamnd to build a custom image:
# DOCKER_BUILDKIT=1 docker build \
#    -t uodcvip/<image-name>:<tag> \
#    --build-arg BASE_CONTAINER=<original-image>:<tag> \
#    -f <path/to/custom>/Dockerfile \
#    --target custom \
#    .

FROM jupyter as custom
USER ${NB_USER}:users
