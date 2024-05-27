#
#!/bin/bash
#

JQ="/usr/bin/jq"
INIT_COUNTER=0
LOOP_COUNTER=1
VAULT_KEYS_FILE="$PWD/.vault-init.txt"
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

eval ${OC_EXEC_VAULT} vault operator init -format=json -key-shares ${UNSEAL_SHARES} -key-threshold ${UNSEAL_THRESHOLD} > ${VAULT_KEYS_FILE}
echo "Root Token: $(eval ${JQ} -r '.root_token' ${VAULT_KEYS_FILE})"
echo "Vault URL: https://$(oc get routes.route.openshift.io vault -n vault -o jsonpath --template='{.spec.host}{"\n"}')"
printf "\n"
echo "Vault's Full JSON Payload" 
eval ${JQ} '.' ${VAULT_KEYS_FILE}
sleep 10


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
    oc exec -n vault -ti vault-$i -- vault operator unseal $(eval ${JQ} -r ".unseal_keys_b64[$x]" ${VAULT_KEYS_FILE})
    if (( LOOP_COUNTER == UNSEAL_THRESHOLD + 1 ));
    then
      LOOP_COUNTER=1
    fi
    printf "\n\n\n"
  done
done


echo "-------------------------------------------------------------------------------"
echo "⎈                         First login via Root Token                         ⎈"
echo "-------------------------------------------------------------------------------"

eval ${OC_EXEC_VAULT} vault login $(eval ${JQ} -r '.root_token' ${VAULT_KEYS_FILE})


printf "\n\n\n"


echo "-------------------------------------------------------------------------------"
echo "⎈                    Enable 'secret/' kv-v2 secret engine                    ⎈"
echo "-------------------------------------------------------------------------------"

eval ${OC_EXEC_VAULT} vault secrets enable --version=2 --path=secret kv


printf "\n\n\n"
