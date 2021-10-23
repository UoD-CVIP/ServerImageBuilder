#!/usr/bin/env bash

set -e

function info () {
  echo "$(date) --- ${1}" | logger
}

function logger () {
  tee build.log
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
      --no-cache \
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

    info "+ Cleaning up"
    info "++ Pruning"
    docker container prune -f
    docker image prune -f

    info "++ Removing"
    docker image rm -f ${CVIP_IMAGE}
    docker image rm -f ${BASE_IMAGE}

    info "++ Lingering image clean up"
    for image in $(docker images | tail -n+2 | awk '{print $3}' | xargs)
    do
      docker rm -f $image
    done

    info "++ System clean up"
    docker builder prune -f
    docker system prune -f
    info "+ Finished clean up"

  done
}

function build_setup () {
    ## Run the image builds for a framework

    if [[ -z ${BUILD_TYPE} ]]
    then
        echo "Please provide the file extension for the images to build (*.txt.???)."
        exit 100
    fi
    if [[ ${FRAMEWORK} == "cpu" ]]
    then
        export BASE_IMAGES=$( populate_image_list ./images/base/cpu_image_tags.txt.${BUILD_TYPE} "jupyter/datascience-notebook" )
        LICENSE=""
    elif [[ ${FRAMEWORK} == "java" ]]
    then
        export BASE_IMAGES=$( populate_image_list ./images/base/java_image_tags.txt.${BUILD_TYPE} "jbindinga/java-notebook" )
        LICENSE=""
    elif [[ ${FRAMEWORK} == "tensorflow" ]]
    then
        export BASE_IMAGES=$( populate_image_list ./images/base/tensorflow_image_tags.txt.${BUILD_TYPE} "tensorflow/tensorflow" )
        LICENSE=""
    elif [[ ${FRAMEWORK} == "rapidsai" ]]
    then
        export BASE_IMAGES=$( populate_image_list ./images/base/rapidsai_image_tags.txt.${BUILD_TYPE} "ubuntu" )
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
    system_cleanup
}

function system_cleanup () {
    docker container prune -f
    docker image prune -f
    docker builder prune -f
}

if [[ ${2} == "all" ]]
then
  export ALL="tensorflow pytorch rapidsai cpu java"
  for framework in ${ALL}
  do
        export BUILD_TYPE=${1}
        export FRAMEWORK=${framework}
        export LICENSE=${3}
        build_setup
  done
else
        export BUILD_TYPE=${1}
        export FRAMEWORK=${2}
        export LICENSE=${3}
        build_setup
fi
system_cleanup
