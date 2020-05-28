#!/usr/bin/env bash

function log () {
  echo $(date)" --- ${1}" >> build.log
}

function remove_images () {
  docker rmi $( docker images | grep ${1} | awk '{print $3}')
}

function populate_image_list () {
  declare -a BASE
  local VERS=$(cat ${1} | sort -V)
  for VER in ${VERS}
  do
    local IMAGE="${2}:${VER}"
    local BASE="${BASE} ${IMAGE}"
  done
  echo ${BASE}
}

## Run the image builds for all frameworks
for FRAMEWORK in ${@}
do

  log "Building ${FRAMEWORK} images."
  if [[ ${FRAMEWORK} == "tensorflow" ]]
  then
    BASE_IMAGES=$( populate_image_list ./tensorflow_image_tags.txt.prod "tensorflow/tensorflow" )
    BUILD_DIR=./TensorflowBuild
    MATLAB_BUILD_FLAG=false

  elif [[ ${FRAMEWORK} == "pytorch" ]]
  then
    BASE_IMAGES=$( populate_image_list ./pytorch_image_tags.txt.prod "pytorch/pytorch" )
    BUILD_DIR=./PyTorchBuild
    MATLAB_BUILD_FLAG=false

  elif [[ ${FRAMEWORK} == "matlab" ]]
  then
    BASE_IMAGES=$( populate_image_list ./matlab_image_tags.txt.prod "nvcr.io/partners/matlab" )
    BUILD_DIR=./MatlabBuild
    MATLAB_BUILD_FLAG=true
  else
    exit 1
  fi

  ### Iterate through each image we need to build for each of ${IMAGES}
  for BASE_IMAGE in ${BASE_IMAGES}
  do

    if [[ ${FRAMEWORK} == "matlab" ]]
    then
      echo "+_+ LIC: ${2}"
      LICENSE="${2}"
    else
      LICENSE=""
    fi
    #then
    #  FRAMEWORK=$( echo ${BASE_IMAGE} | cut -f3 -d"/")
    #else
    #  FRAMEWORK=$( echo ${BASE_IMAGE} | cut -f1 -d"/")
    #fi

    TAG=$(echo ${BASE_IMAGE} | cut -f2 -d":" | cut -f1 -d"-")
    CVIP_TAG=$(echo ${TAG} | cut -f1 -d"-")
    CVIP_IMAGE=uodcvip/${FRAMEWORK}:${CVIP_TAG}

    log "Building ${CVIP_IMAGE} from ${BASE_IMAGE}"

    docker pull ${BASE_IMAGE} \
    && log "${BASE_IMAGE} pull success" \
    || log "${BASE_IMAGE} pull failure" \

    ### Start the build process
    # === If any one of these commands fails, all subsequent build stages *must* fail
    # === Hence the chaining of all docker commands below
    docker build \
      --rm \
      --build-arg BASE_CONTAINER=${BASE_IMAGE} \
      -t tmp/base \
      ./BaseBuild/ \
    && log "${CVIP_IMAGE} BaseBuild success" \
    || log "${CVIP_IMAGE} BaseBuild failure" \
  &&
    docker build \
      --rm \
      --build-arg MATLAB_BUILD_ARG=${MATLAB_BUILD_FLAG} \
      -t tmp/jupyter \
     ./JupyterBuild/ \
    && log "${CVIP_IMAGE} JupyterBuild success" \
    || log "${CVIP_IMAGE} JupyterBuild failure" \
  &&
    if [[ ${FRAMEWORK} == "matlab" ]]
    then
      docker build \
        --rm \
        --build-arg MLM_LICENSE="${LICENSE}" \
        -t ${CVIP_IMAGE} \
        ${BUILD_DIR}
    else
      docker build \
        --rm \
        -t ${CVIP_IMAGE} \
        ${BUILD_DIR}
    fi && log "${CVIP_IMAGE} ${BUILD_DIR} success" \
        || log "${CVIP_IMAGE} ${BUILD_DIR} failure" \
  && \
    docker push ${CVIP_IMAGE} \
    && log "${CVIP_IMAGE} push success" \
    || log "${CVIP_IMAGE} push failure"

    # clean up
    docker container prune -f
    docker image prune -f

    remove_images tmp/jupyter
    remove_images tmp/base
    remove_images ${FRAMEWORK}

  done
done
### Final clean up in case of a failed build
remove_images tensorflow/tensorflow
remove_images pytorch/pytorch
remove_images nvcr.io/partners/matlab

