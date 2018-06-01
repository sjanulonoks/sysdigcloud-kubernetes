#!/bin/bash

# Global Variables
NOW=$(date "+%Y.%m.%d-%H.%M.%S")
SDC_HOME="$(dirname $0)/.."

mkdir -p $SDC_HOME/logs/uninstall

LOG_FILE=$SDC_HOME/logs/uninstall/uninstall-$NOW.log
SETTINGS_FILE="$SDC_HOME/etc/config/sdc-settings.yaml"
NAMESPACE=$(egrep namespace $SETTINGS_FILE | awk '{print $2}')
BACKEND_VERSION=$(egrep backendImage $SETTINGS_FILE | awk -F: '{print $3}')
FRONTEND_VERSION=$(egrep frontendImage $SETTINGS_FILE | awk -F: '{print $3}')
K8S_CLIENT_VERSION=$(kubectl version | egrep ^Client | awk -F, '{print $3}')
K8S_SERVER_VERSION=$(kubectl version | egrep ^Server | awk -F, '{print $3}')
CURRENT_CONTEXT=$(kubectl config get-contexts | egrep '^\*' | awk '{print $2}')
CURRENT_CLUSTER=$(kubectl config get-contexts | egrep '^\*' | awk '{print $3}')

print_env_variables()
{
    printf "LOG_FILE: %s\n" $LOG_FILE
    printf "SDC_HOME: %s\n" $SDC_HOME
    printf "SETTINGS_FILE: %s\n" $SETTINGS_FILE
    printf "NAMESPACE: %s\n" ${NAMESPACE}
    printf "BACKEND_VERSION: %s\n" $BACKEND_VERSION
    printf "FRONTEND_VERSION: %s\n" $FRONTEND_VERSION
    printf "K8S_CLIENT_VERSION: %s\n" $K8S_CLIENT_VERSION
    printf "K8S_SERVER_VERSION: %s\n" $K8S_SERVER_VERSION
    printf "CURRENT_CONTEXT: %s\n" $CURRENT_CONTEXT
    printf "CURRENT_CLUSTER: %s\n" $CURRENT_CLUSTER
}

print_banner()
{
    local cols=$(tput cols)
    local lines=$(tput lines)
    local numcols=$(((cols-6)/2))
    local numlines=$((lines/2))

    clear
    printf '\n'
    printf '+%.0s' {1..100}
    printf '\n'
    #tput cup $numlines $numcols
    printf "%s\n" "sysdigcloud on-prem uninstaller"
    printf '\n%.0s' {1..3}
    printf "%s\n" "This is the Sysdig Monitor on-prem Kubernetes uninstaller."
    printf "%s\n" "This installer assumes you have a running kubernetes cluster on AWS or GKE."
    printf "%s\n" "The executable 'kubectl' needs to be in your \$PATH with the context pointing to the right cluster."
    printf '\n%.0s' {1..3}
    printf "%s\n" "Your current kubectl client and server version are as follows:"
    printf "Client: %s\n" $K8S_CLIENT_VERSION
    printf "Server: %s\n" $K8S_SERVER_VERSION
    printf '\n%.0s' {1..2}
    printf "%s\n" "Your current Kubernetes context is:"
    printf "Current Context: %s\n" $CURRENT_CONTEXT
    printf "Current Cluster: %s\n" $CURRENT_CLUSTER
    printf '\n%.0s' {1..2}
    printf "%s\n" "Uinstaller is configured for namespace ${NAMESPACE}."
    printf "%s\n" "Namespace ${NAMESPACE} will be removed if you answer \"yes\" to the prompt."
    printf '+%.0s' {1..100}
    printf '\n'
}

prompt_uninstall()
{
    printf '\n'
    printf '\n'
    printf "%s\n" "Do you wish to uninstall backend version $BACKEND_VERSION of sdc-kubernetes?"| tee -a $LOG_FILE
    select yn in "Yes" "No"; do
        case $yn in
            Yes ) break;;
            No ) exit 1;;
        esac
    done
    printf '\n'
}

delete_storageclasses()
{
    kubectl delete -f $SDC_HOME/datastores/storageclasses/ -n ${NAMESPACE} >> $LOG_FILE 2>&1
    if [ $? -eq 0 ]; then
        echo "--> deleted storageclasses." | tee -a $LOG_FILE
    else
        echo "--> failed to delete storageclasses." | tee -a $LOG_FILE
    fi
}

delete_ssl_certs()
{
    rm $SDC_HOME/etc/certs/server.key
    rm $SDC_HOME/etc/certs/server.crt
    echo "...deleted ssl certs." | tee -a $LOG_FILE
}

delete_tls_secret()
{
    #create ssl-secret in kubernetes if it doesn't exist already
    kubectl delete secret sysdigcloud-ssl-secret -n ${NAMESPACE} >> $LOG_FILE 2>&1
    echo "--> deleted ssl secret sysdigcloud-ssl-secret." | tee -a $LOG_FILE
}

delete_configmaps()
{
    kubectl delete -f $SDC_HOME/etc/config/sdc-config.yaml >> $LOG_FILE 2>&1
    echo "--> deleted configmaps." | tee -a $LOG_FILE
}

stop_datastores()
{
    kubectl delete -f $SDC_HOME/datastores/sdc-mysql-master.yaml >> $LOG_FILE 2>&1
    kubectl delete -f $SDC_HOME/datastores/sdc-redis-master.yaml >> $LOG_FILE 2>&1
    kubectl delete -f $SDC_HOME/datastores/sdc-redis-slaves.yaml >> $LOG_FILE 2>&1
    kubectl delete -f $SDC_HOME/datastores/sdc-cassandra.yaml >> $LOG_FILE 2>&1
    kubectl delete -f $SDC_HOME/datastores/sdc-elasticsearch.yaml >> $LOG_FILE 2>&1
    kubectl delete -f $SDC_HOME/datastores/sdc-mysql-slaves.yaml >> $LOG_FILE 2>&1
}

stop_backend()
{
    kubectl delete -f $SDC_HOME/backend/sdc-api.yaml >> $LOG_FILE 2>&1
    kubectl delete -f $SDC_HOME/backend/sdc-worker.yaml >> $LOG_FILE 2>&1
    kubectl delete -f $SDC_HOME/backend/sdc-collector.yaml >> $LOG_FILE 2>&1
}

print_post_uninstall_banner()
{
    echo
    echo "--> app deletion order submitted to kubernetes ..." | tee -a $LOG_FILE
    echo "--> monitor application by using \`watch kubectl get pods -n ${NAMESPACE} \`" | tee -a $LOG_FILE
    echo
    echo
    echo
    kubectl get pods -n ${NAMESPACE}| tee -a $LOG_FILE
}

delete_namespace()
{
    clear
    echo "Do you wish to delete the namespace ${NAMESPACE}?"
    echo "NB: Removing the namespace will remove all Persistent Volume Claims (PVCs) and their associated Persistent Volumes (PVs)."
    select yn in "Yes" "No"; do
        case $yn in
            Yes ) break;;
            No ) exit 1;;
        esac
    done

    kubectl get namespace ${NAMESPACE} >> $LOG_FILE 2>&1
    if [ $? -eq 0 ]    ; then
        kubectl delete namespace ${NAMESPACE} >> $LOG_FILE 2>&1
        if [ $? -eq 0 ] ; then
            echo "--> namespace ${NAMESPACE} deleted." | tee -a $LOG_FILE
        else
            echo "--> failed to delete namespace ${NAMESPACE}." | tee -a $LOG_FILE
            exit 1
        fi
    else
        echo "--> namespace ${NAMESPACE} doesn't exist." | tee -a $LOG_FILE
    fi
}

if [[ "${DEBUG:-}" == "true" ]]; then
    print_env_variables
fi

print_banner
prompt_uninstall
stop_datastores
stop_backend
delete_storageclasses
delete_configmaps
delete_ssl_certs
delete_tls_secret
sleep 5
delete_namespace