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
oc create -f config/otel-go-instrument-scc.yaml -n $PROJECT
oc create sa go-lang-runner
oc adm policy add-scc-to-user otel-go-instrumentation-scc -z go-lang-runner
oc create -f config/simple-go.yaml -n $PROJECT
oc create -f config/backend.yaml -n $PROJECT
oc wait --for condition=ready --timeout=180s pod -l app=simple-go  -n $PROJECT
oc wait --for condition=ready --timeout=180s pod -l app=frontend  -n $PROJECT
oc wait --for condition=ready --timeout=180s pod -l app=backend  -n $PROJECT
oc wait --for condition=ready --timeout=180s pod -l app=todo  -n $PROJECT
FRONTEND_URL=https://$(oc get route frontend -n $PROJECT -o jsonpath='{.spec.host}')
TODO_URL=https://$(oc get route todo -n $PROJECT -o jsonpath='{.spec.host}')
COUNT=0
while [ $COUNT -lt 10 ];
do 
  curl -v $FRONTEND_URL
  SLEEP=$(( ( RANDOM % 5 )  + 1 ))
  curl -v $TODO_URL
  SLEEP=$(( ( RANDOM % 5 )  + 1 ))
  COUNT=$((COUNT+1))
done