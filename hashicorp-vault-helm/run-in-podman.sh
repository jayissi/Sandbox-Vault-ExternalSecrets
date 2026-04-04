#!/usr/bin/env bash
# Run tooling inside quay.io/openshift/origin-cli:<OpenShift minor> (e.g. 4.18) matching the cluster.
set -euo pipefail

# 1) OCP_ORIGIN_CLI_IMAGE — full ref, e.g. quay.io/openshift/origin-cli:4.18
# 2) oc get clusterversion — same minor as the running cluster
# 3) OCP_MINOR_VERSION — e.g. 4.18 when oc cannot reach the API
resolve_origin_cli_image() {
	if [[ -n "${OCP_ORIGIN_CLI_IMAGE:-}" ]]; then
		echo "${OCP_ORIGIN_CLI_IMAGE}"
		return
	fi
	if [[ -n "${OCP_MINOR_VERSION:-}" ]]; then
		echo "quay.io/openshift/origin-cli:${OCP_MINOR_VERSION}"
		return
	fi
	local minor
	minor="$(oc get clusterversion version -o jsonpath='{.status.desired.version}' 2>/dev/null | cut -d. -f1,2)"
	if [[ -n "${minor}" ]]; then
		echo "quay.io/openshift/origin-cli:${minor}"
		return
	fi
	echo "Set OCP_ORIGIN_CLI_IMAGE, OCP_MINOR_VERSION, or use oc against the cluster to resolve the origin-cli tag." >&2
	exit 1
}

readonly CONTAINER_IMAGE="$(resolve_origin_cli_image)"

exec podman run --rm -it \
	-v "${PWD}:/work:z" \
	-w /work \
	"${CONTAINER_IMAGE}" \
	"$@"
