#!/bin/bash
PROJECT=demo
oc apply -k todo-kustomize/overlays/otel -n $PROJECT
# oc patch deployment/todo \
# -p '{"spec":{"template":{"metadata":{"annotations":{"instrumentation.opentelemetry.io/inject-java":"true"}}}}}' \
# -n $PROJECT
# oc set env deploy todo \
# OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector-headless:4318 \
# -n $PROJECT
# oc set env deploy todo OTEL_TRACES_SAMPLER_ARG="drop=/;drop=/q/health/live;drop=/q/health/ready;fallback=always_on" \
#  -n $PROJECT
oc apply -f config/frontend.yaml -n $PROJECT
oc patch deployment/frontend \
    -p '{"spec":{"template":{"metadata":{"annotations":{"instrumentation.opentelemetry.io/inject-nodejs":"true"}}}}}' \
    -n $PROJECT
oc set env deploy frontend OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector-headless:4318 -n $PROJECT
oc set env deploy frontend OTEL_SERVICE_NAME=frontend -n $PROJECT
oc set env deploy frontend OTEL_PROPAGATORS=tracecontext,b3 -n $PROJECT
oc apply -f config/simple-rest-python.yaml -n $PROJECT
oc patch deployment/simple-rest-python \
    -p '{"spec":{"template":{"metadata":{"annotations":{"instrumentation.opentelemetry.io/inject-python":"true"}}}}}' \
    -n $PROJECT
oc set env deploy simple-rest-python OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector-headless:4318 -n $PROJECT
oc set env deploy simple-rest-python OTEL_SERVICE_NAME=simple-rest-python -n $PROJECT
oc apply -f config/otel-go-instrument-scc.yaml -n $PROJECT
oc create sa go-lang-runner
oc adm policy add-scc-to-user otel-go-instrumentation-scc -z go-lang-runner
oc apply -f config/simple-go.yaml -n $PROJECT
oc apply -f config/simple-rest-dotnet.yaml -n $PROJECT
oc patch deployment/simple-rest-dotnet \
    -p '{"spec":{"template":{"metadata":{"annotations":{"instrumentation.opentelemetry.io/inject-dotnet":"true"}}}}}' \
    -n $PROJECT
oc set env deploy simple-rest-python OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector-headless:4318 -n $PROJECT
oc set env deploy simple-rest-python OTEL_SERVICE_NAME=simple-rest-python -n $PROJECT
oc apply -f config/backend.yaml -n $PROJECT
oc wait --for condition=ready --timeout=180s pod -l app=simple-go  -n $PROJECT
oc wait --for condition=ready --timeout=180s pod -l app=frontend  -n $PROJECT
oc wait --for condition=ready --timeout=180s pod -l app=backend  -n $PROJECT
oc wait --for condition=ready --timeout=180s pod -l app=simple-rest-python  -n $PROJECT
oc wait --for condition=ready --timeout=180s pod -l app=simple-rest-dotnet  -n $PROJECT
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