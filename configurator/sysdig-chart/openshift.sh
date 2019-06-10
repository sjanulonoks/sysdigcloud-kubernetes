#!/bin/ash
set -euo pipefail
alias oc="/lib/ld-musl-x86_64.so.1 --library-path /lib /openshift/openshift-origin-client-tools-v3.11.0-0cbc58b-linux-64bit/oc"
alias kubectl="/lib/ld-musl-x86_64.so.1 --library-path /lib /openshift/openshift-origin-client-tools-v3.11.0-0cbc58b-linux-64bit/kubectl"
#set variables
OPENSHIFT_URL=$(cat /sysdig-chart/values.yaml | yq .sysdig.openshiftUrl | tr -d '"')
OPENSHIFT_USER=$(cat /sysdig-chart/values.yaml | yq .sysdig.openshiftUser | tr -d '"')
OPENSHIFT_PASSWORD=$(cat /sysdig-chart/values.yaml | yq .sysdig.openshiftPassword | tr -d '"')
NAMESPACE=$(cat /sysdig-chart/values.yaml | yq .namespace | tr -d '"')
#login
oc login ${OPENSHIFT_URL} -u ${OPENSHIFT_USER} -p ${OPENSHIFT_PASSWORD}
OPENSHIFT_PROJECTS=$(oc projects -q)
PROJECT_PRESENT=false
for PROJECT in OPENSHIFT_PROJECTS
do
  if [[ ${NAMESPACE} == ${PROJECT} ]]; then
    PROJECT_PRESENT=true
    echo "project is present in openshift"
  fi
done
echo $OPENSHIFT_PROJECTS
#create project
if [[ ${PROJECT_PRESENT} == false ]]; then
  oc new-project ${NAMESPACE}
else
  oc project ${NAMESPACE}
fi
#create permission for the project
oc adm policy add-scc-to-user anyuid -n ${NAMESPACE} -z default
oc adm policy add-scc-to-user privileged -n ${NAMESPACE} -z default