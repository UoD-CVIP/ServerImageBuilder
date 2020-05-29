# See here for more information on multi stage builds with BUILDKIT
# https://docs.docker.com/develop/develop-images/build_enhancements/#to-enable-buildkit-builds
# https://www.docker.com/blog/advanced-dockerfiles-faster-builds-and-smaller-images-using-buildkit-and-multistage-builds/
# https://github.com/docker/cli/issues/1134#issuecomment-405946645

### === Base image

# Copyright (c) Jupyter Development Team.
# Distributed under the terms of the Modified BSD License.
# Ubuntu 18.04 (bionic) from 2019-06-12
# https://github.com/tianon/docker-brew-ubuntu-core/commit/3c462555392cb188830b7c91e29311b5fad90cfe
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
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

# https://joshtronic.com/2018/05/08/how-to-install-nodejs-10-on-ubuntu-1804-lts/
# Install nodejs 10.0
RUN curl -sL https://deb.nodesource.com/setup_10.x | bash -
RUN apt install -yqq nodejs

# Install yarn dependency
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
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

RUN apt autoremove -yqq

### ==== Jupyter Base image set up
# Copyright (c) Jupyter Development Team.
# Distributed under the terms of the Modified BSD License.
FROM base AS jupyter
LABEL maintainer="Mike Robeson <mrobeson@dundee.ac.uk>"

# N.B. we have to use the `--force` flag because npm doesn't trust it's users
RUN npm install -g configurable-http-proxy \
 && npm cache clean --force

ENV TINI_VERSION v0.18.0
ADD https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini /tini
RUN chmod +x /tini

# Install python requirements for jupyter
# This includes the jupyterhub notebook server, jupyter lab etc.
ADD Jupyter/jupyterhub-requirements.txt /tmp/

RUN curl https://bootstrap.pypa.io/get-pip.py -o /get-pip.py
RUN python3 /get-pip.py --force-reinstall
RUN python3 -m pip install -U -r /tmp/jupyterhub-requirements.txt \
 && rm -f /tmp/*-requirements.txt

# Configure container environment
# N.B. We actually *need* to use the jovyan `user` at build time.
# The `start.sh` will actually overide the user when we use SystemUserSpawner
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
# If this is the matlab image then modify the existing `matlab` user
RUN echo "auth requisite pam_deny.so" >> /etc/pam.d/su \
   && sed -i.bak -e 's/^%admin/#%admin/' /etc/sudoers \
   && sed -i.bak -e 's/^%sudo/#%sudo/' /etc/sudoers \
   && if [ $(grep -c '^matlab' /etc/passwd) -eq 1 ] \
      ; then usermod -l $NB_USER -u $NB_UID -g $NB_GID -m -d /home/$NB_USER -s $SHELL matlab \
      ; else useradd -m -s $SHELL -N -u $NB_UID $NB_USER \
      ; fi \
   && chmod g+w /etc/passwd 

# Set up the user's environment
USER $NB_USER:users
ARG PYTHON_VERSION=default
ENV JUPYTER_ENABLE_LAB=true
WORKDIR $HOME

# Configure container startup and settings
EXPOSE 8888
ENTRYPOINT ["/tini", "-g", "--"]
CMD ["start-notebook.sh"]

# Add local files as late as possible to avoid cache busting
COPY Jupyter/start.sh /usr/local/bin/
COPY Jupyter/start-notebook.sh /usr/local/bin/
COPY Jupyter/start-singleuser.sh /usr/local/bin/

### =========== BUILD TARGETS ============ ####

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
FROM jupyter AS tensorflow
LABEL maintainer="Mike Robeson <mrobeson@dundee.ac.uk>"

# Force users to only user as much GPU memory as their graph actualy needs
# Otherwise it's 1 active tf user session per GPU.
ENV TF_FORCE_GPU_ALLOW_GROWTH true

