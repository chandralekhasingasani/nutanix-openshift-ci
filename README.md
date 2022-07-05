# [[github_repo_name]]
[[github_repo_description]]

# The Hello World service
We've created an example service to show you the setup and workflow with Canaveral.

### Directory Structure
The top level directory of your repository should be set up like this:
  1. `README.md`: this file contains a textual description of the repository.
  2. `.circleci/`: this directory contains CircleCI's `config.yml` file.
  3. `hooks/`: this directory, if present, can contain *ad hoc* scripts that customize your build.
  4. `package/`:  add your `Dockerfile` under `package/docker/` to build a docker image.  (Note:  You can refer to files and folders directly in your `Dockerfile` because all files and folders under `services/` will be copied into the same folder as the `Dockerfile` during build.)
  5. `services/`: this directory should have a subdirectory for each `service`, *e.g.* `services/hello-world/`.  Each subdirectory contains the definition (source and tests) for the service.
  6. `blueprint.json`: this file, if present, contains instructions for Canaveral to deploy the service.

### Build
Canaveral uses CircleCI for building, packaging, and alerting its Deployment Engine. Your repository should have been registered with CircleCI when it was provisioned.  Here are some additional steps you should follow to ensure proper builds:

##### Ensure `.circleci/config.yml` has the correct variables (docker image only)
  1. Specify your preferred `CANAVERAL_BUILD_SYSTEM` (default is noop)
  2. Specify your preferred `CANAVERAL_PACKAGE_TOOLS` (use "docker" if deploying a docker image, use "noop" if no packaging is needed)
  3. **[OPTIONAL]** Specify the target `DOCKERFILE_NAME` to use  (default is Dockerfile)

You'll be able to monitor the build at [circleci.canaveral-corp.us-west-2.aws](https://circleci.canaveral-corp.us-west-2.aws/)

### Deployment
To use Canaveral for deployment, `blueprint.json` should be placed at the top level of the repo.  Spec for the blueprint can be found at [Canaveral Blueprint Spec](https://confluence.eng.nutanix.com:8443/x/5kbdBQ).

__Questions, issues or suggestions? Reach us at https://nutanix.slack.com/messages/canaveral-onboarding/.__

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
export CLUSTER_NAME=demo-general
export IMAGE_TAG=4.11.0-0.nightly-2022-05-20-213928
export UUID=*************
export SUBNET_UUID=***********
export SLACK_TOKEN=*********
export WEBHOOK_URL=***********



