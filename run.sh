#!/usr/bin/env bash
# Host entrypoint: pick an origin-cli image whose OpenShift minor matches the target cluster,
# then run workflow.sh inside that container with the repo mounted at /work.
# Matching minor avoids subtle oc/API skew when driving the cluster from the CLI.
#
# When you are already logged in with oc on the host, no env vars are required: kubeconfig is
# mounted into the container. Otherwise set OPENSHIFT_API_URL, CLUSTER_ADMIN_USERNAME,
# CLUSTER_ADMIN_PASSWORD for oc login inside the container.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${ROOT}"

CTR="${CONTAINER_ENGINE:-podman}"
KUBECONFIG="${KUBECONFIG:-${HOME}/.kube/config}"
# Lab clusters often use certs oc does not trust by default; insecure mode avoids login failures
# there. Set to "false" when the API presents a proper trust chain (production).
OC_INSECURE_TLS="${OC_INSECURE_TLS:-true}"

# Fallback chain (first success wins): OCP_MINOR_VERSION → host oc + current kubeconfig →
# host oc login with OPENSHIFT_API_URL + admin creds → BOOTSTRAP_OC_IMAGE (host oc runs a one-off
# container whose oc can log in when the host kubeconfig cannot query clusterversion yet).
resolve_ocp_minor() {
	if [[ -n "${OCP_MINOR_VERSION:-}" ]]; then
		echo "${OCP_MINOR_VERSION}"
		return
	fi
	if ! command -v oc >/dev/null 2>&1; then
		echo "Install oc, or set OCP_MINOR_VERSION (e.g. 4.18)." >&2
		exit 1
	fi
	local full
	if full="$(oc get clusterversion version -o jsonpath='{.status.desired.version}' 2>/dev/null)" && [[ -n "${full}" ]]; then
		echo "${full}" | cut -d. -f1,2
		return
	fi
	if [[ -n "${OPENSHIFT_API_URL:-}" && -n "${CLUSTER_ADMIN_USERNAME:-}" && -n "${CLUSTER_ADMIN_PASSWORD:-}" ]]; then
		oc login --insecure-skip-tls-verify="${OC_INSECURE_TLS}" "${OPENSHIFT_API_URL}" \
			-u "${CLUSTER_ADMIN_USERNAME}" -p "${CLUSTER_ADMIN_PASSWORD}" >/dev/null
		full="$(oc get clusterversion version -o jsonpath='{.status.desired.version}')"
		echo "${full}" | cut -d. -f1,2
		return
	fi
	if [[ -z "${BOOTSTRAP_OC_IMAGE:-}" ]]; then
		echo "Not logged in (oc get clusterversion failed). Run: oc login ..." >&2
		echo "Or set OCP_MINOR_VERSION, or OPENSHIFT_API_URL + CLUSTER_ADMIN_USERNAME + CLUSTER_ADMIN_PASSWORD." >&2
		exit 1
	fi
	echo "Discovering version with ${BOOTSTRAP_OC_IMAGE} (set OCP_MINOR_VERSION to skip)." >&2
	"${CTR}" run --rm \
		-e OPENSHIFT_API_URL \
		-e CLUSTER_ADMIN_USERNAME \
		-e CLUSTER_ADMIN_PASSWORD \
		"${BOOTSTRAP_OC_IMAGE}" \
		bash -c "oc login --insecure-skip-tls-verify=\${OC_INSECURE_TLS} \"\${OPENSHIFT_API_URL}\" -u \"\${CLUSTER_ADMIN_USERNAME}\" -p \"\${CLUSTER_ADMIN_PASSWORD}\" >/dev/null && oc get clusterversion version -o jsonpath='{.status.desired.version}'" \
		| cut -d. -f1,2
}

OCP_MINOR="$(resolve_ocp_minor)"
IMAGE="quay.io/openshift/origin-cli:${OCP_MINOR}"

if [[ "${OCP_MINOR}" == *latest* ]] || [[ "${IMAGE}" == *:latest ]]; then
	echo "Refusing to run: resolved image must use an OpenShift minor tag (e.g. 4.18), not :latest." >&2
	exit 1
fi

echo "Using OpenShift CLI image: ${IMAGE} (cluster minor ${OCP_MINOR})"

# Only pull the image when it is not already available locally (saves ~10-15 s per run).
if "${CTR}" image exists "${IMAGE}" 2>/dev/null; then
	echo "Image ${IMAGE} already present locally; skipping pull."
else
	if ! "${CTR}" pull "${IMAGE}"; then
		echo "Failed to pull ${IMAGE}. Set OCP_MINOR_VERSION to a tag that exists on quay.io/openshift/origin-cli." >&2
		exit 1
	fi
fi

# Env and mounts for workflow.sh: target make goal, pinned minor/image for validation, TLS flag,
# repo at /work with :z so rootless Podman SELinux can read the tree.
RUN_OPTS=(
	-e WORKFLOW_TARGET
	-e OCP_MINOR_TAG="${OCP_MINOR}"
	-e CONTAINER_IMAGE_REF="${IMAGE}"
	-e OC_INSECURE_TLS
	-v "${ROOT}:/work:z"
	-w /work
)

# Prefer host kubeconfig when already authenticated (no password in container).
# Flatten copies merged kubeconfig into one file: bind-mounting the host path as root in the
# container breaks when the file is mode 600 and the engine maps UIDs (rootless Podman).
# World-readable temp is a deliberate tradeoff; the file is deleted on exit.
TMPKCFG=""
cleanup() { [[ -n "${TMPKCFG}" && -f "${TMPKCFG}" ]] && rm -f "${TMPKCFG}" || true; }
# Always remove the kubeconfig temp; EXIT covers normal exit, signals, and failures before podman run returns.
trap cleanup EXIT

if [[ -f "${KUBECONFIG}" ]] && oc get clusterversion version &>/dev/null; then
	TMPKCFG="$(mktemp)"
	oc config view --flatten > "${TMPKCFG}"
	chmod 644 "${TMPKCFG}"
	RUN_OPTS+=(-e SKIP_OC_LOGIN=1)
	RUN_OPTS+=(-e KUBECONFIG=/root/.kube/config)
	# :Z private relabel for this mount only (contrast :z on the repo); kubeconfig path must be readable in-container under SELinux.
	RUN_OPTS+=(-v "${TMPKCFG}:/root/.kube/config:Z")
else
	RUN_OPTS+=(-e OPENSHIFT_API_URL)
	RUN_OPTS+=(-e CLUSTER_ADMIN_USERNAME)
	RUN_OPTS+=(-e CLUSTER_ADMIN_PASSWORD)
fi

# --rm drops the throwaway container after workflow.sh; same shell keeps the temp kubeconfig until then.
"${CTR}" run --rm \
	"${RUN_OPTS[@]}" \
	"${IMAGE}" \
	bash /work/workflow.sh
ret=$?
cleanup
exit "${ret}"
