# Runtime-built tools image: origin-cli plus make, jq, and helm.
# run.sh builds this once per OpenShift minor when it is not already present locally.
ARG OCP_MINOR=4.18
FROM quay.io/openshift/origin-cli:${OCP_MINOR}

USER 0
RUN dnf install -y -q make jq && dnf clean all
RUN curl -sSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
