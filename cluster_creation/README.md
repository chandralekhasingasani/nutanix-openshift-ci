1 . Create input_file under the folder cluster_creation just like the below sample

export INSTALLER_BRANCH=master
export PRISM_CENTRAL_USER=****
export PRISM_CENTRAL_PASSWORD=******
export API_VIP=10.40.142.2
export INGRESS_VIP=10.40.142.3
export PRISM_CENTRAL_END_POINT=prism-ganon.ntnxsherlock.com
export PULL_SECRET=******
export SSH_PUBLIC_KEY=888888
export PRISM_ELEMENT_IP=10.40.231.131
export CLUSTER_NAME=demo-chandra18april
export IMAGE_TAG=4.11.0-0.nightly-2022-05-20-213928

Note: Please provide PULL_SECRET as json string 

export PULL_SECRET="'{\"auths\":{\"cloud.openshift.com\":{\"auth\":\"\",\"email\":\"chandralekha882@gmail.com\"}}}'"

How to run?

1. To create cluster
    
    `sh main.sh create_cluster`

2. To delete cluster

    `sh main.sh delete_cluster`

