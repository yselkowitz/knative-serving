#!/usr/bin/env bash

# shellcheck disable=SC1090
source "$(dirname "$0")/../test/e2e-common.sh"
source "$(dirname "$0")/release/resolve.sh"

readonly SERVING_NAMESPACE=knative-serving
readonly SERVING_INGRESS_NAMESPACE=knative-serving-ingress

# The OLM global namespace was moved to openshift-marketplace since v4.2
# ref: https://jira.coreos.com/browse/OLM-1190
readonly OLM_NAMESPACE="openshift-marketplace"

# Determine if we're running locally or in CI.
if [ -n "$OPENSHIFT_BUILD_NAMESPACE" ]; then
  TEST_IMAGE_TEMPLATE=$(cat <<-END
{{- with .Name }}
{{- if eq . "volumes"}}$KNATIVE_SERVING_TEST_VOLUMES{{end -}}
{{- if eq . "readiness"}}$KNATIVE_SERVING_TEST_READINESS{{end -}}
{{- if eq . "pizzaplanetv1"}}$KNATIVE_SERVING_TEST_PIZZAPLANETV1{{end -}}
{{- if eq . "pizzaplanetv2"}}$KNATIVE_SERVING_TEST_PIZZAPLANETV2{{end -}}
{{- if eq . "helloworld"}}$KNATIVE_SERVING_TEST_HELLOWORLD{{end -}}
{{- if eq . "runtime"}}$KNATIVE_SERVING_TEST_RUNTIME{{end -}}
{{- if eq . "timeout"}}$KNATIVE_SERVING_TEST_TIMEOUT{{end -}}
{{- if eq . "observed-concurrency"}}$KNATIVE_SERVING_TEST_OBSERVED_CONCURRENCY{{end -}}
{{- if eq . "grpc-ping"}}$KNATIVE_SERVING_TEST_GRPC_PING{{end -}}
{{- if eq . "failing"}}$KNATIVE_SERVING_TEST_FAILING{{end -}}
{{- if eq . "autoscale"}}$KNATIVE_SERVING_TEST_AUTOSCALE{{end -}}
{{- if eq . "wsserver"}}$KNATIVE_SERVING_TEST_WSSERVER{{end -}}
{{- if eq . "httpproxy"}}$KNATIVE_SERVING_TEST_HTTPPROXY{{end -}}
{{- if eq . "singlethreaded"}}$KNATIVE_SERVING_TEST_SINGLETHREADED{{end -}}
{{- if eq . "servingcontainer"}}$KNATIVE_SERVING_TEST_SERVINGCONTAINER{{end -}}
{{- if eq . "sidecarcontainer"}}$KNATIVE_SERVING_TEST_SIDECARCONTAINER{{end -}}
{{- if eq . "hellohttp2"}}$KNATIVE_SERVING_TEST_HELLOHTTP2{{end -}}
{{- if eq . "hellovolume"}}$KNATIVE_SERVING_TEST_HELLOVOLUME{{end -}}
{{- if eq . "invalidhelloworld"}}quay.io/openshift-knative/helloworld:invalid{{end -}}
{{end -}}
END
)
elif [ -n "$DOCKER_REPO_OVERRIDE" ]; then
  readonly TEST_IMAGE_TEMPLATE="${DOCKER_REPO_OVERRIDE}/{{.Name}}"
elif [ -n "$BRANCH" ]; then
  readonly TEST_IMAGE_TEMPLATE="registry.ci.openshift.org/openshift/${BRANCH}:knative-serving-test-{{.Name}}"
elif [ -n "$TEMPLATE" ]; then
  readonly TEST_IMAGE_TEMPLATE="$TEMPLATE"
else
  readonly TEST_IMAGE_TEMPLATE="registry.ci.openshift.org/openshift/knative-nightly:knative-serving-test-{{.Name}}"
fi

env

# Waits until the machineset in the given namespaces scales up to the
# desired number of replicas
# Parameters: $1 - namespace
#             $2 - machineset name
#             $3 - desired number of replicas
function wait_until_machineset_scales_up() {
  echo -n "Waiting until machineset $2 in namespace $1 scales up to $3 replicas"
  for _ in {1..150}; do  # timeout after 15 minutes
    local available
    available=$(oc get machineset -n "$1" "$2" -o jsonpath="{.status.availableReplicas}")
    if [[ ${available} -eq $3 ]]; then
      echo -e "\nMachineSet $2 in namespace $1 successfully scaled up to $3 replicas"
      return 0
    fi
    echo -n "."
    sleep 6
  done
  echo - "Error: timeout waiting for machineset $2 in namespace $1 to scale up to $3 replicas"
  return 1
}

# Waits until the given hostname resolves via DNS
# Parameters: $1 - hostname
function wait_until_hostname_resolves() {
  echo -n "Waiting until hostname $1 resolves via DNS"
  for _ in {1..150}; do  # timeout after 15 minutes
    local output
    output=$(host -t a "$1" | grep 'has address')
    if [[ -n "${output}" ]]; then
      echo -e "\n${output}"
      return 0
    fi
    echo -n "."
    sleep 6
  done
  echo -e "\n\nERROR: timeout waiting for hostname $1 to resolve via DNS"
  return 1
}

# Loops until duration (car) is exceeded or command (cdr) returns non-zero
function timeout() {
  SECONDS=0; TIMEOUT=$1; shift
  while eval $*; do
    sleep 5
    [[ $SECONDS -gt $TIMEOUT ]] && echo "ERROR: Timed out" && return 1
  done
  return 0
}

function update_csv(){
  local SERVING_DIR=$1

  source ./hack/lib/metadata.bash
  local SERVING_VERSION=$(metadata.get dependencies.serving)
  local EVENTING_VERSION=$(metadata.get dependencies.eventing)
  local KOURIER_VERSION=$(metadata.get dependencies.kourier)
  local KOURIER_MINOR_VERSION=${KOURIER_VERSION%.*}    # e.g. "0.21.0" => "0.21"

  local KOURIER_CONTROL="registry.ci.openshift.org/openshift/knative-v${KOURIER_VERSION}:kourier"
  local KOURIER_GATEWAY=$(grep -w "docker.io/maistra/proxyv2-ubi8" $SERVING_DIR/third_party/kourier-latest/kourier.yaml  | awk '{print $NF}')
  local CSV="olm-catalog/serverless-operator/manifests/serverless-operator.clusterserviceversion.yaml"

  # Install CatalogSource in OLM namespace
  # TODO: Rework this into a loop
  sed -i -e "s|\"registry.ci.openshift.org/openshift/knative-.*:knative-serving-queue\"|\"${KNATIVE_SERVING_QUEUE}\"|g"                   ${CSV}
  sed -i -e "s|\"registry.ci.openshift.org/openshift/knative-.*:knative-serving-activator\"|\"${KNATIVE_SERVING_ACTIVATOR}\"|g"           ${CSV}
  sed -i -e "s|\"registry.ci.openshift.org/openshift/knative-.*:knative-serving-autoscaler\"|\"${KNATIVE_SERVING_AUTOSCALER}\"|g"         ${CSV}
  sed -i -e "s|\"registry.ci.openshift.org/openshift/knative-.*:knative-serving-autoscaler-hpa\"|\"${KNATIVE_SERVING_AUTOSCALER_HPA}\"|g" ${CSV}
  sed -i -e "s|\"registry.ci.openshift.org/openshift/knative-.*:knative-serving-controller\"|\"${KNATIVE_SERVING_CONTROLLER}\"|g"         ${CSV}
  sed -i -e "s|\"registry.ci.openshift.org/openshift/knative-.*:knative-serving-webhook\"|\"${KNATIVE_SERVING_WEBHOOK}\"|g"               ${CSV}
  sed -i -e "s|\"registry.ci.openshift.org/openshift/knative-.*:knative-serving-domain-mapping\"|\"${KNATIVE_SERVING_DOMAIN_MAPPING}\"|g"                       ${CSV}
  sed -i -e "s|\"registry.ci.openshift.org/openshift/knative-.*:knative-serving-domain-mapping-webhook\"|\"${KNATIVE_SERVING_DOMAIN_MAPPING_WEBHOOK}\"|g"       ${CSV}
  sed -i -e "s|\"registry.ci.openshift.org/openshift/knative-.*:knative-serving-storage-version-migration\"|\"${KNATIVE_SERVING_STORAGE_VERSION_MIGRATION}\"|g" ${CSV}

  # Replace kourier's image with the latest ones from third_party/kourier-latest
  sed -i -e "s|\"docker.io/maistra/proxyv2-ubi8:.*\"|\"${KOURIER_GATEWAY}\"|g"                                        ${CSV}
  sed -i -e "s|\"registry.ci.openshift.org/openshift/knative-.*:kourier\"|\"${KOURIER_CONTROL}\"|g"               ${CSV}

  # release-next branch keeps updating the latest manifest in knative-serving-ci.yaml for serving resources.
  # see: https://github.com/openshift/knative-serving/blob/release-next/openshift/release/knative-serving-ci.yaml
  # So mount the manifest and use it by KO_DATA_PATH env value.

  cat << EOF | yq write --inplace --script - $CSV || return $?
- command: update
  path: spec.install.spec.deployments.(name==knative-operator).spec.template.spec.containers.(name==knative-operator).env[+]
  value:
    name: "KO_DATA_PATH"
    value: "/tmp/knative/"
- command: update
  path: spec.install.spec.deployments.(name==knative-operator).spec.template.spec.containers.(name==knative-operator).volumeMounts[+]
  value:
    name: "serving-manifest"
    mountPath: "/tmp/knative/knative-serving/${SERVING_VERSION}"
- command: update
  path: spec.install.spec.deployments.(name==knative-operator).spec.template.spec.volumes[+]
  value:
    name: "serving-manifest"
    configMap:
      name: "ko-data-serving"
      items:
        - key: "knative-serving-ci.yaml"
          path: "knative-serving-ci.yaml"
# eventing
- command: update
  path: spec.install.spec.deployments.(name==knative-operator).spec.template.spec.containers.(name==knative-operator).volumeMounts[+]
  value:
    name: "eventing-manifest"
    mountPath: "/tmp/knative/knative-eventing/${EVENTING_VERSION}"
- command: update
  path: spec.install.spec.deployments.(name==knative-operator).spec.template.spec.volumes[+]
  value:
    name: "eventing-manifest"
    configMap:
      name: "ko-data-eventing"
      items:
        - key: "knative-eventing-ci.yaml"
          path: "knative-eventing-ci.yaml"
# kourier
- command: update
  path: spec.install.spec.deployments.(name==knative-operator).spec.template.spec.containers.(name==knative-operator).volumeMounts[+]
  value:
    name: "kourier-manifest"
    mountPath: "/tmp/knative/ingress/${KOURIER_MINOR_VERSION}"
- command: update
  path: spec.install.spec.deployments.(name==knative-operator).spec.template.spec.volumes[+]
  value:
    name: "kourier-manifest"
    configMap:
      name: "kourier-cm"
      items:
        - key: "kourier.yaml"
          path: "kourier.yaml"
EOF
  cat ./openshift-knative-operator/cmd/operator/kodata/ingress/${KOURIER_MINOR_VERSION}/0-kourier.yaml \
      ./openshift-knative-operator/cmd/operator/kodata/ingress/${KOURIER_MINOR_VERSION}/1-config-network.yaml > /tmp/kourier.yaml

  oc create configmap kourier-cm -n $OPERATORS_NAMESPACE --from-file="/tmp/kourier.yaml" || return $?
}

function install_catalogsource(){

  # And checkout the setup script based on that commit.
  local SERVERLESS_DIR=$(mktemp -d)
  local CURRENT_DIR=$(pwd)
  git clone --depth 1 https://github.com/openshift-knative/serverless-operator.git ${SERVERLESS_DIR}
  pushd ${SERVERLESS_DIR}

  source ./test/lib.bash
  create_namespaces "${SYSTEM_NAMESPACES[@]}"
  update_csv $CURRENT_DIR || return $?
  # Make OPENSHIFT_CI non-empty to build the serverless index and use S-O nightly build images.
  OPENSHIFT_CI="true" ensure_catalogsource_installed || return $?
  # Create a secret for https test.
  trust_router_ca || return $?
  popd
}

function install_knative(){
  header "Installing Knative"
  install_catalogsource || return $?
  create_configmaps || return $?
  deploy_serverless_operator "$CURRENT_CSV" || return $?

  # Wait for the CRD to appear
  timeout 900 '[[ $(oc get crd | grep -c knativeservings) -eq 0 ]]' || return 1

  # Install Knative Serving with initial values in test/config/config-observability.yaml.
  cat <<-EOF | oc apply -f - || return $?
apiVersion: operator.knative.dev/v1alpha1
kind: KnativeServing
metadata:
  name: knative-serving
  namespace: ${SERVING_NAMESPACE}
spec:
  ingress:
    kourier:
      service-type: "LoadBalancer" # To enable gRPC and HTTP2 tests.
  config:
    deployment:
      progressDeadline: "120s"
    observability:
      logging.request-log-template: '{"httpRequest": {"requestMethod": "{{.Request.Method}}",
        "requestUrl": "{{js .Request.RequestURI}}", "requestSize": "{{.Request.ContentLength}}",
        "status": {{.Response.Code}}, "responseSize": "{{.Response.Size}}", "userAgent":
        "{{js .Request.UserAgent}}", "remoteIp": "{{js .Request.RemoteAddr}}", "serverIp":
        "{{.Revision.PodIP}}", "referer": "{{js .Request.Referer}}", "latency": "{{.Response.Latency}}s",
        "protocol": "{{.Request.Proto}}"}, "traceId": "{{index .Request.Header "X-B3-Traceid"}}"}'
      logging.enable-probe-request-log: "true"
      logging.enable-request-log: "true"
EOF

  # Wait for 4 pods to appear first
  timeout 600 '[[ $(oc get pods -n $SERVING_NAMESPACE --no-headers | wc -l) -lt 4 ]]' || return 1
  wait_until_pods_running $SERVING_NAMESPACE || return 1

  wait_until_service_has_external_ip $SERVING_INGRESS_NAMESPACE kourier || fail_test "Ingress has no external IP"
  wait_until_hostname_resolves "$(kubectl get svc -n $SERVING_INGRESS_NAMESPACE kourier -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"

  header "Knative Installed successfully"
}

function create_configmaps(){
  # Create configmap to use the latest manifest.
  oc create configmap ko-data-serving -n $OPERATORS_NAMESPACE --from-file="openshift/release/knative-serving-ci.yaml" || return $?

  # Create eventing manifest. We don't want to do this, but upstream designed that knative-eventing dir is mandatory
  # when KO_DATA_PATH was overwritten.
  oc create configmap ko-data-eventing -n $OPERATORS_NAMESPACE --from-file="openshift/release/knative-eventing-ci.yaml" || return $?
}

function prepare_knative_serving_tests_nightly {
  echo ">> Creating test resources for OpenShift (test/config/)"

  kubectl apply -f test/config/cluster-resources.yaml
  kubectl apply -f test/config/test-resources.yaml

  # Apply resource quota in rq-test namespace, needed for the related e2e test.
  oc apply -f ./test/config/resource-quota/resource-quota.yaml

  # Apply persistent volume claim needed, needed for the related e2e test.
  oc apply -f ./test/config/pvc/pvc.yaml

  oc adm policy add-scc-to-user privileged -z default -n serving-tests
  oc adm policy add-scc-to-user privileged -z default -n serving-tests-alt
  # Adding scc for anyuid to test TestShouldRunAsUserContainerDefault.
  oc adm policy add-scc-to-user anyuid -z default -n serving-tests

  export SYSTEM_NAMESPACE="$SERVING_NAMESPACE"
  export GATEWAY_OVERRIDE=kourier
  export GATEWAY_NAMESPACE_OVERRIDE="$SERVING_INGRESS_NAMESPACE"
  export INGRESS_CLASS=kourier.ingress.networking.knative.dev
}

function run_e2e_tests(){
  header "Running tests"

  local test_name=$1 
  local failed=0

  # Keep this in sync with test/ha/ha.go
  readonly OPENSHIFT_REPLICAS=2
  # TODO: Increase BUCKETS size more than 1 when operator supports configmap/config-leader-election setting.
  readonly OPENSHIFT_BUCKETS=1

  # Changing the bucket count and cycling the controllers will leave around stale
  # lease resources at the old sharding factor, so clean these up.
  kubectl -n ${SYSTEM_NAMESPACE} delete leases --all

  # Wait for a new leader Controller to prevent race conditions during service reconciliation
  wait_for_leader_controller || failed=1

  # Dump the leases post-setup.
  header "Leaders"
  kubectl get lease -n "${SYSTEM_NAMESPACE}"

  # Give the controller time to sync with the rest of the system components.
  sleep 30
  subdomain=$(oc get ingresses.config.openshift.io cluster  -o jsonpath="{.spec.domain}")

  if [ -n "$test_name" ]; then
    oc -n ${SYSTEM_NAMESPACE} patch knativeserving/knative-serving --type=merge --patch='{"spec": {"config": { "features": {"kubernetes.podspec-volumes-emptydir": "enabled"}}}}' || fail_test
    go_test_e2e -tags=e2e -timeout=15m -parallel=1 \
    ./test/e2e ./test/conformance/api/... ./test/conformance/runtime/... \
    -run "^(${test_name})$" \
    --kubeconfig "$KUBECONFIG" \
    --imagetemplate "$TEST_IMAGE_TEMPLATE" \
    --enable-alpha \
    --enable-beta \
    --customdomain=$subdomain \
    --https \
    --skip-cleanup-on-fail \
    --resolvabledomain || failed=$?
    oc -n ${SYSTEM_NAMESPACE} patch knativeserving/knative-serving --type=merge --patch='{"spec": {"config": { "features": {"kubernetes.podspec-volumes-emptydir": "disabled"}}}}' || fail_test

    return $failed
  fi

  local parallel=3

  if [[ $(oc get infrastructure cluster -ojsonpath='{.status.platform}') = VSphere ]]; then
    # Since we don't have LoadBalancers working, gRPC tests will always fail.
    rm ./test/e2e/grpc_test.go
    parallel=2
  fi

  oc -n ${SYSTEM_NAMESPACE} patch knativeserving/knative-serving --type=merge --patch='{"spec": {"config": { "features": {"kubernetes.podspec-volumes-emptydir": "enabled"}}}}' || fail_test
  go_test_e2e -tags=e2e -timeout=30m -parallel=$parallel \
    ./test/e2e ./test/conformance/api/... ./test/conformance/runtime/... \
    --kubeconfig "$KUBECONFIG" \
    --imagetemplate "$TEST_IMAGE_TEMPLATE" \
    --enable-alpha \
    --enable-beta \
    --customdomain=$subdomain \
    --https \
    --skip-cleanup-on-fail \
    --resolvabledomain || failed=1
  oc -n ${SYSTEM_NAMESPACE} patch knativeserving/knative-serving --type=merge --patch='{"spec": {"config": { "features": {"kubernetes.podspec-volumes-emptydir": "disabled"}}}}' || fail_test

  oc -n ${SYSTEM_NAMESPACE} patch knativeserving/knative-serving --type=merge --patch='{"spec": {"config": { "features": {"tag-header-based-routing": "enabled"}}}}' || fail_test
  go_test_e2e -timeout=2m ./test/e2e/tagheader \
    --kubeconfig "$KUBECONFIG" \
    --imagetemplate "$TEST_IMAGE_TEMPLATE" \
    --https \
    --skip-cleanup-on-fail \
    --resolvabledomain || failed=1
  oc -n ${SYSTEM_NAMESPACE} patch knativeserving/knative-serving --type=merge --patch='{"spec": {"config": { "features": {"tag-header-based-routing": "disabled"}}}}' || fail_test

  oc -n ${SYSTEM_NAMESPACE} patch knativeserving/knative-serving --type=merge --patch='{"spec": {"config": { "autoscaler": {"allow-zero-initial-scale": "true"}}}}' || fail_test
  # wait 10 sec until sync.
  sleep 10
  go_test_e2e -timeout=2m ./test/e2e/initscale \
    --kubeconfig "$KUBECONFIG" \
    --imagetemplate "$TEST_IMAGE_TEMPLATE" \
    --https \
    --skip-cleanup-on-fail \
    --resolvabledomain || failed=1
  oc -n ${SYSTEM_NAMESPACE} patch knativeserving/knative-serving --type=merge --patch='{"spec": {"config": { "autoscaler": {"allow-zero-initial-scale": "false"}}}}' || fail_test

  oc -n ${SYSTEM_NAMESPACE} patch knativeserving/knative-serving --type=merge --patch='{"spec": {"config": { "features": {"responsive-revision-gc": "enabled"}}}}' || fail_test
  # immediate_gc
  oc -n ${SYSTEM_NAMESPACE} patch knativeserving/knative-serving --type=merge --patch='{"spec": {"config": { "gc": {"retain-since-create-time":"disabled","retain-since-last-active-time":"disabled","min-non-active-revisions":"0","max-non-active-revisions":"0"}}}}' || fail_test
  go_test_e2e -timeout=2m ./test/e2e/gc \
    --kubeconfig "$KUBECONFIG" \
    --imagetemplate "$TEST_IMAGE_TEMPLATE" \
    --https \
    --skip-cleanup-on-fail \
    --resolvabledomain || failed=1
  oc -n ${SYSTEM_NAMESPACE} patch knativeserving/knative-serving --type=merge --patch='{"spec": {"config": { "features": {"responsive-revision-gc": "disabled"}}}}' || fail_test

  # Run HPA tests
  go_test_e2e -timeout=30m -tags=hpa ./test/e2e \
    --kubeconfig "$KUBECONFIG" \
    --imagetemplate "$TEST_IMAGE_TEMPLATE" \
    --https \
    --skip-cleanup-on-fail \
    --resolvabledomain || failed=1

  # Run init-containers test
  oc -n ${SYSTEM_NAMESPACE} patch knativeserving/knative-serving --type=merge --patch='{"spec": {"config": { "features": {"kubernetes.podspec-volumes-emptydir": "enabled"}}}}' || fail_test
  oc -n ${SYSTEM_NAMESPACE} patch knativeserving/knative-serving --type=merge --patch='{"spec": {"config": { "features": {"kubernetes.podspec-init-containers": "enabled"}}}}' || fail_test
  go_test_e2e -timeout=2m ./test/e2e/initcontainers \
    --kubeconfig "$KUBECONFIG" \
    --imagetemplate "$TEST_IMAGE_TEMPLATE" \
    --https \
    --skip-cleanup-on-fail \
    --resolvabledomain || failed=1
  oc -n ${SYSTEM_NAMESPACE} patch knativeserving/knative-serving --type=merge --patch='{"spec": {"config": { "features": {"kubernetes.podspec-volumes-emptydir": "disabled"}}}}' || fail_test
  oc -n ${SYSTEM_NAMESPACE} patch knativeserving/knative-serving --type=merge --patch='{"spec": {"config": { "features": {"kubernetes.podspec-init-containers": "disabled"}}}}' || fail_test

  # Run PVC test
  oc -n ${SYSTEM_NAMESPACE} patch knativeserving/knative-serving --type=merge --patch='{"spec": {"config": { "features": {"kubernetes.podspec-persistent-volume-claim": "enabled"}}}}' || fail_test
  oc -n ${SYSTEM_NAMESPACE} patch knativeserving/knative-serving --type=merge --patch='{"spec": {"config": { "features": {"kubernetes.podspec-persistent-volume-write": "enabled"}}}}' || fail_test
  oc -n ${SYSTEM_NAMESPACE} patch knativeserving/knative-serving --type=merge --patch='{"spec": {"config": { "features": {"kubernetes.podspec-securitycontext": "enabled"}}}}' || fail_test
  go_test_e2e -timeout=5m ./test/e2e/pvc \
    --kubeconfig "$KUBECONFIG" \
    --imagetemplate "$TEST_IMAGE_TEMPLATE" \
    --enable-alpha \
    --https \
    --skip-cleanup-on-fail \
    --resolvabledomain || failed=1
  oc -n ${SYSTEM_NAMESPACE} patch knativeserving/knative-serving --type=merge --patch='{"spec": {"config": { "features": {"kubernetes.podspec-persistent-volume-claim": "disabled"}}}}' || fail_test
  oc -n ${SYSTEM_NAMESPACE} patch knativeserving/knative-serving --type=merge --patch='{"spec": {"config": { "features": {"kubernetes.podspec-persistent-volume-write": "disabled"}}}}' || fail_test
  oc -n ${SYSTEM_NAMESPACE} patch knativeserving/knative-serving --type=merge --patch='{"spec": {"config": { "features": {"kubernetes.podspec-securitycontext": "disabled"}}}}' || fail_test

  # Run the helloworld test with an image pulled into the internal registry.
  local image_to_tag=$KNATIVE_SERVING_TEST_HELLOWORLD
  oc tag -n serving-tests "$image_to_tag" "helloworld:latest" --reference-policy=local
  go_test_e2e -tags=e2e -timeout=30m ./test/e2e -run "^(TestHelloWorld)$" \
    --https \
    --skip-cleanup-on-fail \
    --resolvabledomain --kubeconfig "$KUBECONFIG" \
    --imagetemplate "image-registry.openshift-image-registry.svc:5000/serving-tests/{{.Name}}" || failed=2

  # Prevent HPA from scaling to make the tests more stable
  oc -n "$SERVING_NAMESPACE" patch hpa activator \
  --type 'merge' \
  --patch '{"spec": {"maxReplicas": '${OPENSHIFT_REPLICAS}', "minReplicas": '${OPENSHIFT_REPLICAS}'}}' || return 1

  # Use sed as the -spoofinterval parameter is not available yet
  sed "s/\(.*requestInterval =\).*/\1 10 * time.Millisecond/" -i vendor/knative.dev/pkg/test/spoof/spoof.go

  # Run HA tests separately as they're stopping core Knative Serving pods
  # Define short -spoofinterval to ensure frequent probing while stopping pods
  go_test_e2e -tags=e2e -timeout=15m -failfast -parallel=1 \
    ./test/ha \
    -replicas="${OPENSHIFT_REPLICAS}" -buckets="${OPENSHIFT_BUCKETS}" -spoofinterval="10ms" \
    --kubeconfig "$KUBECONFIG" \
    --imagetemplate "$TEST_IMAGE_TEMPLATE" \
    --enable-alpha \
    --enable-beta \
    --customdomain=$subdomain \
    --https \
    --skip-cleanup-on-fail \
    --resolvabledomain || failed=3

  return $failed
}

function gather_knative_state {
  logger.info 'Gather knative state'
  local gather_dir="${ARTIFACT_DIR:-/tmp}/gather-knative"
  mkdir -p "$gather_dir"

  oc --insecure-skip-tls-verify adm must-gather \
    --image=quay.io/openshift-knative/must-gather \
    --dest-dir "$gather_dir" > "${gather_dir}/gather-knative.log"
}
