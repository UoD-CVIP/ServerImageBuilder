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

####################################################################################################
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
    gcc \
    g++ \
    make \
    openssh-server \
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

# Use tini -s to sub reap when tini won't be running as PID 1 (we use --pid=host at runtime)
# use tini -g to process groups to make sure subprocess close on exit.
ENTRYPOINT ["/tini", "-g", "-s", "--"]

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

RUN sed -i /etc/skel/.bashrc \
    -e 's/^#force_color_prompt=yes/force_color_prompt=yes/' \
 && echo "alias pip3=/opt/conda/bin/pip" >> /etc/skel/.bashrc \
 && echo "alias pip=/opt/conda/bin/pip" >> /etc/skel/.bashrc

# Create NB_USER wtih name jovyan user with UID=1000 and in the 'users' group
# and make sure these dirs are writable by the `users` group.
# If this is the matlab image               ===> modify the existing `matlab` user
# elif this is an existing jupyter image    ===> add the jovyan user

RUN echo "auth requisite pam_deny.so" >> /etc/pam.d/su \
   && sed -i.bak -e 's/^%sudo/#%sudo/' /etc/sudoers \
   && if [ $(grep -c '^matlab' /etc/passwd) -eq 1 ] \
      ; then usermod -l $NB_USER -u $NB_UID -g $NB_GID -m -d /home/$NB_USER -s $SHELL matlab \
      ; fi \
   && if [ $(grep -c '^jovyan' /etc/passwd) -eq 0 ] \
      ; then useradd -m -s $SHELL -N -u $NB_UID $NB_USER \
      ; fi \
   && chmod g+w /etc/passwd

# Let user accounts in the "users" group to use sudo for apt commands ONLY.

RUN mkdir -p /etc/sudoers.d/ \
 && echo '%users ALL = NOPASSWD : /usr/bin/apt-get , /usr/bin/apt, /usr/bin/apt-key, /usr/bin/add-apt-repository' > /etc/sudoers.d/apt \
 && chmod 0444 /etc/sudoers.d/apt

# Additional directories can be added to CHOWN_EXTRA to give shared user access
# Note that CHOWN_EXTRA is only called if the container strarts as root.
# See: ServerConfig/jupyyterhub/config.py

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

USER root

# setup custom bashrc for CVIP
COPY Jupyter/bashrc /tmp/bashrc
RUN if [ -f /etc/bash.bashrc ] \
  ; then \
      cp /etc/bash.bashrc /etc/bash.bashrc.bak \
      && cp -f /tmp/bashrc /etc/bash.bashrc \
      && cat /etc/bash.bashrc.bak >> /etc/bash.bashrc \
  ; else \
    cp -f /tmp/bashrc /etc/bash.bashrc \
  ; fi \
  && rm -f /tmp/bashrc

####################################################################################################
# Install conda if the base image doesn't already have it
# make sure to force re-install the correct python version from the existing one in the docker image
# N.B. https://stackoverflow.com/a/57770483
FROM base as conda
ADD https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh /tmp/miniconda.sh
RUN if [ ! -d /opt/conda ] \
 ; then \
     chmod +x /tmp/miniconda.sh \
     && /tmp/miniconda.sh -b -p /opt/conda \
     && export PY_VERSION=$(python3 --version | cut --d=' ' -f2)\
     && /opt/conda/bin/conda install --force-reinstall -q -y python=${PY_VERSION} \
     && /opt/conda/bin/conda clean -yaq \
 ; fi \
 && rm /tmp/miniconda.sh

ENV CONDA_BIN="/opt/conda/bin/conda"
ENV CONDA_PIP="/opt/conda/bin/pip"
ENV SYSTEM_PIP="python3 -m pip"


####################################################################################################
# Install jupyter
FROM conda AS jupyter
LABEL maintainer="Mike Robeson <mrobeson@dundee.ac.uk>"

# Install python requirements for jupyter
# -
# we have to force-reinstall because there's a nasty bug with python3.6 and the prompt_toolkit
# package
# -
# Also add the bash kernel
# https://github.com/takluyver/bash_kernel

ADD Jupyter/jupyterhub-requirements.txt /tmp/
RUN ${CONDA_PIP} install -r /tmp/jupyterhub-requirements.txt \
 && ${CONDA_PIP} install --force-reinstall prompt-toolkit ipython \
 && ${CONDA_BIN} install -yq -c conda-forge bash_kernel \
 && ${CONDA_BIN} clean -yaq


####################################################################################################
### 3. =========== BUILD TARGETS ============ ####


####################################################################################################
# ===> jupyter/datascience
FROM base as cpu
USER root
RUN conda install -yq -c conda-forge xeus-cling
USER ${NB_USER}


####################################################################################################
# ===> jbindinga/java-notebook
FROM base as java
USER root
RUN rm -rf /home/${NB_USER}/.jupyter/
USER ${NB_USER}

####################################################################################################
# ===> nvidia/partners/matlab
FROM jupyter as matlab
LABEL maintainer="Mike Robeson <mrobeson@dundee.ac.uk>"

USER root

# Install the pyython engine
# https://uk.mathworks.com/help/matlab/matlab-engine-for-python.html
# https://github.com/calysto/matlab_kernel

RUN cd /opt/matlab/*/extern/engines/python/ \
 && /opt/conda/bin/python3 setup.py install
RUN ${CONDA_BIN} install -c conda-forge matlab_kernel

# Set up the licensing.
# See "Network License" under "Run Options" from here:
# https://uk.mathworks.com/help/cloudcenter/ug/matlab-deep-learning-container-on-dgx.html

USER $NB_USER:users
ARG MLM_LICENSE
ENV MLM_LICENSE_FILE=$MLM_LICENSE

####################################################################################################
# ===> pytorch/pytorch
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
USER $NB_USER:users

####################################################################################################
# ===> ubuntu into rapidsai
FROM jupyter as rapidsai
LABEL maintainer="Mike Robeson <mrobeson@dundee.ac.uk>"
USER root

RUN ${CONDA_BIN} install \
 -c rapidsai \
 -c nvidia \
 -c conda-forge\
 rapids-blazing=21.06 python=3.8 cudatoolkit=11.2 \
 && ${CONDA_BIN} clean -yaq

ENV NVIDIA_DRIVER_CAPABILITIES="compute,utility"
ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_REQUIRE_CUDA="cuda>=11.2"
USER $NB_USER:users

####################################################################################################
# ===> tensorflow/tensorflow

FROM jupyter as tensorflow
LABEL maintainer="Mike Robeson <mrobeson@dundee.ac.uk>"

# we need to get all the tensorflow requirements from system pip, then reinstall with conda pip
# because tensorflow packages are unreliably added to conda and we can't link conda to system pip
# N.B. Only reinstall the "tensor" packages to keep dependencies constraints as soft as possible
USER root
RUN python3 -m pip list --format freeze | grep tensor > /tmp/pip.txt \
 && python3 -m pip uninstall -y -r /tmp/pip.txt \
 && ${CONDA_PIP} install --force-reinstall -r /tmp/pip.txt \
 && rm -rf /tmp/pip.txt \
 && ${CONDA_BIN} clean -a -y

USER ${NB_USER}:users
# Force users to only user as much GPU memory as their graph actualy needs
# Otherwise it's 1 active tf user session per GPU.
ENV TF_FORCE_GPU_ALLOW_GROWTH=true

####################################################################################################
# ===> custom

# Use this comamnd to build a custom image:
# DOCKER_BUILDKIT=1 docker build \
#    -t uodcvip/<image-name>:<tag> \
#    --build-arg BASE_CONTAINER=<original-image>:<tag> \
#    -f <path/to/custom>/Dockerfile \
#    --target custom \
#    .

FROM jupyter as custom
USER ${NB_USER}:users
