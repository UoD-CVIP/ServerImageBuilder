#!/usr/bin/env bash

function info () {
  echo $(date)" --- ${1}" | logger
}

function logger () {
  tee build.log
}

function remove_images () {
  info "Attempting to remove image ${1}"
  docker rmi $( docker images | grep ${1} | awk '{print $3}') \
    && info "${1} image removed" \
    || info "${1} image NOT removed, trying to force..." \
  || docker rmi -f $( docker images | grep ${1} | awk '{print $3}') \
    && info "${1} image removed" \
    || info "${1} image not removed, you'll have to remove it manually."
}

function clean_up_images () {
  info "Running clean up"
  docker container prune -f
  docker image prune -f
  for image in ${@}
  do
    remove_images $image
  done
  docker builder prune --force
  info "Finished clean up"
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

function build_loop () {
  info "++++ Starting build process."
  for BASE_IMAGE in ${BASE_IMAGES}
  do
    export TAG=$(echo ${BASE_IMAGE} | cut -f2 -d":" | cut -f1 -d"-")
    export CVIP_TAG=$(echo ${TAG} | cut -f1 -d"-")
    export CVIP_IMAGE=uodcvip/${FRAMEWORK}:${CVIP_TAG}

    info "++ Building ${CVIP_IMAGE} from ${BASE_IMAGE}"
    DOCKER_BUILDKIT=1 docker build \
      --rm \
      --pull \
      --target ${FRAMEWORK} \
      --tag ${CVIP_IMAGE} \
      --build-arg BASE_CONTAINER=${BASE_IMAGE} \
      --build-arg MLM_LICENSE="${LICENSE}" \
      ./ \
    && info "+ Build SUCCESS for ${CVIP_IMAGE}" \
    || info "+ Build FAILURE for ${CVIP_IMAGE}"

    docker push ${CVIP_IMAGE} \
    && info "+ ${CVIP_IMAGE} push success" \
    || info "+ ${CVIP_IMAGE} push failure"

    clean_up_images ${BASE_IMAGE}

  done
}


## Run the image builds for all frameworks
export BUILD_TYPE=${1}
export FRAMEWORK=${2}
export LICENSE=${3}

if [[ -z ${BUILD_TYPE} ]]
then
    echo "Please provide the file extension for the images to build (*.txt.???)."
    exit 100
fi
if [[ ${FRAMEWORK} == "cpu" ]]
then
    export BASE_IMAGES=$( populate_image_list ./images/base/cpu_image_tags.txt.${BUILD_TYPE} "ubuntu" )
    LICENSE=""

elif [[ ${FRAMEWORK} == "tensorflow" ]]
then
    export BASE_IMAGES=$( populate_image_list ./images/base/tensorflow_image_tags.txt.${BUILD_TYPE} "tensorflow/tensorflow" )
    LICENSE=""

elif [[ ${FRAMEWORK} == "pytorch" ]]
then
    export BASE_IMAGES=$( populate_image_list ./images/base/pytorch_image_tags.txt.${BUILD_TYPE} "pytorch/pytorch" )
    LICENSE=""

elif [[ ${FRAMEWORK} == "matlab" ]]
then
    export BASE_IMAGES=$( populate_image_list ./images/base/matlab_image_tags.txt.${BUILD_TYPE} "nvcr.io/partners/matlab" )
    if [[ ${LICENSE} == "" ]]
    then
      echo "For a 'matlab' build you need to provide a valid network license address."
      exit 100
   fi
else
    echo "${FRAMEWORK} does not exist."
    exit 100
fi

build_loop
