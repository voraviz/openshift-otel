#!/bin/bash
SLEEP=60
PROJECT=demo
oc new-project $PROJECT
oc create -f config/tempo-sub.yaml
sleep 60
oc wait --for condition=ready --timeout=300s pod -l app.kubernetes.io/name=tempo-operator  -n openshift-tempo-operator
clear
oc get po -l app.kubernetes.io/name=tempo-operator -n openshift-tempo-operator
oc get csv -n openshift-operators
oc wait --for condition=ready --timeout=300s pod -l app.kubernetes.io/name=tempo-monolithic -n $PROJECT
oc get po -l app.kubernetes.io/component=tempo -n $PROJECT
oc create -f config/otel-sub.yaml
sleep 60
oc wait --for condition=ready --timeout=300s pod -l app.kubernetes.io/name=opentelemetry-operator -n openshift-operators
clear
oc get csv -n openshift-operators
clear
cat config/otel-collector-multi-tenant.yaml | sed 's/PROJECT/'$PROJECT'/' | oc apply -n $PROJECT -f -
oc wait --for condition=ready --timeout=180s pod -l app.kubernetes.io/name=otel-collector  -n $PROJECT
oc get po -l  app.kubernetes.io/managed-by=opentelemetry-operator -n $PROJECT
oc create -f config/observability-sub.yaml
sleep 60
oc create -f config/ui-plugin.yaml
oc create -f config/instrumentation.yaml -n $PROJECT
oc apply -k todo-kustomize/base -n $PROJECT
oc patch deployment/todo \
-p '{"spec":{"template":{"metadata":{"annotations":{"instrumentation.opentelemetry.io/inject-java":"true"}}}}}' \
-n $PROJECT
oc set env deploy todo \
OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector-headless:4318 \
-n $PROJECT
oc set env deploy todo OTEL_TRACES_SAMPLER_ARG="drop=/;drop=/q/health/live;drop=/q/health/ready;fallback=always_on" \
 -n $PROJECT
oc create -f config/frontend.yaml -n $PROJECT
oc patch deployment/frontend \
    -p '{"spec":{"template":{"metadata":{"annotations":{"instrumentation.opentelemetry.io/inject-nodejs":"true"}}}}}' \
    -n $PROJECT
oc create -f config/otel-go-instrument-scc.yaml -n $PROJECT
oc create sa go-lang-runner
oc adm policy add-scc-to-user otel-go-instrumentation-scc -z go-lang-runner
oc create -f config/simple-go.yaml -n $PROJECT
oc create -f config/backend.yaml -n $PROJECT
