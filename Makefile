SHELL := /bin/bash

.PHONY: install uninstall

install:
	make install \
	    --directory=./vault-init
	make install \
	    --directory=./external-secrets-custom-ca
	/bin/bash -c 'sleep 90s'
	make install \
	    --directory=./external-secrets-operator-example

uninstall:
	make uninstall --ignore-errors \
	    --directory=./external-secrets-operator-example
	make uninstall --ignore-errors \
	    --directory=./external-secrets-custom-ca
	make uninstall --ignore-errors \
	    --directory=./vault-init
