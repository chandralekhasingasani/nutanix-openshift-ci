#!/bin/bash

LOG_FILE=/tmp/openshift-$(date '+%d-%m-%Y-%H-%M-%S').log
rm -f $LOG_FILE
touch /tmp/openshift-$(date '+%d-%m-%Y-%H-%M-%S').log
RELEASE_IMAGE=`curl  https://amd64.ocp.releases.ci.openshift.org/api/v1/releasestream/4.11.0-0.nightly/latest | jq '.pullSpec' | xargs`

function install_tools() {
  curl -fsSL https://get.docker.com/ | sh; systemctl start docker;systemctl status docker;systemctl enable docker ; yum install jq -y
  yum install unzip wget -y; wget https://awscli.amazonaws.com/awscli-exe-linux-x86_64-2.6.1.zip; unzip awscli-exe-linux-x86_64-2.6.1.zip; ./aws/install
  aws --profile default configure set aws_access_key_id $AWS_ACCESS_KEY
  aws --profile default configure set aws_secret_access_key $AWS_SECRET_KEY
}

function statusCheck() {
  current_date=$(date '+%d/%m/%Y %H:%M:%S')
  if [ $1 -eq 0 ]; then
    echo  "[INFO] ${current_date} $2"
  else
    echo  "[ERROR] ${current_date} $2"
    exit 1
  fi
}

function pull_image_redhat_latest () {
  oc login --token=${OAUTH_TOKEN} --server=https://api.ci.l2s4.p1.openshiftapps.com:6443 > /dev/null 2>&1
  oc registry login > /dev/null 2>&1
  docker login registry.ci.openshift.org > /dev/null 2>&1
  statusCheck $? "docker login to registry.ci.openshift.org is successfull"
  docker pull ${RELEASE_IMAGE} >> $LOG_FILE 2>&1
  statusCheck $? "Pulled  image ${RELEASE_IMAGE}"
  aws ecr-public get-login-password --region us-east-1 | docker login --username AWS --password-stdin public.ecr.aws/g7v6l0u0 > /dev/null 2>&1
  statusCheck $? "docker login to  public.ecr.aws/g7v6l0u0/openshift/origin-release successfully"
  docker tag ${RELEASE_IMAGE} public.ecr.aws/g7v6l0u0/openshift/origin-release:nightly
  docker push public.ecr.aws/g7v6l0u0/openshift/origin-release:nightly
  statusCheck $? "Pushing image to AWS ECR."
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
        sudo cp ./oc /usr/bin/oc /dev/null 2>&1
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
    git clean -xdf
    git pull
    statusCheck $? "Checkout branch to ${INSTALLER_BRANCH}"
    sh ./hack/build.sh 
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
    oc adm release extract --credentials-requests --cloud=nutanix --to=. public.ecr.aws/g7v6l0u0/openshift/origin-release:nightly
    statusCheck $? "Credentials request object created"
    ccoctl nutanix create-shared-secrets --credentials-requests-dir=. --output-dir=. > /dev/null 2>&1
    statusCheck $? "Shared secrets  created"
    export OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE='public.ecr.aws/g7v6l0u0/openshift/origin-release:nightly'
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
    statusCheck 1 "Kubeconfig file not present under binary/auth/kubeconfig" 
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

function run_e2e_tests()
{
  if [ `command -v openshift-tests | wc -l` -eq 0 ];
  then
    rm -rf origin
    git clone "https://github.com/openshift/origin.git" > /dev/null 2>&1
    pushd ./origin > /dev/null 2>&1
    go mod tidy && go mod vendor > /dev/null 2>&1
    make > /dev/null 2>&1
    sudo mv ./openshift-tests /usr/bin/openshift-tests > /dev/null 2>&1
    statusCheck $? "Cloned origin repository"
    popd
  fi

  if [ ! -f binary/auth/kubeconfig ];then
    statusCheck 1 "Kubeconfig file not present under binary/auth/kubeconfig"   
  fi
  export KUBECONFIG=`pwd`/binary/auth/kubeconfig
  pushd binary
  openshift-tests run openshift/conformance/parallel -o parallel-conformance.log > /dev/null 2>&1
  statusCheck $? "E2e tests executed , logs saved to parallel-conformance.log file" 
  popd
}



function enable_ImageRegistry()
{
   if [ ! -f binary/auth/kubeconfig ];then      
      statusCheck 1 "Kubeconfig file not present under binary/auth/kubeconfig"
  else
    export KUBECONFIG=`pwd`/binary/auth/kubeconfig 
    pushd binary
cat > "image-registry-pvc.yaml" << EOF
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: image-registry-storage
  namespace: openshift-image-registry
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 100Gi
EOF
    oc delete -f image-registry-pvc.yaml -n openshift-image-registry > /dev/null 2>&1
    oc create -f image-registry-pvc.yaml -n openshift-image-registry > /dev/null 2>&1
    statusCheck $? "Created PVC named image-registry" 
    oc patch configs.imageregistry.operator.openshift.io/cluster --type=merge -p '{"spec":{"storage":{"pvc":{"claim":"image-registry-storage"}}}}' > /dev/null 2>&1
    oc patch config.imageregistry.operator.openshift.io/cluster --type=merge -p '{"spec":{"rolloutStrategy":"Recreate","replicas":1}}' > /dev/null 2>&1
    statusCheck $?  "Changed rollout strategy for Image Registry"
    oc patch configs.imageregistry.operator.openshift.io/cluster --type=merge -p '{"spec":{"managementState":"Managed"}}' > /dev/null 2>&1
    statusCheck $?  "Changing management state for Image Registry Operator"
    popd 
  fi 
}


function deploy_CSI_Operator()
{
  if [ ! -f binary/auth/kubeconfig ];then    
      statusCheck 1 "Kubeconfig file not present under binary/auth/kubeconfig"     
  else
    export KUBECONFIG=`pwd`/binary/auth/kubeconfig 
    pushd binary
    cat > "manifest_0000-nutanix-csi-crd-manifest.yaml" << EOF
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: nutanixcsistorages.crd.nutanix.com
spec:
  group: crd.nutanix.com
  names:
    kind: NutanixCsiStorage
    listKind: NutanixCsiStorageList
    plural: nutanixcsistorages
    singular: nutanixcsistorage
  scope: Namespaced
  versions:
  - name: v1alpha1
    schema:
      openAPIV3Schema:
        description: NutanixCsiStorage is the Schema for the nutanixcsistorages API
        properties:
          apiVersion:
            description: 'APIVersion defines the versioned schema of this representation
              of an object. Servers should convert recognized schemas to the latest
              internal value, and may reject unrecognized values. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#resources'
            type: string
          kind:
            description: 'Kind is a string value representing the REST resource this
              object represents. Servers may infer this from the endpoint the client
              submits requests to. Cannot be updated. In CamelCase. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds'
            type: string
          metadata:
            type: object
          spec:
            description: Spec defines the desired state of NutanixCsiStorage
            type: object
            x-kubernetes-preserve-unknown-fields: true
          status:
            description: Status defines the observed state of NutanixCsiStorage
            type: object
            x-kubernetes-preserve-unknown-fields: true
        type: object
    served: true
    storage: true
    subresources:
      status: {}
EOF
    oc apply -f manifest_0000-nutanix-csi-crd-manifest.yaml > /dev/null 2>&1
    statusCheck $? "Created nutanixcsistorages CRD"

    cat > "manifest_0001-nutanix-csi-ntnx-system-namespace.yaml" << EOF
apiVersion: v1
kind: Namespace
metadata:
  name: ntnx-system
EOF
    oc apply -f manifest_0001-nutanix-csi-ntnx-system-namespace.yaml > /dev/null 2>&1
    statusCheck $? "Created ntnx-system namespace"

    cat > "manifest_0002-nutanix-csi-ntnx-secret.yaml" << EOF
apiVersion: v1
kind: Secret
metadata:
  name: ntnx-secret
  namespace: ntnx-system
stringData:
  key: ${PRISM_ELEMENT_IP}:9440:${PE_USERNAME}:${PE_PASSWORD}
EOF
    oc apply -f manifest_0002-nutanix-csi-ntnx-secret.yaml > /dev/null 2>&1
    statusCheck $? "Created ntnx-secret secret"

    cat > "manifest_0003-nutanix-csi-operator-group.yaml" << EOF
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: ntnx-system-r8czl
  namespace: ntnx-system
spec:
  targetNamespaces:
    - ntnx-system
EOF
    oc apply -f manifest_0003-nutanix-csi-operator-group.yaml > /dev/null 2>&1
    statusCheck $? "Created Operator group ntnx-system-r8czl"

    cat > "manifest_0004-nutanix-csi-subscription.yaml" << EOF
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: nutanixcsioperator
  namespace: ntnx-system
spec:
  channel: stable
  name: nutanixcsioperator
  installPlanApproval: Automatic
  source: certified-operators
  sourceNamespace: openshift-marketplace
EOF
    oc apply -f manifest_0004-nutanix-csi-subscription.yaml > /dev/null 2>&1
    statusCheck $? "Created Subscription nutanixcsioperator"

    cat > "manifest_0005-nutanix-csi-storage.yaml" << EOF
apiVersion: crd.nutanix.com/v1alpha1
kind: NutanixCsiStorage
metadata:
  name: nutanixcsistorage
  namespace: ntnx-system
spec:
  namespace: ntnx-system
  tolerations:
    - key: "node-role.kubernetes.io/infra"
      operator: "Exists"
      value: ""
      effect: "NoSchedule"
EOF
    oc apply -f manifest_0005-nutanix-csi-storage.yaml > /dev/null 2>&1
    statusCheck $? "Created NutanixCsiStorage named nutanixcsistorage"

    cat > "manifest_0006-nutanix-csi-storage-class.yaml" << EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nutanix-volume
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: csi.nutanix.com
parameters:
  csi.storage.k8s.io/provisioner-secret-name: ntnx-secret
  csi.storage.k8s.io/provisioner-secret-namespace: ntnx-system
  csi.storage.k8s.io/node-publish-secret-name: ntnx-secret
  csi.storage.k8s.io/node-publish-secret-namespace: ntnx-system
  csi.storage.k8s.io/controller-expand-secret-name: ntnx-secret
  csi.storage.k8s.io/controller-expand-secret-namespace: ntnx-system
  csi.storage.k8s.io/fstype: ext4
  storageContainer: ${PE_STORAGE_CONTAINER}
  storageType: NutanixVolumes
allowVolumeExpansion: true
reclaimPolicy: Delete
EOF
    oc delete -f manifest_0006-nutanix-csi-storage-class.yaml > /dev/null 2>&1
    oc apply -f manifest_0006-nutanix-csi-storage-class.yaml > /dev/null 2>&1
    statusCheck $? "Created StorageClass named nutanix-volume"

    cat > "manifest_iscsid-enable-master.yaml" << EOF
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: master
  name: 99-master-ntnx-csi-enable-iscsid
spec:
  config:
    ignition:
      version: 3.2.0
    systemd:
      units:
      - enabled: true
        name: iscsid.service
EOF
    oc apply -f manifest_iscsid-enable-master.yaml > /dev/null 2>&1
    statusCheck $? "Set iscsid.service on the master to true"

cat > "manifest_iscsid-enable-worker.yaml" << EOF
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: worker
  name: 99-worker-ntnx-csi-enable-iscsid
spec:
  config:
    ignition:
      version: 3.2.0
    systemd:
      units:
      - enabled: true
        name: iscsid.service
EOF
    oc apply -f manifest_iscsid-enable-worker.yaml > /dev/null 2>&1
    statusCheck $? "Set iscsid.service on the worker to true"
    popd 
fi
}

function send_kubeconfig_slack()
{
  message=`awk '/Access/{x=NR+1}(NR<=x){print}' ${LOG_FILE}|cut -d "=" -f 3|xargs`
  path_kubeconfig_file=`pwd`/binary/auth/kubeconfig
  if [ -f $path_kubeconfig_file ];then
      curl -F file=@binary/auth/kubeconfig -F "initial_comment=Here is the Kubeconfig file , INSTALLER_BRANCH=$INSTALLER_BRANCH and RELEASE_IMAGE=${RELEASE_IMAGE} . ${message}" -F channels=C03L5TG925C -H "Authorization: Bearer xoxb-2172428722-3547239687975-JqvTUzCcpB8ULNs70i4RKJk8" https://slack.com/api/files.upload
      statusCheck $? "Sent Kube config file to Slack channel"
  else
     curl -X POST -H 'Content-type: application/json' --data "{
              \"text\": \"Cluster creation Failed , Please debug !!! \"}" https://hooks.slack.com/services/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
     statusCheck 1 "Kube config file not present."
  fi
}

source ./input_file
source ~/.bash_profile

statusCheck 0 "GOPATH=$GOPATH"
statusCheck 0 "INSTALLER_BRANCH=$INSTALLER_BRANCH"
statusCheck 0 "API_VIP=$API_VIP"
statusCheck 0 "INGRESS_VIP=$INGRESS_VIP"
statusCheck 0 "PRISM_CENTRAL_END_POINT=$PRISM_CENTRAL_END_POINT"
statusCheck 0 "SSH_PUBLIC_KEY=`echo $SSH_PUBLIC_KEY| cut -d " " -f1,3`"
statusCheck 0 "RELEASE_IMAGE=$RELEASE_IMAGE"

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
  #install_tools
  pull_image_redhat_latest
  install_openshift_installer
  create_openshift_cluster
}

case $1 in
  create_cluster)
    create_cluster
    deploy_CSI_Operator
    enable_ImageRegistry
    send_kubeconfig_slack
    ;;

  destroy_cluster)
    destroy_cluster
    ;;

  deploy_csi)
    deploy_CSI_Operator
    ;;
  
  enable_ImageRegistry)
    enable_ImageRegistry
    ;;

  run_e2e_tests)
    run_e2e_tests
    ;;
  *)
    statusCheck 1 " Usage: main.sh destroy_cluster or main.sh create_cluster or main.sh deploy_csi or main.sh enable_ImageRegistry or main.sh run_e2e_tests"
    ;;
esac
