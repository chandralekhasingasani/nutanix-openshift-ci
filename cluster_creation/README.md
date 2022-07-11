
### How to create cluster , with csi provisioned and image registry enabled

Create file named input_file with  environment variables required to create cluster .Below is a sample input_file:

export AWS_ACCESS_KEY=**********
export AWS_SECRET_KEY=**********
export OAUTH_TOKEN=**********
export PE_STORAGE_CONTAINER=default-container-44323109284837
export PE_USERNAME=**********
export PE_PASSWORD=**********
export INSTALLER_BRANCH=master
export PRISM_CENTRAL_USER=**********
export PRISM_CENTRAL_PASSWORD=**********
export API_VIP=10.40.142.2
export INGRESS_VIP=10.40.142.3
export PRISM_CENTRAL_END_POINT=prism-ganon.ntnxsherlock.com
export PULL_SECRET=**********
export SSH_PUBLIC_KEY=''
export PRISM_ELEMENT_IP=10.40.231.131
export CLUSTER_NAME=demo-ocp-nightly-411
export UUID=*************
export SUBNET_UUID=***********
export SLACK_TOKEN=*********
export WEBHOOK_URL=***********

Here is the document that talks about above parameters - https://confluence.eng.nutanix.com:8443/display/INFRA/Creation+of+sandbox+environment


 1.  To create cluster with latest redhat image:
              `sh main.sh create_cluster`

Note: To create cluster with custom image - `sh main.sh create_cluster_custom_image public.ecr.aws/g7v6l0u0/openshift/origin-release:ntnx-nightly-20220707`

2. To destroy cluster:           
              sh main.sh destroy_cluster

