#!/bin/bash
SLEEP=60
PROJECT=demo
oc new-project $PROJECT
oc create -f config/tempo-sub.yaml
sleep $SLEEP
cat config/tempoMonolithic.yaml | sed 's/PROJECT/'$PROJECT'/g' | oc create -f -
oc wait --for condition=ready --timeout=300s pod -l app.kubernetes.io/name=tempo-operator  -n openshift-tempo-operator
clear
oc get po -l app.kubernetes.io/name=tempo-operator -n openshift-tempo-operator
oc get csv -n openshift-operators
oc wait --for condition=ready --timeout=300s pod -l app.kubernetes.io/name=tempo-monolithic -n $PROJECT
oc get po -l app.kubernetes.io/component=tempo -n $PROJECT
oc create -f config/otel-sub.yaml
sleep $SLEEP
oc wait --for condition=ready --timeout=300s pod -l app.kubernetes.io/name=opentelemetry-operator -n openshift-operators
clear
oc get csv -n openshift-operators
clear
TEMPO=tempo-sample-gateway:4317
TEMPO_URL=tempo-sample-gateway.$PROJECT.svc.cluster.local
cat config/otel-collector-multi-tenant.yaml| \
sed 's/change_endpoint: .*/endpoint: '$TEMPO'/' | \
sed 's/change_server_name_override: .*/server_name_override: '$TEMPO_URL'/' | \
oc apply -n $PROJECT -f -
oc wait --for condition=ready --timeout=180s pod -l app.kubernetes.io/name=otel-collector  -n $PROJECT
oc get po -l  app.kubernetes.io/managed-by=opentelemetry-operator -n $PROJECT
oc create -f config/observability-sub.yaml
sleep $SLEEP
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
oc set env deploy frontend OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector-headless:4318 -n $PROJECT
oc set env deploy frontend OTEL_SERVICE_NAME=frontend -n $PROJECT
oc set env deploy frontend OTEL_PROPAGATORS=tracecontext,b3 -n $PROJECT
oc create -f config/simple-rest-python.yaml -n $PROJECT
oc patch deployment/simple-rest-python \
    -p '{"spec":{"template":{"metadata":{"annotations":{"instrumentation.opentelemetry.io/inject-python":"true"}}}}}' \
    -n $PROJECT
oc set env deploy simple-rest-python OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector-headless:4318 -n $PROJECT
oc set env deploy simple-rest-python OTEL_SERVICE_NAME=simple-rest-python -n $PROJECT
oc create -f config/otel-go-instrument-scc.yaml -n $PROJECT