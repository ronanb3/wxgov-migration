#!/bin/zsh

# Variables
TARGET_OCP_URL="https://api.670e54de9c48c677246af89e.ocp.techzone.ibm.com:6443"
TARGET_OCP_USER=kubeadmin
TARGET_OCP_PWD="qsL7w-nLRzs-tXLjZ-dBg6z"
TARGET_OCP_PROJECT=cpd
TARGET_OPERATORS_PROJECT=cpd-operators

TARGET_OP_USER=OpenPagesAdministrator

WORK_DIR="work_tmp"
PARAMETER_FILE="params.yaml"

yq="./yq"

debug()
{
  echo "$1 = `eval echo \\$${1}`"
}

# Retrieve parameters
# OpenPage User
OP_USER=$($yq '.openpage_user.OP_USER' $WORK_DIR/$PARAMETER_FILE)

CP4D_USER=$($yq '.openpage_user.CP4D_USER' $WORK_DIR/$PARAMETER_FILE)

# Source Instance ID
##instance_id=$($yq '.source_instance_id.instance_id' $WORK_DIR/$PARAMETER_FILE)
instance_id=1729790192083064

# Backup params
secrets=($($yq '.backup_params.SECRETS' $WORK_DIR/$PARAMETER_FILE))
backup_name=$($yq '.backup_params.backup_name' $WORK_DIR/$PARAMETER_FILE)
storage_file=$($yq '.backup_params.storage_file' $WORK_DIR/$PARAMETER_FILE)
configuration_file=$($yq '.backup_params.configuration_file' $WORK_DIR/$PARAMETER_FILE)

# Keys
encryption_key_pw=$($yq '.keys.encryption_key_pw' $WORK_DIR/$PARAMETER_FILE)
opsystem_pw=$($yq '.keys.opsystem_pw' $WORK_DIR/$PARAMETER_FILE)
keystore_pw=$($yq '.keys.keystore_pw' $WORK_DIR/$PARAMETER_FILE)
op_user_pwd=$($yq '.keys.op_user_pwd' $WORK_DIR/$PARAMETER_FILE)

cpd_instance_ns=${TARGET_OCP_PROJECT}
cpd_operator_ns=${TARGET_OPERATORS_PROJECT}
tenant_user="cp4dadmin"


# print Variables
for var in {OP_USER,CP4D_USER,instance_id,backup_name,storage_file,configuration_file,encryption_key_pw,opsystem_pw,keystore_pw,op_user_pwd}
do 
  debug $var
done
echo "secrets ="
for sec in $secrets
do
  echo "- $sec" | cat -v
done

# Login to OpenShift
oc login -u ${TARGET_OCP_USER} -p ${TARGET_OCP_PWD} --server=${TARGET_OCP_URL}

# Switch to project
oc project ${TARGET_OCP_PROJECT}

# create working directory and switch to it
mkdir -p $WORK_DIR
cd $WORK_DIR

# automatic detection of OpenPage instance name if only one instance
# openpage_name=$(oc get openpagesinstances.openpages.cpd.ibm.com | grep -v NAME | awk '{print $1}')
openpage_name="openpagesinstance-cr"
echo "OpenPage Instance Name = $openpage_name"

echo "**********************"
echo "**** UPGRADE PART ****"
echo "**********************"

# GOTO !
## cat >/dev/null <<CODING

echo "==== Create Role with required permissions ===="
oc create role crud-pod-role --verb=get,list,create,update,watch,patch --resource=pod -n ${cpd_instance_ns}
oc create role crud-pod-exec-role --verb=get,list,create,update,watch,patch --resource=pods/exec -n ${cpd_instance_ns}
oc create role crud-pod-log-role --verb=get,list,create,update,watch,patch --resource=pods/log -n ${cpd_instance_ns}
oc create role read-ns --verb=get,list,watch --resource=namespace -n ${cpd_instance_ns}

echo "- Add role to user"
oc adm policy add-role-to-user crud-pod-role ${tenant_user} --role-namespace=${cpd_instance_ns} -n ${cpd_instance_ns}
oc adm policy add-role-to-user read-ns ${tenant_user} --role-namespace=${cpd_instance_ns} -n ${cpd_instance_ns}
oc adm policy add-role-to-user crud-pod-exec-role ${tenant_user} --role-namespace=${cpd_instance_ns} -n ${cpd_instance_ns}
oc adm policy add-role-to-user crud-pod-log-role ${tenant_user} --role-namespace=${cpd_instance_ns} -n ${cpd_instance_ns}

echo "- Add SCC to user"
oc adm policy add-scc-to-user privileged ${tenant_user} -n ${cpd_instance_ns}
oc adm policy add-scc-to-user rook-ceph-csi ${tenant_user} -n ${cpd_instance_ns}
oc adm policy add-scc-to-user restricted  ${tenant_user} -n ${cpd_instance_ns}
oc adm policy add-scc-to-user anyuid  ${tenant_user} -n ${cpd_instance_ns}
oc adm policy add-scc-to-user restricted-v2  ${tenant_user} -n ${cpd_instance_ns}
oc adm policy add-scc-to-user nonroot-v2  ${tenant_user} -n ${cpd_instance_ns}
oc adm policy add-scc-to-user nonroot  ${tenant_user} -n ${cpd_instance_ns}
oc adm policy add-scc-to-user noobaa-db ${tenant_user} -n ${cpd_instance_ns}
oc adm policy add-scc-to-user noobaa-endpoint ${tenant_user} -n ${cpd_instance_ns}
oc adm policy add-scc-to-user hostmount-anyuid ${tenant_user} -n ${cpd_instance_ns}
oc adm policy add-scc-to-user machine-api-termination-handler ${tenant_user} -n ${cpd_instance_ns}
oc adm policy add-scc-to-user hostnetwork-v2 ${tenant_user} -n ${cpd_instance_ns}
oc adm policy add-scc-to-user hostnetwork ${tenant_user} -n ${cpd_instance_ns}
oc adm policy add-scc-to-user hostaccess ${tenant_user} -n ${cpd_instance_ns}
oc adm policy add-scc-to-user zen-ns-c-db2oltp-${instance_id}-scc ${tenant_user} -n ${cpd_instance_ns}
oc adm policy add-scc-to-user rook-ceph ${tenant_user} -n ${cpd_instance_ns}
oc adm policy add-scc-to-user node-exporter ${tenant_user} -n ${cpd_instance_ns}

echo "==== Stop Application pod ===="
rep=0
echo "- Scale STS to $rep and wait for result"
oc scale --replicas=$rep sts/openpages-${openpage_name}-sts
res=$(oc get sts/openpages-${openpage_name}-sts | grep $rep/$rep | wc -l)
while [[ $res -ne 1 ]]
do
  echo "- Wait a minute"
  sleep 60
  res=$(oc get sts/openpages-${openpage_name}-sts | grep $rep/$rep | wc -l)
done

echo "- delete the openpages operator"
oc delete subscription.operators.coreos.com/ibm-cpd-openpages-operator clusterserviceversion.operators.coreos.com/ibm-cpd-openpages-operator.v7.2.0 -n ${cpd_operator_ns}

echo '=== Upgrade DB ===='
PROVISIONER_IMAGE_DIGEST=$(skopeo inspect docker://cp.icr.io/cp/cpd/openpages-cpd-provisioner:9.0.0.3.2-61 | jq -r '.Digest')
- echo "- found image: $PROVISIONER_IMAGE_DIGEST"

cat <<EOF > openpages_${openpage_name}-debug-upgrade_db.yaml
apiVersion: v1
kind: Pod
metadata:
  name: openpages-${openpage_name}-provision-db-debug
  namespace: ${cpd_instance_ns}
spec:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: kubernetes.io/arch
            operator: In
            values:
            - amd64
  automountServiceAccountToken: false
  containers:
  - command: ["/bin/sh", "-ec", "upgrade_db.sh"]
    env:
    - name: INSTANCE_ID
      value: "${instance_id}"
    - name: INSTANCE_NAME
      value: ${openpage_name}
    - name: ZEN_CONTROL_PLANE_NS
      value: ${cpd_instance_ns}
    - name: INSTANCE_NAMESPACE
      value: ${cpd_instance_ns}
    - name: OP_CONTEXT_ROOT
      value: openpages-${openpage_name}
    - name: OP_EXT_HOST
      valueFrom:
        configMapKeyRef:
          key: URL_PREFIX
          name: product-configmap
    - name: OP_EXT_PORT
      value: "443"
    - name: DATABASE_TYPE
      value: internal
    - name: OPDB_PORT
      value: "50001"
    - name: SCHEMA_VERSION
      value: "9.0.0.3.2"
    - name: OPDB_ALIAS
      value: OPX
    - name: OPDB_USER
      value: openpage
    - name: OPDB_OWNER
      value: "db2inst1"
    image: cp.icr.io/cp/cpd/openpages-cpd-provisioner@${PROVISIONER_IMAGE_DIGEST}
    imagePullPolicy: Always
    name: opdbprovisioner-pre-install-job-container
    resources:
      limits:
        cpu: 500m
        ephemeral-storage: 60Mi
        memory: 512Mi
      requests:
        cpu: 250m
        ephemeral-storage: 60Mi
        memory: 256Mi
    securityContext:
      allowPrivilegeEscalation: false
      runAsUser: 0
    terminationMessagePath: /dev/termination-log
    terminationMessagePolicy: File
    volumeMounts:
    - mountPath: /var/run/op-initialpw-secret
      name: op-initialpw-secret
    - mountPath: /var/run/op-platform-secret
      name: op-platform-secret
    - mountPath: /var/run/op-db-secret
      name: op-db-secret
    - mountPath: /var/run/sharedsecrets
      name: zen-service-broker-secret
    - mountPath: /var/run/certs
      name: internal-tls
  dnsPolicy: ClusterFirst
  enableServiceLinks: true
  imagePullSecrets:
  - name: ibm-entitlement-key
  nodeSelector:
    kubernetes.io/arch: amd64
  preemptionPolicy: PreemptLowerPriority
  priority: 0
  restartPolicy: Never
  schedulerName: default-scheduler
  serviceAccount: zen-norbac-sa
  serviceAccountName: zen-norbac-sa
  terminationGracePeriodSeconds: 30
  tolerations:
  - effect: NoExecute
    key: node.kubernetes.io/not-ready
    operator: Exists
    tolerationSeconds: 300
  - effect: NoExecute
    key: node.kubernetes.io/unreachable
    operator: Exists
    tolerationSeconds: 300
  - effect: NoSchedule
    key: node.kubernetes.io/memory-pressure
    operator: Exists
  volumes:
  - name: op-platform-secret
    secret:
      defaultMode: 420
      items:
      - key: opsystem-pw
        path: opsystem-pw
      - key: encryption-key-pw
        path: encryption-key-pw
      secretName: openpages-${openpage_name}-platform-secret
  - name: op-db-secret
    secret:
      defaultMode: 420
      items:
      - key: openpage-pw
        path: openpage-pw
      - key: db2inst1-pw
        path: db2inst1-pw
      secretName: openpages-${openpage_name}-db-secret
  - name: op-initialpw-secret
    secret:
      defaultMode: 420
      secretName: openpages-${openpage_name}-initialpw-secret
  - name: zen-service-broker-secret
    secret:
      defaultMode: 420
      secretName: zen-service-broker-secret
  - name: internal-tls
    secret:
      defaultMode: 420
      items:
      - key: ca.crt
        path: certificate.pem
      - key: tls.crt
        path: tls.crt
      - key: tls.key
        path: tls.key
      secretName: internal-tls
EOF

echo "- Run upgrade DB script openpages-${openpage_name}-provision-db-debug"

# oc apply -f openpages_${openpage_name}-debug-upgrade_db.yaml

echo "- Wait for the script to complete"
res=$(oc get pod openpages-${openpage_name}-provision-db-debug | grep Completed | wc -l)
while [[ $res -ne 1 ]]
do
  echo "- Wait a minute"
  sleep 60
  res=$(oc get pod openpages-${openpage_name}-provision-db-debug | grep Completed | wc -l)
done

echo "- Verify DB Schema"
oc exec -it c-db2oltp-${instance_id}-db2u-0 -- /bin/bash -c 'source ~/.bashrc ; db2 connect to ${DBNAME} ; db2 "select * from openpage.schemaversion"'
#TODO : add a check

echo "==== Start Application pod ===="
rep=1
echo "- Scale STS to $rep and wait for result"
oc scale --replicas=$rep sts/openpages-${openpage_name}-sts
res=$(oc get sts/openpages-${openpage_name}-sts | grep $rep/$rep | wc -l)
while [[ $res -ne 1 ]]
do
  echo "- Wait a minute"
  sleep 60
  res=$(oc get sts/openpages-${openpage_name}-sts | grep $rep/$rep | wc -l)
done

echo '=== Upgrade Data ===='
cat <<EOF > openpages_${openpage_name}-debug-upgrade_loader_data.yaml
apiVersion: v1
kind: Pod
metadata:
  name: openpages-${openpage_name}-provision-data-debug
  namespace: ${cpd_instance_ns}
spec:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: kubernetes.io/arch
            operator: In
            values:
            - amd64
  automountServiceAccountToken: false
  containers:
  - command: ["/bin/sh", "-ec", "upgrade_loader_data.sh"]
    env:
    - name: INSTANCE_ID
      value: "${instance_id}"
    - name: INSTANCE_NAME
      value: ${openpage_name}
    - name: ZEN_CONTROL_PLANE_NS
      value: ${cpd_instance_ns}
    - name: INSTANCE_NAMESPACE
      value: ${cpd_instance_ns}
    - name: OP_CONTEXT_ROOT
      value: openpages-${openpage_name}
    - name: OP_EXT_HOST
      valueFrom:
        configMapKeyRef:
          key: URL_PREFIX
          name: product-configmap
    - name: OP_EXT_PORT
      value: "443"
    - name: DATABASE_TYPE
      value: internal
    - name: OPDB_PORT
      value: "50001"
    - name: SCHEMA_VERSION
      value: "9.0.0.3.2"
    - name: OPDB_ALIAS
      value: OPX
    - name: OPDB_USER
      value: openpage
    - name: OPDB_OWNER
      value: "db2inst1"
    image: cp.icr.io/cp/cpd/openpages-cpd-provisioner@${PROVISIONER_IMAGE_DIGEST}
    imagePullPolicy: Always
    name: opdbprovisioner-pre-install-job-container
    resources:
      limits:
        cpu: 500m
        ephemeral-storage: 60Mi
        memory: 512Mi
      requests:
        cpu: 250m
        ephemeral-storage: 60Mi
        memory: 256Mi
    securityContext:
      allowPrivilegeEscalation: false
      runAsUser: 0
    terminationMessagePath: /dev/termination-log
    terminationMessagePolicy: File
    volumeMounts:
    - mountPath: /var/run/op-initialpw-secret
      name: op-initialpw-secret
    - mountPath: /var/run/op-platform-secret
      name: op-platform-secret
    - mountPath: /var/run/op-db-secret
      name: op-db-secret
    - mountPath: /var/run/sharedsecrets
      name: zen-service-broker-secret
    - mountPath: /var/run/certs
      name: internal-tls
  dnsPolicy: ClusterFirst
  enableServiceLinks: true
  imagePullSecrets:
  - name: ibm-entitlement-key
  nodeSelector:
    kubernetes.io/arch: amd64
  preemptionPolicy: PreemptLowerPriority
  priority: 0
  restartPolicy: Never
  schedulerName: default-scheduler
  serviceAccount: zen-norbac-sa
  serviceAccountName: zen-norbac-sa
  terminationGracePeriodSeconds: 30
  tolerations:
  - effect: NoExecute
    key: node.kubernetes.io/not-ready
    operator: Exists
    tolerationSeconds: 300
  - effect: NoExecute
    key: node.kubernetes.io/unreachable
    operator: Exists
    tolerationSeconds: 300
  - effect: NoSchedule
    key: node.kubernetes.io/memory-pressure
    operator: Exists
  volumes:
  - name: op-platform-secret
    secret:
      defaultMode: 420
      items:
      - key: opsystem-pw
        path: opsystem-pw
      - key: encryption-key-pw
        path: encryption-key-pw
      secretName: openpages-${openpage_name}-platform-secret
  - name: op-db-secret
    secret:
      defaultMode: 420
      items:
      - key: openpage-pw
        path: openpage-pw
      - key: db2inst1-pw
        path: db2inst1-pw
      secretName: openpages-${openpage_name}-db-secret
  - name: op-initialpw-secret
    secret:
      defaultMode: 420
      secretName: openpages-${openpage_name}-initialpw-secret
  - name: zen-service-broker-secret
    secret:
      defaultMode: 420
      secretName: zen-service-broker-secret
  - name: internal-tls
    secret:
      defaultMode: 420
      items:
      - key: ca.crt
        path: certificate.pem
      - key: tls.crt
        path: tls.crt
      - key: tls.key
        path: tls.key
      secretName: internal-tls
EOF

echo "- Run script openpages-${openpage_name}-provision-data-debug"
##oc apply -f openpages_${openpage_name}-debug-upgrade_loader_data.yaml

echo "- Wait for the script to complete"
res=$(oc get pod openpages-${openpage_name}-provision-data-debug | grep Completed | wc -l)
while [[ $res -ne 1 ]]
do
  echo "- Wait a minute"
  sleep 60
  res=$(oc get pod openpages-${openpage_name}-provision-data-debug | grep Completed | wc -l)
done


echo "==== RECREATE OPERATOR ===="
cat <<EOF > recreate_openpage_operator.yaml
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  labels:
    operators.coreos.com/ibm-cpd-openpages-operator.cpd-operators: ""
  name: ibm-cpd-openpages-operator
  namespace: ${cpd_operator_ns}
spec:
  channel: v7.2
  installPlanApproval: Automatic
  name: ibm-cpd-openpages-operator
  source: ibm-cpd-openpages-operator-catalog
  sourceNamespace: cpd-operators
  startingCSV: ibm-cpd-openpages-operator.v7.2.0
EOF

echo "- Run script"
##oc create -f recreate_openpage_operator.yaml

echo "==== Start Application pod ===="
rep=1
echo "- Scale STS to $rep and wait for result"
oc scale --replicas=$rep sts/openpages-${openpage_name}-sts
res=$(oc get sts/openpages-${openpage_name}-sts | grep $rep/$rep | wc -l)
while [[ $res -ne 1 ]]
do
  echo "- Wait a minute"
  sleep 60
  res=$(oc get sts/openpages-${openpage_name}-sts | grep $rep/$rep | wc -l)
done

# Check all is fine
oc get pod | grep ${openpage_name}
oc get openpagesinstance ${openpage_name}



