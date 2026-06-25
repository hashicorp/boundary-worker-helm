# Copyright IBM Corp. 2026
#
# KIND cluster topology for the Kubernetes version matrix test.
#
# k8s-version-matrix-test.sh renders this template once per version, replacing
# the version placeholder below with the requested kindest/node tag
# (e.g. v1.36.1) before creating the cluster. This way the same node layout and
# NodePort mappings are exercised across every Kubernetes version.
#
# Edit node roles / extraPortMappings here — the Kubernetes version is injected
# automatically, so do NOT hardcode a version in this file.
# Available node image tags: https://hub.docker.com/r/kindest/node

kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: acceptance
nodes:
- role: control-plane
  image: kindest/node:__K8S_VERSION__
  extraPortMappings:
  - containerPort: 30000
    hostPort: 30000
    protocol: TCP
  - containerPort: 30001
    hostPort: 30001
    protocol: TCP
- role: worker
  image: kindest/node:__K8S_VERSION__
- role: worker
  image: kindest/node:__K8S_VERSION__
