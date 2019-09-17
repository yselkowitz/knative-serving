#!/bin/bash -x

for component in serving; do
    for subcomponent in controller autoscaler activator networking-istio networking-certmanager webhook queue; do
        m4 -DCOMPONENT=$component -DSUBCOMPONENT=$subcomponent Dockerfile.m4 > ../dist-git/Dockerfile.$subcomponent
    done
done
