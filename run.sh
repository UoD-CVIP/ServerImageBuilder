#!/usr/bin/env bash

function log () {
  echo $(date)" --- ${1}" >> build.log
}

function remove_images () {
  docker rmi $( docker images | grep ${1} | awk '{print $3}')
}

declare -a TF_BASE_IMAGES
TF_VERSIONS=$(cat ./tensorflow_versions.txt | sort -V)

declare -a PT_BASE_IMAGES
PYTORCH_VERSIONS=$(cat ./pytorch_image_tags.txt | sort -V)

declare -a ML_BASE_IMAGES
MATLAB_VERSIONS=$(cat ./matlab_image_tags.txt | sort)

### Tensorflow images
for TF_VERSION in ${TF_VERSIONS}
do
  IMAGE="tensorflow/tensorflow:${TF_VERSION}-gpu-py3"
  BASE_IMAGES="${BASE_IMAGES} ${IMAGE}"
done

### Pytorch images
for TAG in ${PYTORCH_VERSIONS}
do
  IMAGE="pytorch/pytorch:${TAG}"
  BASE_IMAGES="${BASE_IMAGES} ${IMAGE}"
done

for TAG in ${MATLAB_VERSIONS}
do
  IMAGE="nvcr.io/partners/matlab:${TAG}"
  BASE_IMAGES="${BASE_IMAGES} ${IMAGE}"
done



## Run the image builds
for BASE_IMAGE in ${BASE_IMAGES}
do
  TAG=$(echo ${BASE_IMAGE} | cut -f2 -d":" | cut -f1 -d"-")
  FRAMEWORK=$( echo ${BASE_IMAGE} | cut -f1 -d"/")
  CVIP_TAG=$(echo ${TAG} | cut -f1 -d"-")
  CVIP_IMAGE=uodcvip/${FRAMEWORK}:${CVIP_TAG}

  docker pull ${BASE_IMAGE}

  docker build \
    --build-arg BASE_CONTAINER=${BASE_IMAGE} \
    -t ${CVIP_IMAGE} \
    ./Builds/ \
    && log "${CVIP_IMAGE} successful build from ${BASE_IMAGE}" \
    || log "${CVIP_IMAGE} failed build from ${BASE_IMAGE}"


  docker rm ${BASE_IMAGE}

  docker push ${CVIP_IMAGE} \
  && log "${CVIP_IMAGE} successful push" \
  || log "${CVIP_IMAGE} failed to push"

  # clean up
  docker container prune -f
  docker image prune -f

  ### Final clean up in case of a failed build
  remove_images tensorflow/tensorflow
  remove_images pytorch/pytorch

done

