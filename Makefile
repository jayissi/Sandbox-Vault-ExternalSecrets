SHELL := /bin/bash

.PHONY: install-dev install-lab install-prod uninstall clean-demo clean-es clean-hv


install-dev:
	make dev \
	    --directory=./hashicorp-vault-helm
	make install \
	    --directory=./external-secrets-helm
	/bin/bash -c 'sleep 30s'
	make demo \
	    --directory=./vault-external-secrets-lab

#install-lab:
#	make lab \
#	    --directory=./hashicorp-vault-helm
#	make install \
#	    --directory=./external-secrets-helm
#	/bin/bash -c 'sleep 30s'
#	make demo \
#	    --directory=./vault-external-secrets-lab
#
#install-prod:
#	make prod \
#	    --directory=./hashicorp-vault-helm
#	make install \
#	    --directory=./external-secrets-helm
#	/bin/bash -c 'sleep 30s'
#	make demo \
#	    --directory=./vault-external-secrets-lab

uninstall:
	make clean-up --ignore-errors \
	    --directory=./vault-external-secrets-lab
	make uninstall --ignore-errors \
	    --directory=./external-secrets-helm
	make uninstall --ignore-errors \
	    --directory=./hashicorp-vault-helm

clean-demo:
	make clean-up --ignore-errors \
	    --directory=./vault-external-secrets-lab

clean-es:
	make uninstall --ignore-errors \
            --directory=./external-secrets-helm

clean-hv:
	make uninstall --ignore-errors \
            --directory=./hashicorp-vault-helm
