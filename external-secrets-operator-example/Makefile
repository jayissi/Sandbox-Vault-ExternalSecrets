SHELL := /bin/bash

.PHONY: install uninstall

install:
	@source ./deploy.sh

uninstall:
	@oc delete -f ./manifests/ --ignore-not-found=true
