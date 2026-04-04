#!/usr/bin/env bash
# Container-side driver: install anything origin-cli omits, authenticate to the cluster, verify
# the CLI image minor matches the cluster, then delegate to make at /work.
set -euo pipefail

WORKFLOW_TARGET="${WORKFLOW_TARGET:-lab-demo}"

: "${OCP_MINOR_TAG:?OCP_MINOR_TAG must be set (use run.sh)}"
: "${CONTAINER_IMAGE_REF:?CONTAINER_IMAGE_REF must be set (use run.sh)}"

if [[ "${CONTAINER_IMAGE_REF}" == *:latest ]] || [[ "${OCP_MINOR_TAG}" == *latest* ]]; then
	echo "Refusing to run workflow with :latest; use run.sh to pin cluster minor." >&2
	exit 1
fi

# origin-cli is minimal; recipes expect make, jq, and helm on PATH.
if ! command -v make >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
	echo "Installing make and jq..."
	dnf install -y -q make jq
fi

if ! command -v helm >/dev/null 2>&1; then
	echo "Installing Helm 3..."
	curl -sSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

export PATH="/usr/local/bin:${PATH}"

# Without this, the Makefile would recurse into run.sh again; we are already in the right container.
export WORKFLOW_IN_CONTAINER=1

if [[ "${SKIP_OC_LOGIN:-}" == "1" ]]; then
	echo "Using mounted kubeconfig (already logged in on host)..."
	oc whoami >/dev/null || {
		echo "ERROR: kubeconfig not valid inside container." >&2
		exit 1
	}
else
	: "${OPENSHIFT_API_URL:?OPENSHIFT_API_URL is required when not using host kubeconfig}"
	: "${CLUSTER_ADMIN_USERNAME:?CLUSTER_ADMIN_USERNAME is required when not using host kubeconfig}"
	: "${CLUSTER_ADMIN_PASSWORD:?CLUSTER_ADMIN_PASSWORD is required when not using host kubeconfig}"
	echo "Logging in to cluster API..."
	# Same semantics as run.sh: tolerate untrusted/lab API certs when OC_INSECURE_TLS is true.
	oc login --insecure-skip-tls-verify="${OC_INSECURE_TLS:-true}" "${OPENSHIFT_API_URL}" \
		-u "${CLUSTER_ADMIN_USERNAME}" -p "${CLUSTER_ADMIN_PASSWORD}" >/dev/null
fi

# Fail fast if run.sh picked the wrong origin-cli tag (avoids debugging confusing oc/server mismatches later).
cluster_full="$(oc get clusterversion version -o jsonpath='{.status.desired.version}')"
cluster_minor="$(echo "${cluster_full}" | cut -d. -f1,2)"
if [[ "${cluster_minor}" != "${OCP_MINOR_TAG}" ]]; then
	echo "ERROR: origin-cli image tag minor (${OCP_MINOR_TAG}) does not match cluster minor (${cluster_minor} from ${cluster_full})." >&2
	exit 1
fi

echo "[workflow] OpenShift cluster version: ${cluster_full}"
echo "[workflow] origin-cli container image: ${CONTAINER_IMAGE_REF} (tag ${OCP_MINOR_TAG} matches cluster)"

echo "Running make ${WORKFLOW_TARGET}..."
exec make -C /work "${WORKFLOW_TARGET}"
