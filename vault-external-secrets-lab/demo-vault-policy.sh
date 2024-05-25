oc exec -n vault -ti vault-0 -- vault policy write demo -<< EOF
# Read-only permission on secrets stored at 'secret/data/demo'
path "secret/data/demo" {
  capabilities = [ "read" ]
}
EOF
