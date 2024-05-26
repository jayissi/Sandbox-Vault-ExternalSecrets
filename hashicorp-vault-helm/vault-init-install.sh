#
#!/bin/bash
#
INIT_COUNTER=0
LOOP_COUNTER=1
VAULT_POD_COUNT=$(oc get pods -n vault -o=jsonpath='{.items[?(@.metadata.labels.app\.kubernetes\.io\/name=="vault")].metadata.labels.apps\.kubernetes\.io\/pod-index}{"\n"}')


#Clear the screen, move to (0,0):
#  \033[2J
# Clear the screen
#printf '\033[1J'
# Move the cursor up 1 line
#printf '\033[1A'
# Save cursor position
#printf '\033[s'
# Restore cursor position
#printf '\033[u'

/usr/bin/reset

echo "-------------------------------------------------------------------------------"
echo "#                          Starting Vault Initiation                          #"
echo "-------------------------------------------------------------------------------"
oc exec -n vault -ti vault-0 -- vault operator init -format=json > .vault-init.txt
echo "Root Token: $(jq -r '.root_token' .vault-init.txt)"
printf "\n\n"
echo "Vault's Full JSON Payload" 
cat .vault-init.txt | jq
sleep 5


printf "\n\n\n"


for i in $VAULT_POD_COUNT;
do
  for x in $(shuf -i 0-4 -n 3);
  do
    echo "-------------------------------------------------------------------------------"
    echo "#            $LOOP_COUNTER: Joining pod 'vault-$i' using unseal key index: $x               #"
    echo "-------------------------------------------------------------------------------"
    (( LOOP_COUNTER++ ))
    (( INIT_COUNTER++ ))
    if (( $INIT_COUNTER <= 1 ));
    then
      if (( $i > 0 ));
      then
        oc exec -n vault -ti vault-$i -- vault operator raft join http://vault-0.vault-internal:8200
        printf "\n"
      fi
    elif (( $INIT_COUNTER == 3));
    then
      INIT_COUNTER=0
    fi
    oc exec -n vault -ti vault-$i -- vault operator unseal $(jq -r ".unseal_keys_b64[$x]" .vault-init.txt)
    if (( $LOOP_COUNTER == 4));
    then
      LOOP_COUNTER=1
    fi
    printf "\n\n\n"
  done
done


echo "-------------------------------------------------------------------------------"
echo "#                         First login via Root Token                          #"
echo "-------------------------------------------------------------------------------"
oc exec -n vault -ti vault-0 -- vault login $(jq -r '.root_token' .vault-init.txt)

printf "\n\n\n"

echo "-------------------------------------------------------------------------------"
echo "#                           Enable 'secret/' kv-v2                            #"
echo "-------------------------------------------------------------------------------"
oc exec -n vault -ti vault-0 -- vault secrets enable --version=2 --path=secret kv

printf "\n\n\n"
