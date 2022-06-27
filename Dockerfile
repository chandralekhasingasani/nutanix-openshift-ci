FROM centos:7

ADD ./ccoctl .
RUN mv ccoctl /usr/bin/ccoctl
ADD ./oc /
RUN mv oc /usr/bin/oc
ADD ./openshift-install /
RUN mv openshift-install /usr/bin/openshift-install
ADD main.sh main.sh
ADD input_file input_file
CMD sh main.sh create_cluster
