#
#!/bin/bash
#

JQ="/usr/bin/jq"
INIT_COUNTER=0
LOOP_COUNTER=1
VAULT_KEYS_FILE=".vault-init.txt"
VAULT_INIT_SECRET_NAME="vault-operator-init"
UNSEAL_SHARES=5
UNSEAL_THRESHOLD=3
VAULT_POD_COUNT="oc get pods -n vault -o=jsonpath='{.items[?(@.metadata.labels.app\.kubernetes\.io\/name==\"vault\")].metadata.labels.apps\.kubernetes\.io\/pod-index}{\"\n\"}'"
OC_EXEC_VAULT="oc exec -n vault -ti vault-0 --"


# Clear the screen, move to (0,0):
#  \033[2J
# Clear the screen
#printf '\033[1J'
# Move the cursor up 1 line
#printf '\033[1A'
# Save cursor position
#printf '\033[s'
# Restore cursor position
#printf '\033[u'


# Clear the screen
/usr/bin/clear


echo "-------------------------------------------------------------------------------"
echo "⎈                          Starting Vault Initiation                         ⎈"
echo "-------------------------------------------------------------------------------"

TEMP_DIR=$(mktemp --directory --tmpdir=${PWD})
VAULT_KEYS_FILE="${TEMP_DIR}/${VAULT_KEYS_FILE}"
eval ${OC_EXEC_VAULT} vault operator init \
  -format=json \
  -key-shares ${UNSEAL_SHARES} \
  -key-threshold ${UNSEAL_THRESHOLD} > ${VAULT_KEYS_FILE}

VAULT_KEYS_PAYLOAD=$(cat ${VAULT_KEYS_FILE})

# Create an OpenShift secret containing vault root keys.
oc create -n vault secret generic ${VAULT_INIT_SECRET_NAME} --from-env-file <(${JQ} -r "to_entries|map(\"\(.key)=\(.value|tostring)\")|.[]" ${VAULT_KEYS_FILE})

# Cleanup
/usr/bin/rm -rf ${TEMP_DIR}

echo "Root Token: $(echo ${VAULT_KEYS_PAYLOAD} | ${JQ} -a -r '.root_token')"
echo "Vault URL: https://$(oc get routes.route.openshift.io vault -n vault -o jsonpath --template='{.spec.host}{"\n"}')"
printf "\n"
echo "Vault's Full JSON Payload" 
echo ${VAULT_KEYS_PAYLOAD} | ${JQ} -a '.'


printf "\n\n"


for i in $(eval ${VAULT_POD_COUNT});
do
  for x in $(shuf -i 0-$(( UNSEAL_SHARES - 1 )) -n ${UNSEAL_THRESHOLD});
  do
    (( INIT_COUNTER++ ))
    if (( ${INIT_COUNTER} <= 1 ));
    then
      if (( $i > 0 ));
      then
        echo "-------------------------------------------------------------------------------"
        echo "⎈         Loop Count  ${LOOP_COUNTER}:  Joining server 'vault-$i' to the cluster            ⎈"
        echo "-------------------------------------------------------------------------------"

        oc exec -n vault -ti vault-$i -- vault operator raft join http://vault-0.vault-internal:8200
        printf "\n"
      fi
    elif (( INIT_COUNTER == UNSEAL_THRESHOLD ));
    then
      INIT_COUNTER=0
    fi
    echo "-------------------------------------------------------------------------------"
    echo "⎈       Loop Count ${LOOP_COUNTER}: Unsealing pod 'vault-$i' using unseal key index: $x      ⎈"
    echo "-------------------------------------------------------------------------------"

    (( LOOP_COUNTER++ ))
    oc exec -n vault -ti vault-$i -- vault operator unseal $(echo ${VAULT_KEYS_PAYLOAD} | ${JQ} -r ".unseal_keys_b64[$x]")
    if (( LOOP_COUNTER == UNSEAL_THRESHOLD + 1 ));
    then
      LOOP_COUNTER=1
    fi
    printf "\n\n\n"
  done
done


for i in $(eval ${VAULT_POD_COUNT});
do
  echo "-------------------------------------------------------------------------------"
  echo "⎈                   First login via Root Token on 'vault-$i'                  ⎈"
  echo "-------------------------------------------------------------------------------"

  oc exec -n vault -ti vault-$i -- vault login $(echo ${VAULT_KEYS_PAYLOAD} | ${JQ} -r '.root_token')
done
unset VAULT_KEYS_PAYLOAD


printf "\n\n\n"


for i in $(eval ${VAULT_POD_COUNT});
do
  echo "-------------------------------------------------------------------------------"
  echo "⎈               Enable Audit File and Socket Logging on 'vault-$i'            ⎈"
  echo "-------------------------------------------------------------------------------"

  oc exec -n vault -ti vault-$i -- vault audit enable -path="vault-${i}_file_audit_" file \
    format=json \
    prefix="ocp_vault-${i}_" \
    file_path=/vault/audit/vault_audit.log

  oc exec -n vault -ti vault-$i -- vault audit enable -path="vault-${i}_socket_audit_" socket \
    address="127.0.0.1:8200" \
    socket_type=tcp
done


printf "\n\n\n"


echo "-------------------------------------------------------------------------------"
echo "⎈                    Enable 'secret/' kv-v2 secret engine                    ⎈"
echo "-------------------------------------------------------------------------------"

eval ${OC_EXEC_VAULT} vault secrets enable --version=2 --path=secret kv


printf "\n\n\n"
