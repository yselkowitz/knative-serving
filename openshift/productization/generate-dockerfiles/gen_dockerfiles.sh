#!/bin/bash -x

target_dir=$1

component=Serving

for subcomponent in Activator Autoscaler Autoscaler-HPA \
                    Networking-Istio Networking-CertManager Networking-NSCert \
                    Queue Webhook; \
do
    CAPITALIZED_COMPONENT=$component \
    CAPITALIZED_SUBCOMPONENT=$(echo -e "$subcomponent" | sed -e 's/-/ /g') \
    COMPONENT=$(echo -e "$component" | sed -e 's/\(.*\)/\L\1/g') \
    SUBCOMPONENT=$(echo -e "$subcomponent" | sed -e 's/\(.*\)/\L\1/g') \
    GO_PACKAGE=$(echo -e "$SUBCOMPONENT" | sed -e 's/networking-/networking\//g') \
    envsubst \
      < openshift/productization/generate-dockerfiles/Dockerfile.in \
      > ${target_dir}/Dockerfile.$subcomponent
done
