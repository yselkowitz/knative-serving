#!/bin/bash

set -x
target_dir=$1

for subcomponent in controller autoscaler autoscaler-hpa activator networking-istio webhook queue; do
    if [[ ${subcomponent} =~ "-hpa" ]]; then
        go_pkg=$subcomponent
        cap_subcomponent="Autoscaler HPA"
    else
        go_pkg=$(echo -e "$subcomponent" | sed -r 's/-/\//g')
        cap_subcomponent=$(echo -e "$subcomponent" | sed -r 's/\<./\U&/g' | sed -r 's/-/ /g')
    fi
    SUBCOMPONENT=$subcomponent \
    CAPITALIZED_SUBCOMPONENT=$cap_subcomponent \
    GO_PACKAGE=$go_pkg \
    envsubst < openshift/productization/generate-dockerfiles/Dockerfile.in > $target_dir/Dockerfile.$subcomponent
done
