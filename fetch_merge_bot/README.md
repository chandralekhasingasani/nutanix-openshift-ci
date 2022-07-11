Github app  scans through repositories where to check if there are in sync with upstream repositories . 

Incase they are not identical it calls fetch and merge github api to be in sync with Upstream repositories

All secrets required for the github app are stored in AWS Secret Manager under openshift/github/secrets

Create 3 environment variables under lambda configuration namely ,

APP_ID	-> Application id
INSTALLATION_ID -> Installation id
BASE_REF -> upstream_repo_owner:branch_name

