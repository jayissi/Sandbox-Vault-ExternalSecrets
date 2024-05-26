SHELL := /bin/bash
HELM_UPDATE := helm repo update

.PHONY: dev lab prod uninstall clean-demo clean-es clean-hv


dev:
	eval "$(HELM_UPDATE)"
	make dev \
	    --directory=./hashicorp-vault-helm
	make install \
	    --directory=./external-secrets-helm
	make demo \
	    --directory=./vault-external-secrets-lab

lab:
	eval "$(HELM_UPDATE)"
	make lab \
	    --directory=./hashicorp-vault-helm
	make install \
	    --directory=./external-secrets-helm
	make demo \
	    --directory=./vault-external-secrets-lab

prod:
	make prod \
	    --directory=./hashicorp-vault-helm
	make install \
	    --directory=./external-secrets-helm
	make demo \
	    --directory=./vault-external-secrets-lab

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
