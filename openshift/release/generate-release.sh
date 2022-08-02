#!/usr/bin/env bash

root="$(dirname "${BASH_SOURCE[0]}")"

source $(dirname $0)/resolve.sh

release=$1
output_file="openshift/release/knative-serving-${release}.yaml"

resolve_resources "config/core/ config/hpa-autoscaling/" "$output_file"

${root}/download_release_artifacts.sh $release
