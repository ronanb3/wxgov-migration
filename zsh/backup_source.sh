#!/bin/zsh

# Variables
OCP_URL="https://api.670e543742e233326365a7f5.ocp.techzone.ibm.com:6443"
OCP_USER=kubeadmin
OCP_PWD="Qq5rR-pipyq-bE9je-EfpBy"
OCP_PROJECT=wxgov

OP_USER=OpenPagesAdministrator
CP4D_USER=cp4dadmin

instance_id=1729685232620366

WORK_DIR="work_tmp"
PARAMETER_FILE="params.yaml"

# Login to OpenShift
oc login -u ${OCP_USER} -p ${OCP_PWD} --server=${OCP_URL}

# Switch to project
oc project ${OCP_PROJECT}

# create working directory and switch to it
mkdir -p $WORK_DIR
cd $WORK_DIR

# automatic detection of OpenPage instance name if only one instance
openpage_name=$(oc get openpagesinstances.openpages.cpd.ibm.com | grep -v NAME | awk '{print $1}')
echo "OpenPage Instance Name = $openpage_name"

echo "*********************"
echo "**** BACKUP PART ****"
echo "*********************"

# GOTO !
# cat >/dev/null <<CODING 

# get secret names
secrets=($(oc exec -it c-db2oltp-${instance_id}-db2u-0 -- /bin/bash -c 'source ~/.bashrc ; gsk8capicmd_64 -cert -list -db /mnt/blumeta0/db2/keystore/keystore.p12 -stashed' 2> /dev/null | awk '/DB2/ {print $2}'))


echo "==== Backup Secrets ===="
echo "- Remove all .sec files"
oc exec -it c-db2oltp-${instance_id}-db2u-0 -- /bin/bash -c "source ~/.bashrc ; cd ; rm *.sec;" 2> /dev/null

for sec in $secrets
do 
  # remove trailing \r
  sec="${sec%%[[:cntrl:]]}"
  echo "- Extract ${sec}" | cat -v
  oc exec -it c-db2oltp-${instance_id}-db2u-0 -- /bin/bash -c "source ~/.bashrc ; cd ; gsk8capicmd_64 -secretkey -extract -db /mnt/blumeta0/db2/keystore/keystore.p12 -stashed -target ${sec}.sec -format pkcs12 -label ${sec};" 2> /dev/null
  echo "- Copy ${sec}.sec from the pod locally"
  oc cp c-db2oltp-${instance_id}-db2u-0:/mnt/blumeta0/home/db2inst1/${sec}.sec ${sec}.sec &> /dev/null
done

# Backup database in pod
backup_database() {
  source ~/.bashrc
  db2 connect to ${DBNAME}
  BACKUPDIR="/mnt/backup/online/"
  cp ${KEYSTORELOC}/keystore.p12 $BACKUPDIR
  cp ${KEYSTORELOC}/keystore.sth $BACKUPDIR
  cd $BACKUPDIR
  # remove all previous backups
  rm OPX*
  db2 backup db ${DBNAME} on all dbpartitionnums online to $BACKUPDIR include logs without prompting
}

# Backup database OPX
echo "==== Backup Database and keys ==="
##oc exec c-db2oltp-${instance_id}-db2u-0 -- bash -c "$(typeset -f backup_database); backup_database" 2> /dev/null

# get latest backup file name 
backup_name=$(oc exec -it c-db2oltp-${instance_id}-db2u-0 -- /bin/bash -c "source ~/.bashrc ; cd /mnt/backup/online/ ; ls -lt OPX* | head -n 1 | awk '{print \$9}'" 2> /dev/null)
# remove trailing \r
backup_name="${backup_name%%[[:cntrl:]]}"
echo "- Backup name : ${backup_name}"
echo "- Copy keys"
oc rsync c-db2oltp-${instance_id}-db2u-0:/mnt/backup/online//keystore.p12 . --progress=true 2> /dev/null
oc rsync c-db2oltp-${instance_id}-db2u-0:/mnt/backup/online//keystore.sth . --progress=true 2> /dev/null
echo "- Copy ${backup_name} from the pod locally. It can take a lot of time !"
oc rsync c-db2oltp-${instance_id}-db2u-0:/mnt/backup/online/${backup_name} . --progress=true 2> /dev/null

echo "==== Backup OpenPage Application Storage and Configuration ===="
echo "- Scale STS to 1 and wait for result"
oc scale --replicas=1 sts/openpages-${openpage_name}-sts
res=$(oc get sts/openpages-${openpage_name}-sts | grep 1/1 | wc -l)
while [[ $res -ne 1 ]]
do
  echo "- Wait a minute"
  sleep 60
  res=$(oc get sts/openpages-${openpage_name}-sts | grep 1/1 | wc -l)
done

echo "- Backup Application Storage"
# Backup application storage in pod
backup_application_storage() {
  mkdir -p /openpages-shared/temp
  cd /opt/ibm/OpenPages/aurora/bin
  ./OPBackup.sh /openpages-shared/temp nosrvrst
  ls -alt /openpages-shared/temp
}

oc exec openpages-${openpage_name}-sts-0 -- bash -c "$(typeset -f backup_application_storage); backup_application_storage" &> /dev/null

storage_file=$(oc exec -it openpages-${openpage_name}-sts-0 -- /bin/bash -c "cd /openpages-shared/temp ; ls -lt *.zip | head -n 1 | awk '{print \$9}'" 2> /dev/null)
# remove trailing \r
storage_file="${storage_file%%[[:cntrl:]]}"
echo "- Copy ${storage_file} from the pod locally"
oc rsync openpages-${openpage_name}-sts-0:/openpages-shared/temp/${storage_file} . --progress=true 2> /dev/null

echo "- Backup Application Configuration"
# Backup application storage in pod
backup_application_configuration() {
  cd /opt/ibm/OpenPages/aurora/bin
  ./OPBackup.sh /openpages-shared/openpages-backup-restore app-cp4d nosrvrst
  ls -alt /openpages-shared/openpages-backup-restore
}

oc exec openpages-${openpage_name}-sts-0 -- bash -c "$(typeset -f backup_application_configuration); backup_application_configuration" &> /dev/null

configuration_file=$(oc exec -it openpages-${openpage_name}-sts-0 -- /bin/bash -c "cd /openpages-shared/openpages-backup-restore ; ls -lt *.zip | head -n 1 | awk '{print \$9}'" 2> /dev/null)
# remove trailing \r
configuration_file="${configuration_file%%[[:cntrl:]]}"
echo "- Copy ${configuration_file} from the pod locally"
oc rsync openpages-${openpage_name}-sts-0:/openpages-shared/openpages-backup-restore/${configuration_file} . --progress=true 2> /dev/null

echo "==== Copy secrets ===="
encryption_key_pw=$(oc get secret openpages-${openpage_name}-platform-secret -o jsonpath="{.data.encryption-key-pw}")
opsystem_pw=$(oc get secret openpages-${openpage_name}-platform-secret -o jsonpath="{.data.opsystem-pw}")
keystore_pw=$(oc get secret openpages-${openpage_name}-platform-secret -o jsonpath="{.data.keystore-pw}")
echo "- encryption_key_pw=${encryption_key_pw}" | cat -v
echo "- opsystem_pw=${opsystem_pw}"
echo "- keystore_pw=${keystore_pw}"

op_user_pwd=$(oc get secret openpages-${openpage_name}-initialpw-secret -o jsonpath="{.data.OpenPagesAdministrator}")
echo "- op_user_pwd=${op_user_pwd}"

echo "==== Save data to zip file ===="
echo "- parameter file creattion"
cat > $PARAMETER_FILE <<EOF
---
  source_ocp:
    OCP_URL: ${OCP_URL}
    OCP_USER: ${OCP_USER}
    OCP_PWD: ${OCP_PWD}
    OCP_PROJECT: ${OCP_PROJECT}
  openpage_user:
    OP_USER: ${OP_USER}
    CP4D_USER: ${CP4D_USER}
  source_instance_id:
    instance_id: ${instance_id}
    openpage_name: ${openpage_name}
  directories:
    WORK_DIR: ${WORK_DIR}
    PARAMETER_FILE: ${PARAMETER_FILE}
  backup_params:
    SECRETS: ${secrets}
    backup_name: ${backup_name}
    storage_file: ${storage_file}
    configuration_file: ${configuration_file}
  keys:
    encryption_key_pw: ${encryption_key_pw}
    opsystem_pw: ${opsystem_pw}
    keystore_pw: ${keystore_pw}
    op_user_pwd: ${op_user_pwd}
EOF

echo ": === Backup Done ===="
echo "- Transfer the ${WORK_DIR} to the target bastion server"
echo "- Run the restore.sh script"
