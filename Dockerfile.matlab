FROM tmp/jupyter

LABEL maintainer="Mike Robeson <mrobeson@dundee.ac.uk>"

USER root

RUN cd /opt/matlab/*/extern/engines/python/ && python3 setup.py install
RUN python3 -m pip install matlab_kernel

USER $NB_USER:users

ARG MLM_LICENSE
ENV MLM_LICENSE_FILE=$MLM_LICENSE

RUN echo $MLM_LICENSE_FILE
