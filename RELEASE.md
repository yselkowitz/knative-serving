# OpenShift Knative Serving Release procedure

The OpenShift Knative Serving release cut is mostly automated and requires only two manual steps for enabling the CI runs on the `openshift/release` repository.

No manual creation of a midstream `release-v1.x` branch is needed. The nightly Jenkins job, does create a `release` branch, as soon as the upstream has created a new release tag. The code for this script is located in this [script](./openshift/release/mirror-upstream-branches.sh), which does mirror the upstream release tag to our midstream `release` branches.

## Enable CI for the release branch

TODO
