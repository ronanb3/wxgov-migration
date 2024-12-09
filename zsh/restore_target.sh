#!/bin/zsh

# Variables
TARGET_OCP_URL="https://api.670e54de9c48c677246af89e.ocp.techzone.ibm.com:6443"
TARGET_OCP_USER=kubeadmin
TARGET_OCP_PWD="qsL7w-nLRzs-tXLjZ-dBg6z"
TARGET_OCP_PROJECT=cpd

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

# Target Instance ID
##instance_id=$($yq '.source_instance_id.instance_id' $WORK_DIR/$PARAMETER_FILE)
instance_id=$($yq '.target_instance_id.instance_id' $WORK_DIR/$PARAMETER_FILE)
##instance_id=1729790192083064
openpage_name=$($yq '.target_instance_id.openpage_name' $WORK_DIR/$PARAMETER_FILE)


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


# print Variables
for var in {OP_USER,instance_id,openpage_name,backup_name,storage_file,configuration_file,encryption_key_pw,opsystem_pw,keystore_pw,op_user_pwd}
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
##openpage_name="openpagesinstance-cr"
echo "OpenPage Instance Name = $openpage_name"

echo "***********************"
echo "**** RESTORE PART ****"
echo "***********************"

# GOTO !
##cat >/dev/null <<CODING

echo "==== Restore Secrets ===="
for sec in $secrets
do 
  echo "- Send ${sec}.sec locally to the pod"
  oc cp ${sec}.sec c-db2oltp-${instance_id}-db2u-0:/mnt/backup/online &> /dev/null
  echo "- Import secret"
  oc exec -it c-db2oltp-${instance_id}-db2u-0 -- /bin/bash -c "source ~/.bashrc ; cd /mnt/backup/online/; gsk8capicmd_64 -secretkey -add -db /mnt/blumeta0/db2/keystore/keystore.p12 -stashed -label ${sec} -format pkcs12 -file ${sec}.sec ;" 2> /dev/null
done

echo "==== Restart Application pod ===="
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

pwd
echo "==== Restore Openpage Storage ===="
echo "- Copy Storage Backup file to pod"
oc cp ./${storage_file} openpages-${openpage_name}-sts-0:/openpages-shared/openpages-backup-restore/${storage_file} # 2> /dev/null

echo "- Import Storage Backup"
# Backup application storage in pod
restore_application_storage() {
  storage_file=$1
  cd /openpages-shared/openpages-backup-restore
  export OPDB_PASSWORD="$(cat "${SECRETS_PATH}/op-db-secret/openpage-pw")"
  cd /opt/ibm/OpenPages/aurora/bin
  name=$(basename ${storage_file} .zip)
  ./OPRestore.sh $name
  cd /openpages-shared/openpages-backup-restore/
  rm ${storage_file}
}

oc exec openpages-${openpage_name}-sts-0 -- bash -c "$(typeset -f restore_application_storage); restore_application_storage ${storage_file}" # &> /dev/null

echo "- Copy Configuration Backup"
oc cp ./${configuration_file} openpages-${openpage_name}-sts-0:/openpages-shared/openpages-backup-restore/${configuration_file} # 2> /dev/null

echo "==== Restart Application pod ===="
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

CODING

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

echo "==== Restore Db2 backup ===="
echo "-Copy backup to pod"
oc cp ${backup_name}  c-db2oltp-${instance_id}-db2u-0:/mnt/backup/online/ --retries=-1

# Backup database in pod
restore_database() 
{
  backup_name=$1
  timestamp=${backup_name:25:14}
  echo "timestamp = $timestamp"
  source ~/.bashrc
  db2 connect to ${DBNAME}
  db2 force application all
  db2 deactivate DATABASE ${DBNAME}
  db2 connect reset
  db2 deactivate DATABASE ${DBNAME}
  BACKUPDIR="/mnt/backup/online/"
  cd $BACKUPDIR
  db2ckbkp -h ./${backup_name}
  db2 RESTORE DATABASE ${DBNAME} FROM /mnt/backup/online/ TAKEN AT ${timestamp} INTO ${DBNAME} LOGTARGET /mnt/backup/online/extracted_logs REPLACE EXISTING WITHOUT PROMPTING
  db2 'rollforward db OPX to end of backup on all dbpartitionnums and stop overflow log path (/mnt/backup/online/extracted_logs/)'
  db2 activate db ${DBNAME}
  db2 connect to ${DBNAME}
}

oc exec c-db2oltp-${instance_id}-db2u-0 -- bash -c "$(typeset -f restore_database); restore_database ${backup_name}" 2> /dev/null

echo "- Get Restore version"
oc exec -it c-db2oltp-${instance_id}-db2u-0 -- /bin/bash -c 'source ~/.bashrc ; db2 connect to ${DBNAME} ; db2 "select * from openpage.schemaversion"'

echo "==== Restore Secrets ===="
echo "- encryption-key-pw"
oc patch secrets openpages-${openpage_name}-platform-secret -p '{"data":{"encryption-key-pw":"'${encryption_key_pw}'"}}'
echo "- keystore-pw"
oc patch secrets openpages-${openpage_name}-platform-secret -p '{"data":{"keystore-pw":"'${keystore_pw}'"}}'
echo "- opsystem-pw"
oc patch secrets openpages-${openpage_name}-platform-secret -p '{"data":{"opsystem-pw":"'${opsystem_pw}'"}}'
echo "- user"
oc patch secrets openpages-${openpage_name}-initialpw-secret -p '{"data":{"'${OP_USER}'":"'${op_user_pwd}'"}}'

