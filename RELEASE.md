# OpenShift Knative Serving Release procedure

The OpenShift Knative Serving release cut is mostly automated and requires only two manual steps for enabling the CI runs on the `openshift/release` repository.

No manual creation of a midstream `release-v1.x` branch is needed. The nightly Jenkins job, does create a `release` branch, as soon as the upstream has created a new release tag. The code for this script is located in this [script](./openshift/release/mirror-upstream-branches.sh), which does mirror the upstream release tag to our midstream `release` branches.

## Enable CI for the release branch

* Create a fork and clone of https://github.com/openshift/release into your `$GOPATH`
* On your `openshift/knative-serving` root folder checkout the new `release-vX.Y` branch and run:

```bash
# Invoke CI config generation, and mirroring images

make update-ci
```

The above `make update-ci` adds new CI configuration to the `openshift/release` repository and afterwards shows which new files were added, like below:

```bash
┌────────────────────────────────────────────────────────────┐
│ Summary...                                                 │
└────────────────────────────────────────────────────────────┘
│─── Modified files in /home/knakayam/.go/src/github.com/openshift/release
core-services/image-mirroring/knative/mapping_knative_v1_3_quay
│─── New files in /home/knakayam/.go/src/github.com/openshift/release
ci-operator/config/openshift/knative-serving/openshift-knative-serving-release-v1.3__410.yaml
ci-operator/config/openshift/knative-serving/openshift-knative-serving-release-v1.3__46.yaml
ci-operator/config/openshift/knative-serving/openshift-knative-serving-release-v1.3__47.yaml
ci-operator/config/openshift/knative-serving/openshift-knative-serving-release-v1.3__48.yaml
ci-operator/config/openshift/knative-serving/openshift-knative-serving-release-v1.3__49.yaml
ci-operator/jobs/openshift/knative-serving/openshift-knative-serving-release-v1.3-periodics.yaml
ci-operator/jobs/openshift/knative-serving/openshift-knative-serving-release-v1.3-postsubmits.yaml
ci-operator/jobs/openshift/knative-serving/openshift-knative-serving-release-v1.3-presubmits.yaml
┌────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ Commit changes to /home/knakayam/.go/src/github.com/openshift/release and create a PR                                  │
└────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

As stated by the `make` target, these changes need to be PR'd against that repository. Once the PR is merged, the CI jobs for the new `release-vX.Y` repo is done.

### Serverless Operator

_Making use of the midstream release on the serverless operator is discussed on its own release manual..._
