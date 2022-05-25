#!/bin/bash

LOG_FILE=/tmp/openshift-$(date '+%d-%m-%Y-%H-%M-%S').log
rm -f $LOG_FILE
touch /tmp/openshift-$(date '+%d-%m-%Y-%H-%M-%S').log
source ./input_file

function statusCheck() {
  current_date=$(date '+%d/%m/%Y %H:%M:%S')
  if [ $1 -eq 0 ]; then
    echo  "[INFO] ${current_date} $2"
  else
    echo  "[ERROR] ${current_date} $2"
    exit 1
  fi
}

function printstars(){
  echo "******************************$1***************************************" >> $LOG_FILE
}

function pull_image () {
  aws ecr-public get-login-password --region us-east-1 | docker login --username AWS --password-stdin public.ecr.aws/g7v6l0u0 > /dev/null 2>&1
  docker pull public.ecr.aws/g7v6l0u0/openshift/origin-release:${IMAGE_TAG} >> $LOG_FILE 2>&1
  statusCheck $? "Pulled docker image ${IMAGE_TAG}"
}

function install_openshift_cli(){
      if [ `command -v oc | wc -l` -eq 0 ];
      then
        rm -rf oc
        git clone git@github.com:openshift/oc.git > /dev/null 2>&1
        pushd oc > /dev/null 2>&1
        make build > /dev/null 2>&1
        statusCheck $? "Built oc binary"
        sudo ./oc /usr/bin/oc /dev/null 2>&1
        popd
      fi
}

function install_ccoctl(){
  if [ `command -v ccoctl | wc -l` -eq 0 ];
  then
    rm -rf cloud-credential-operator
    git clone git@github.com:openshift/cloud-credential-operator.git > /dev/null 2>&1
    statusCheck $? "Cloned cloud-credential-operator repository"
    pushd cloud-credential-operator > /dev/null 2>&1
    make build > /dev/null 2>&1
    statusCheck $? "Built ccoctl binary"
    sudo cp ./ccoctl /usr/bin/ccoctl > /dev/null 2>&1
    popd
  fi
}

function install_openshift_installer(){
    if [ ! -d openshift-installer ];then
      git clone git@github.com:nutanix-cloud-native/openshift-installer.git > /dev/null 2>&1
      statusCheck $? "Cloned install openshift-installer repository"
    fi    
    pushd openshift-installer > /dev/null 2>&1
    git checkout ${INSTALLER_BRANCH} > /dev/null 2>&1
    statusCheck $? "Checkout branch to ${INSTALLER_BRANCH}"
    ./hack/build.sh > /dev/null 2>&1
    sudo cp ./bin/openshift-install /usr/bin/openshift-install > /dev/null 2>&1
    statusCheck $? "Built openshift-install binary"
    popd
}

function create_openshift_cluster(){
    rm -rf $HOME/.nutanix
    mkdir -p $HOME/.nutanix 
    cat <<EOF >>$HOME/.nutanix/credentials
credentials:
- type: basic_auth
  data:
    prismCentral:
      username: ${PRISM_CENTRAL_USER}
      password: ${PRISM_CENTRAL_PASSWORD}
EOF
    statusCheck $? "Created  $HOME/.nutanix/credentials file"
    rm -rf binary
    mkdir binary
    pushd binary
    oc adm release extract --credentials-requests --cloud=nutanix --to=. public.ecr.aws/g7v6l0u0/openshift/origin-release:${IMAGE_TAG} 
    statusCheck $? "Credentials request object created"
    ccoctl nutanix create-shared-secrets --credentials-requests-dir=. --output-dir=. > /dev/null 2>&1
    statusCheck $? "Shared secrets  created"
    export OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE=public.ecr.aws/g7v6l0u0/openshift/origin-release:${IMAGE_TAG}
    cat <<EOF >>install-config.yaml
apiVersion: v1
baseDomain: ntnxsherlock.com
compute:
- architecture: amd64
  hyperthreading: Enabled
  name: worker
  platform: {}
  replicas: 3
controlPlane:
  architecture: amd64
  hyperthreading: Enabled
  name: master
  platform: {}
  replicas: 3
credentialsMode: Manual
metadata:
  name: ${CLUSTER_NAME}
networking:
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  machineNetwork:
  - cidr: 10.0.0.0/16
  networkType: OpenShiftSDN
  serviceNetwork:
  - 172.30.0.0/16
platform:
  nutanix:
    clusterOSImage: "https://ntnx-openshift-rhcos.s3.us-west-2.amazonaws.com/rhcos-411.85.202205171904-0-nutanix.x86_64.qcow2"
    apiVIP: ${API_VIP}
    ingressVIP: ${INGRESS_VIP}
    prismCentral:
      endpoint:
        address: ${PRISM_CENTRAL_END_POINT}
        port: 9440
      password: ${PRISM_CENTRAL_PASSWORD}
      username: ${PRISM_CENTRAL_USER}
    prismElements:
    - endpoint:
        address: ${PRISM_ELEMENT_IP}
        port: 9440
      uuid: 0005b0f1-8f43-a0f2-02b7-3cecef193712
    subnetUUIDs:
    - c7938dc6-7659-453e-a688-e26020c68e43
publish: External
pullSecret: ${PULL_SECRET}
sshKey: |
  ${SSH_PUBLIC_KEY}
EOF
    statusCheck $? "Created install-config.yaml file"
    printstars "openshift-install create manifests"
    openshift-install create manifests --log-level=debug >> ${LOG_FILE} 2>&1
    statusCheck $? "Created  manifests folder"
    printstars "openshift-install create ignition-configs"
    openshift-install create ignition-configs --log-level=debug >> ${LOG_FILE} 2>&1
    statusCheck $? "Created  ignition config yaml files"
    printstars "openshift-install create cluster"
    openshift-install create cluster --log-level=debug >> ${LOG_FILE} 2>&1
    statusCheck $? "Created  cluster , logs saved to ${LOG_FILE}" 
    popd
}

function destroy_cluster()
{  
  if [ ! -f binary/auth/kubeconfig ];then
      if [ -z $1 ];
      then
      statusCheck 1 "Usage : main destroy_cluster path_kubeconfig_file"
      exit 
      fi
  fi
  pushd binary > /dev/null 2>&1
  export KUBECONFIG=`pwd`/binary/auth/kubeconfig
  openshift-install destroy cluster --log-level=debug >> ${LOG_FILE} 2>&1
  statusCheck $? "Cluster deleted, logs saved to ${LOG_FILE}" 
  popd
  pushd openshift-installer 
  git clean -xdf > /dev/null 2>&1
  popd
}

function deploy_origin_repository()
{
  if [ `command -v origin | wc -l` -eq 0 ];
  then
    rm -rf origin
    git clone "https://github.com/openshift/origin.git" > /dev/null 2>&1
    pushd ./origin > /dev/null 2>&1
    go mod tidy && go mod vendor > /dev/null 2>&1
    make > /dev/null 2>&1
    statusCheck $? "Cloned origin repository"
    popd
  fi
}

function deploy_csi_operator()
{
   if [ ! -f binary/auth/kubeconfig ];then
      if [ -z $1 ];
      then
      statusCheck 1 "Usage : main  path_kubeconfig_file"
      exit 
      fi
  else
    export KUBECONFIG=`pwd`/binary/auth/kubeconfig   
  fi 
}

function send_kubeconfig_slack()
{
  path_kubeconfig_file=`pwd`/binary/auth/kubeconfig
  if [ -f $path_kubeconfig_file ];then
      curl -F file=@binary/auth/kubeconfig -F "initial_comment=Here is the Kubeconfig file , INSTALLER_BRANCH=$INSTALLER_BRANCH and IMAGE_TAG=$IMAGE_TAG" -F channels=C01UE7XQ95E -H "Authorization: Bearer xoxb-2172428722-3547239687975-JqvTUzCcpB8ULNs70i4RKJk8" https://slack.com/api/files.upload
      statusCheck $? "Sent Kube config file to Slack channel"
  else
     statusCheck 1 "Kube config file not present."
  fi
}

if [ -z "$PRISM_CENTRAL_USER" ]
then
  statusCheck 1 " Environment variable  PRISM_CENTRAL_USER is not defined."
  exit 1
fi

if [ -z "$PRISM_CENTRAL_PASSWORD" ]
then
  statusCheck 1 " Environment variable  PRISM_CENTRAL_PASSWORD is not defined."
  exit 1
fi

if [ -z "$INSTALLER_BRANCH" ]
then
  statusCheck 1 " Environment variable  INSTALLER_BRANCH is not defined."
  exit 1
fi

if [ -z "$API_VIP"  ]
then
  statusCheck 1 " Environment variable  API_VIP is not defined."
  exit 1
fi

if [ -z "$INGRESS_VIP" ]
then
  statusCheck 1 " Environment variable  INGRESS_VIP is not defined."
  exit 1
fi

if [ -z "$PRISM_CENTRAL_END_POINT" ]
then
  statusCheck 1 " Environment variable  PRISM_CENTRAL_END_POINT is not defined."
  exit 1
fi

function create_cluster()
{
  pull_image
  install_openshift_installer
  create_openshift_cluster
  send_kubeconfig_slack
}

statusCheck 0 "INSTALLER_BRANCH=$INSTALLER_BRANCH"
statusCheck 0 "API_VIP=$API_VIP"
statusCheck 0 "INGRESS_VIP=$INGRESS_VIP"
statusCheck 0 "PRISM_CENTRAL_END_POINT=$PRISM_CENTRAL_END_POINT"
statusCheck 0 "SSH_PUBLIC_KEY=`echo $SSH_PUBLIC_KEY| cut -d " " -f1,3`"
statusCheck 0 "IMAGE_TAG=$IMAGE_TAG"

case $1 in
  create_cluster)
    create_cluster
    ;;

  destroy_cluster)
    destroy_cluster
    ;;
  *)
    statusCheck 1 " Usage: main.sh destroy_cluster or main.sh create_cluster "
    ;;
esac
