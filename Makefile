SHELL := /bin/bash
MAKEFLAGS += --no-print-directory


.SILENT:
.PHONY: dev lab prod clean clean-demo clean-es clean-hv


dev:
	make dev \
	    --directory=./hashicorp-vault-helm
	make install \
	    --directory=./external-secrets-helm
	make demo \
	    --directory=./vault-external-secrets-lab

lab:
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

clean:
	-make clean --ignore-errors \
	    --directory=./vault-external-secrets-lab
	-make clean --ignore-errors \
	    --directory=./external-secrets-helm
	-make clean --ignore-errors \
	    --directory=./hashicorp-vault-helm

clean-demo:
	-make clean --ignore-errors \
	    --directory=./vault-external-secrets-lab

clean-es:
	-make clean --ignore-errors \
            --directory=./external-secrets-helm

clean-hv:
	-make clean --ignore-errors \
            --directory=./hashicorp-vault-helm
