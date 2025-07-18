# OpenShift - OpenTelemetry with Tempo

| ![Logo](images/OpenTelemetry.png)                  | 

- [OpenShift - OpenTelemetry with Tempo](#openshift---opentelemetry-with-tempo)
  - [TL;DR](#tldr)
  - [Operators](#operators)
    - [Tempo Operator](#tempo-operator)
      - [Tempo Monolithic](#tempo-monolithic)
      - [TempoStack](#tempostack)
    - [Distributed Tracing Data Collection Operator](#distributed-tracing-data-collection-operator)
      - [Config OTEL Collector](#config-otel-collector)
    - [Cluster Observability Operator](#cluster-observability-operator)
      - [Tracing UI](#tracing-ui)
  - [Todo Application (with OpenTelemetry library)](#todo-application-with-opentelemetry-library)
  - [TraceQL](#traceql)
  - [OTEL Auto-Instrumentation](#otel-auto-instrumentation)
    - [Todo App (without OpenTelemetry library)](#todo-app-without-opentelemetry-library)
    - [RESTful App](#restful-app)
      - [Node.js](#nodejs)
      - [Python](#python)
      - [Go-lang](#go-lang)
      - [.NET Core](#net-core)
      - [Java App](#java-app)
      - [Test RESTful App](#test-restful-app)
  - [Grafana](#grafana)

## TL;DR

- If you're too busy then try this all in one [bash script](setup.sh) to setup Tempo Monolithic.

## Operators
- Create project demo

```bash
PROJECT=demo
oc new-project $PROJECT
```

### Tempo Operator

- Install [Tempo Operator](config/tempo-sub.yaml)

```bash
oc create -f config/tempo-sub.yaml
oc wait --for condition=ready --timeout=300s pod -l app.kubernetes.io/name=tempo-operator  -n openshift-tempo-operator
oc get po -l app.kubernetes.io/name=tempo-operator -n openshift-tempo-operator
```

Output

```bash
namespace/openshift-tempo-operator created
operatorgroup.operators.coreos.com/openshift-tempo-operator-svgqj created
subscription.operators.coreos.com/tempo-product created
pod/tempo-operator-controller-797d6cb7d6-bg9zz condition met
NAME                                         READY   STATUS    RESTARTS   AGE
tempo-operator-controller-797d6cb7d6-bg9zz   1/1     Running   0          5m41s
```
- Verify operators are installed successfully

```bash
oc get csv -n openshift-operators

```

Output

```bash
NAME                                DISPLAY                          VERSION     REPLACES                            PHASE
tempo-operator.v0.15.4-1            Tempo Operator                   0.15.4-1    tempo-operator.v0.15.3-1            Succeeded
```

#### Tempo Monolithic

- Create [Tempo Monolithic](config/tempoMonolithic.yaml) instance in project demo

```bash
cat config/tempoMonolithic.yaml | sed 's/PROJECT/'$PROJECT'/g' | oc create -f -
```
Output

```bash
clusterrole.rbac.authorization.k8s.io/tempostack-traces-write created
clusterrole.rbac.authorization.k8s.io/tempostack-traces-reader created
clusterrolebinding.rbac.authorization.k8s.io/tempostack-traces-reader created
serviceaccount/otel-collector created
clusterrolebinding.rbac.authorization.k8s.io/tempostack-traces created
tempomonolithic.tempo.grafana.com/sample created
```

- Check TempoMonolithic operator status

```bash
oc wait --for condition=ready --timeout=300s pod -l app.kubernetes.io/name=tempo-monolithic -n $PROJECT
oc get po -l app.kubernetes.io/component=tempo -n $PROJECT
```

Output

```bash
NAME             READY   STATUS    RESTARTS   AGE
tempo-sample-0   5/5     Running   0          59s
```

- Check PVC created by Tempo Operator

```bash
oc get pvc -n $PROJECT
```

Output

```bash
NAME                           STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
tempo-storage-tempo-sample-0   Bound    pvc-13ef64d5-ca36-41a9-bcd1-81e82fa540f5   2Gi        RWO            gp3-csi        <unset>                 2m21s
```

#### TempoStack

- Tempo need S3 bucket for store data. Prepare your S3 bucket. Following example is using the same bucket with OpenShift image registry

```bash
S3_BUCKET=$(oc get configs.imageregistry.operator.openshift.io/cluster -o jsonpath='{.spec.storage.s3.bucket}' -n openshift-image-registry)
REGION=$(oc get configs.imageregistry.operator.openshift.io/cluster -o jsonpath='{.spec.storage.s3.region}' -n openshift-image-registry)
ACCESS_KEY_ID=$(oc get secret image-registry-private-configuration -o jsonpath='{.data.credentials}' -n openshift-image-registry|base64 -d|grep aws_access_key_id|awk -F'=' '{print $2}'|sed 's/^[ ]*//')
SECRET_ACCESS_KEY=$(oc get secret image-registry-private-configuration -o jsonpath='{.data.credentials}' -n openshift-image-registry|base64 -d|grep aws_secret_access_key|awk -F'=' '{print $2}'|sed 's/^[ ]*//')
ENDPOINT=$(echo "https://s3.$REGION.amazonaws.com")
DEFAULT_STORAGE_CLASS=$(oc get sc -A -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}')
```

- Create secret to store S3 bucket's credentials

```bash
oc create secret generic tempo-s3 \
  --from-literal=name=tempo \
  --from-literal=bucket=$S3_BUCKET  \
  --from-literal=endpoint=$ENDPOINT \
  --from-literal=access_key_id=$ACCESS_KEY_ID \
  --from-literal=access_key_secret=$SECRET_ACCESS_KEY \
  -n $PROJECT
```
- Create [TempoStack](config/tempoStack.yaml) instance in project demo 

```bash
cat config/tempoStack-multi-tenant.yaml | sed 's/PROJECT/'$PROJECT'/'  | oc apply -n $PROJECT -f -
oc wait --for condition=ready --timeout=180s pod -l app.kubernetes.io/managed-by=tempo-operator  -n $PROJECT 
oc get po -l  app.kubernetes.io/managed-by=tempo-operator -n $PROJECT
```

### Distributed Tracing Data Collection Operator
- Install [Distributed Tracing Data Collection Operator](config/otel-sub.yaml)

```bash
oc create -f config/otel-sub.yaml
oc wait --for condition=ready --timeout=300s pod -l app.kubernetes.io/name=opentelemetry-operator -n openshift-operators

```

Output

```bash
subscription.operators.coreos.com/opentelemetry-product created
```

- Verify operators are installed successfully

```bash
oc get csv -n openshift-operators
```

Output

```bash
NAME                                DISPLAY                          VERSION     REPLACES                            PHASE
opentelemetry-operator.v0.119.0-2   Red Hat build of OpenTelemetry   0.119.0-2   opentelemetry-operator.v0.119.0-1   Succeeded
tempo-operator.v0.15.4-1            Tempo Operator                   0.15.4-1    tempo-operator.v0.15.3-1            Succeeded
```

#### Config OTEL Collector


  
- Set environment variables for Tempo service name and URL
  
  - TempoMonolithic
    
```bash
TEMPO=tempo-sample-gateway:4317
TEMPO_URL=tempo-sample-gateway.$PROJECT.svc.cluster.local
```

  - TempoStack

```bash
TEMPO=tempo-sample-gateway:8090
TEMPO_URL=tempo-sample-gateway.$PROJECT.svc.cluster.local
```

- Create [OTEL collector](config/otel-collector-multi-tenant.yaml)

```bash
cat config/otel-collector-multi-tenant.yaml|sed 's/change_endpoint: .*/endpoint: '$TEMPO'/' | sed 's/change_server_name_override: .*/server_name_override: '$TEMPO_URL'/' | oc apply -n $PROJECT -f -
oc wait --for condition=ready --timeout=180s pod -l app.kubernetes.io/name=otel-collector  -n $PROJECT
oc get po -l  app.kubernetes.io/managed-by=opentelemetry-operator -n $PROJECT
```

Output of TempoMonolithic

```bash
opentelemetrycollector.opentelemetry.io/otel created
pod/tempo-sample-0 condition met
NAME                              READY   STATUS    RESTARTS   AGE
otel-collector-54bc66dd66-gfl2t   1/1     Running   0          2m6s
```

Output of TempoStack

```bash
pod/tempo-sample-compactor-67474b45d4-sg2l7 condition met
pod/tempo-sample-distributor-648954cc76-njtst condition met
pod/tempo-sample-gateway-c8f6f755f-78jqx condition met
pod/tempo-sample-ingester-0 condition met
pod/tempo-sample-querier-67db7759c5-pgbkg condition met
pod/tempo-sample-query-frontend-656c6bbbdc-h7fjf condition met
NAME                                           READY   STATUS    RESTARTS   AGE
tempo-sample-compactor-67474b45d4-sg2l7        1/1     Running   0          74s
tempo-sample-distributor-648954cc76-njtst      1/1     Running   0          75s
tempo-sample-gateway-c8f6f755f-78jqx           2/2     Running   0          74s
tempo-sample-ingester-0                        1/1     Running   0          74s
tempo-sample-querier-67db7759c5-pgbkg          1/1     Running   0          74s
tempo-sample-query-frontend-656c6bbbdc-h7fjf   3/3     Running   0          74s
```

### Cluster Observability Operator
- Install [Cluster Observability Operator](config/cluster-observability-sub.yaml)

```bash
oc create -f config/observability-sub.yaml
```

Output

```bash
namespace/openshift-cluster-observability-operator created
operatorgroup.operators.coreos.com/openshift-cluster-observability-operator-ds9pl created
subscription.operators.coreos.com/cluster-observability-operator created
```

- Verify operators are installed successfully

```bash
oc get csv -n openshift-operators  
```

Output

```bash
NAME                                    DISPLAY                          VERSION     REPLACES                                PHASE
cluster-observability-operator.v1.1.1   Cluster Observability Operator   1.1.1       cluster-observability-operator.v1.1.0   Succeeded
opentelemetry-operator.v0.119.0-2       Red Hat build of OpenTelemetry   0.119.0-2   opentelemetry-operator.v0.119.0-1       Succeeded
tempo-operator.v0.15.4-1                Tempo Operator                   0.15.4-1    tempo-operator.v0.15.3-1                Succeeded
```

#### Tracing UI
- Create [Tracing UI Plugin](config/ui-plugin.yaml)

```bash
oc create -f config/ui-plugin.yaml
```

Output

```bash
uiplugin.observability.openshift.io/distributed-tracing created
```

- Check that menu Trace is available under Observe

![Observe Menu](images/menu-observe.png)

## Todo Application (with OpenTelemetry library)
- Deploy sample todo application. This application is developed by Quarkus with OpenTelemetry library

```bash
oc create -k todo-kustomize/overlays/otel -n $PROJECT
oc wait --for condition=ready --timeout=180s pod -l app=todo-db  -n $PROJECT 
oc wait --for condition=ready --timeout=180s pod -l app=todo  -n $PROJECT
```
Output
```bash
configmap/todo-db-init created
secret/todo-db created
service/todo created
service/todo-db created
persistentvolumeclaim/todo-db created
persistentvolumeclaim/todo-db-init-data created
deployment.apps/todo created
deployment.apps/todo-db created
route.route.openshift.io/todo created
pod/todo-db-77b5754784-swf7x condition met
pod/todo-7c6bddcdcb-t7pt6 condition met
```

- Verify todo application 
  
  ![](images/todo-topology.png)

- Access todo app and do some operations i.e. add tasks, set task's status to completed and delete tasks.
  
![](images/todo-app.png)

- Navigate to Observe -> Trace
  Select Tempo Instance to *demo/sample* and Tenant to *dev*

  ![](images/trace-todo-main-screen.png)

- Select trace and check its details
  
  Update todo's status

  ![](images/todo-trace-update-todo.png)

  
  SQL Statement

  ![](images/todo-trace-update-todo-sql.png)

## TraceQL

| TraceQL                                                  | Description                                                       |
|----------------------------------------------------------|-------------------------------------------------------------------|
| {trace:id=~"f738c.*"}                                    | Trace ID start with "f738c"                                       |
| {span:id="2f636ff7a3f65a45"}                             | Span ID equals to 2f636ff7a3f65a45                                |
| {span.url.path="/api" && span.http.request.method="GET"} | URL equals to /api and HTTP method is GET                         |
| {span.http.response.status_code >= 500}                  | HTTP status code is greater or equals to 500 ( Server side error) |


![](images/TraceQL-spanId.png)

## OTEL Auto-Instrumentation
- Create [Instrumentation](config/instrumentation.yaml)
```bash
oc create -f config/instrumentation.yaml -n $PROJECT
```
Output
```bash
instrumentation.opentelemetry.io/instrumentation created
```
### Todo App (without OpenTelemetry library)
- Replace Todo Application to version that does not included opentelemetry library

```bash
oc delete -k todo-kustomize/overlays/otel -n $PROJECT
oc apply -k todo-kustomize/overlays/auto-instrument -n $PROJECT
```

Check Kustomize configuration for [Auto-Instrument](todo-kustomize/overlays/auto-instrument.yaml)

- Annotate with *instrumentation.opentelemetry.io/inject-java=true*
- Add following environemnt variables

| Environment Variable        | Value                                                              | Description                               |
|-----------------------------|--------------------------------------------------------------------|-------------------------------------------|
| OTEL_EXPORTER_OTLP_ENDPOINT | http://otel-collector-headless:4318                                | OTEL Service and port                     |
| OTEL_TRACES_SAMPLER_ARG     | drop=/;drop=/q/health/live;drop=/q/health/ready;fallback=always_on | Config trace sampling to skip health chek |

- Another way to config this is patch deployment and set environment variable with following command

```bash
oc patch deployment/todo \
-p '{"spec":{"template":{"metadata":{"annotations":{"instrumentation.opentelemetry.io/inject-java":"true"}}}}}' \
-n $PROJECT
oc set env deploy todo \
OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector-headless:4318 \
-n $PROJECT
 oc set env deploy todo OTEL_TRACES_SAMPLER_ARG="drop=/;drop=/q/health/live;drop=/q/health/ready;fallback=always_on" \
 -n $PROJECT
```
<!-- oc set env deploy todo quarkus.otel.exporter.otlp.endpoint- \
-n $PROJECT -->
- Check todo's pod
  
  Init Container

  ![](images/todo-init-container.png)

  Todo pod log

  ```log
  INFO exec -a "java" java -Dquarkus.http.host=0.0.0.0 -Djava.util.logging.manager=org.jboss.logmanager.LogManager -cp "." -jar /deployments/quarkus-run.jar
  INFO running in /deployments
  Picked up JAVA_TOOL_OPTIONS: -javaagent:/otel-auto-instrumentation-java/javaagent.jar
  OpenJDK 64-Bit Server VM warning: Sharing is only supported for boot loader classes because bootstrap classpath has been appended
  [otel.javaagent 2025-05-04 13:27:02:012 +0000] [main] INFO io.opentelemetry.javaagent.tooling.VersionLogger - opentelemetry-javaagent - version: 1.33.6
  ```
- Test todo app again and verify that traces still created even app container image does not contains openTelemetry library.
- Specified TraceQL *{rootServiceName="todo" && span.db.statement!="unknown"}*

![](images/trace-ui-with-traceql.png)

### RESTful App
#### Node.js
- Deploy Node.js app

```bash
oc create -f config/frontend.yaml -n $PROJECT
```

Output

```bash
deployment.apps/frontend created
service/frontend created
route.route.openshift.io/frontend created
```

- Annotate deployment for auto-instrumentation

```bash
oc patch deployment/frontend \
    -p '{"spec":{"template":{"metadata":{"annotations":{"instrumentation.opentelemetry.io/inject-nodejs":"true"}}}}}' \
    -n $PROJECT
```

Output

```bash
deployment.apps/frontend patched
```
- Verify that auto-instrumentation is working with init-container

```bash
oc get po $(oc get po -l app=frontend -o custom-columns='Name:.metadata.name' -n $PROJECT --no-headers) -n $PROJECT -o jsonpath='{.status.initContainerStatuses}'|jq
```

Output

```json
[
  {
    "containerID": "cri-o://8461a346ece60ba52018f6395b1133298c26d532a0d411a30e5d147bee089fc0",
    "image": "ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-nodejs:0.53.0",
    "imageID": "ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-nodejs@sha256:70ba757df71d0596aaccac91f439e8be7f81136b868205e79178e8fd3c36a763",
    "lastState": {},
    "name": "opentelemetry-auto-instrumentation-nodejs",
    "ready": true,
    "restartCount": 0,
    "started": false,
    "state": {
      "terminated": {
        "containerID": "cri-o://8461a346ece60ba52018f6395b1133298c26d532a0d411a30e5d147bee089fc0",
        "exitCode": 0,
        "finishedAt": "2025-05-05T07:22:25Z",
        "reason": "Completed",
        "startedAt": "2025-05-05T07:22:23Z"
      }
    },
    "volumeMounts": [
      {
        "mountPath": "/otel-auto-instrumentation-nodejs",
        "name": "opentelemetry-auto-instrumentation-nodejs"
      },
      {
        "mountPath": "/var/run/secrets/kubernetes.io/serviceaccount",
        "name": "kube-api-access-6zqld",
        "readOnly": true,
        "recursiveReadOnly": "Disabled"
      }
    ]
  }
]
```
- Set environment variables

```bash
oc set env deploy frontend OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector-headless:4318 -n $PROJECT
oc set env deploy frontend OTEL_SERVICE_NAME=frontend -n $PROJECT
oc set env deploy frontend OTEL_PROPAGATORS=tracecontext,b3 -n $PROJECT
```
#### Python
- Deploy Python app

```bash
oc create -f config/simple-rest-python.yaml -n $PROJECT
```

Output

```bash
deployment.apps/simple-rest-python created
service/simple-rest-python created
```

- Annotate deployment for auto-instrumentation

```bash
oc patch deployment/simple-rest-python \
    -p '{"spec":{"template":{"metadata":{"annotations":{"instrumentation.opentelemetry.io/inject-python":"true"}}}}}' \
    -n $PROJECT
```

Output

```bash
deployment.apps/simple-rest-python patched
```
- Verify that auto-instrumentation is working with init-container

```bash
oc get po $(oc get po -l app=simple-rest-python -o custom-columns='Name:.metadata.name' -n $PROJECT --no-headers) -n $PROJECT -o jsonpath='{.status.initContainerStatuses}'|jq
```

Output

```json
[
  {
    "containerID": "cri-o://1f6ee4ae0581c7ffd2ab428c039414533d07dbc9666a471b495d45e19e5c3c03",
    "image": "ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-python:0.54b1",
    "imageID": "ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-python@sha256:3b0c54aefaf735835e23a6ec8b81f34d4357e7444d3a0e78cd6acfa1fc3485fc",
    "lastState": {},
    "name": "opentelemetry-auto-instrumentation-python",
    "ready": true,
    "restartCount": 0,
    "started": false,
    "state": {
      "terminated": {
        "containerID": "cri-o://1f6ee4ae0581c7ffd2ab428c039414533d07dbc9666a471b495d45e19e5c3c03",
        "exitCode": 0,
        "finishedAt": "2025-07-10T13:22:31Z",
        "reason": "Completed",
        "startedAt": "2025-07-10T13:22:31Z"
      }
    },
    "volumeMounts": [
      {
        "mountPath": "/otel-auto-instrumentation-python",
        "name": "opentelemetry-auto-instrumentation-python"
      },
      {
        "mountPath": "/var/run/secrets/kubernetes.io/serviceaccount",
        "name": "kube-api-access-hdsj2",
        "readOnly": true,
        "recursiveReadOnly": "Disabled"
      }
    ]
  }
]
```
- Set environment variables

```bash
oc set env deploy simple-rest-python OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector-headless:4318 -n $PROJECT
oc set env deploy simple-rest-python OTEL_SERVICE_NAME=simple-rest-python -n $PROJECT
```
#### Go-lang

*Remark: With opentelemetry-operator.v0.119.0-2 and go autoinstrumentation-go:v0.20.0 only work with golang 1.23*

- Create [SCC](config/otel-go-instrument-scc.yaml) for for go-lang instrumentation 

```bash
 oc create -f config/otel-go-instrument-scc.yaml -n $PROJECT
```

- Create Service Account for go-lang pod and add SCC to this service account

```bash
oc create sa go-lang-runner
oc adm policy add-scc-to-user otel-go-instrumentation-scc -z go-lang-runner
```

- Deploy [simple-go app](config/simple-go.yaml)

```bash
oc create -f config/simple-go.yaml -n $PROJECT
```

Output

```bash
deployment.apps/simple-go created
service/simple-go created
```

- Check [simple-go deployment](config/simple-go.yaml)
  - Annotations
    
    ```yaml
      template:
        metadata:
          annotations:
            instrumentation.opentelemetry.io/inject-go: "true"
            instrumentation.opentelemetry.io/otel-go-auto-target-exe: /app/api
            openshift.io/required-scc: otel-go-instrumentation-scc
    ```
  
  - Enviornment variables
    
    ```yaml
            - name: OTEL_EXPORTER_OTLP_ENDPOINT
              value: http://otel-collector-headless:4318
            - name: OTEL_SERVICE_NAME
              value: simple-go
            - name: OTEL_GO_AUTO_TARGET_EXE
              value: /app/api
            - name: OTEL_PROPAGATORS
              value: tracecontext,b3
    ```

- Verify that auto-instrumentation is working with container sidecar

```bash
oc get po -l app=simple-go -n $PROJECT
oc get po $(oc get po -l app=simple-go -o custom-columns='Name:.metadata.name' -n $PROJECT --no-headers) -n $PROJECT -o jsonpath='{.spec.containers[1].name}'
```

Output

```bash
NAME                        READY   STATUS    RESTARTS   AGE
simple-go-56f8c644b-w4sxw   2/2     Running   0          7m42s
opentelemetry-auto-instrumentation
```

#### .NET Core
- Deploy .NET Core app

```bash
oc create -f config/simple-rest-dotnet.yaml -n $PROJECT
```

Output

```bash
deployment.apps/simple-rest-dotnet created
service/simple-rest-dotnet created
```

- Annotate deployment for auto-instrumentation

```bash
oc patch deployment/simple-rest-dotnet \
    -p '{"spec":{"template":{"metadata":{"annotations":{"instrumentation.opentelemetry.io/inject-dotnet":"true"}}}}}' \
    -n $PROJECT
```

Output

```bash
deployment.apps/simple-rest-dotnet patched
```
- Verify that auto-instrumentation is working with init-container

```bash
oc get po $(oc get po -l app=simple-rest-dotnet -o custom-columns='Name:.metadata.name' -n $PROJECT --no-headers) -n $PROJECT -o jsonpath='{.status.initContainerStatuses}'|jq
```

Output

```json
[
  {
    "containerID": "cri-o://3c5a2875af666df5ab116df7e917261e4dce5606f523910538cceacffa051d06",
    "image": "ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-dotnet:1.2.0",
    "imageID": "ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-dotnet@sha256:093f0057f30022d0d4f4fbdbd3104c48879c8424d7acec0b46e9cb86a3d95e10",
    "lastState": {},
    "name": "opentelemetry-auto-instrumentation-dotnet",
    "ready": true,
    "restartCount": 1,
    "started": false,
  ...
```
- Set environment variables

```bash
oc set env deploy simple-rest-python OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector-headless:4318 -n $PROJECT
oc set env deploy simple-rest-python OTEL_SERVICE_NAME=simple-rest-python -n $PROJECT
```

#### Java App
- Deploy [Java RESTful App](config/backend.yaml)

```bash
oc create -f config/backend.yaml -n $PROJECT
```

- Check [backend deployment](config/backend.yaml)
  - Annotations
    
    ```yaml
      template:
        metadata:
          annotations:
            instrumentation.opentelemetry.io/inject-java: "true"
    ```
  
  - Enviornment variables
    
    ```yaml
            - name: OTEL_EXPORTER_OTLP_ENDPOINT
              value: http://otel-collector-headless:4318
            - name: OTEL_SERVICE_NAME
              value: backend
            - name: OTEL_PROPAGATORS
              value: tracecontext,b3
    ```

- Verify that auto-instrumentation is working with init-container

```bash
oc get po $(oc get po -l app=backend -o custom-columns='Name:.metadata.name' -n $PROJECT --no-headers) -n $PROJECT -o jsonpath='{.status.initContainerStatuses}'|jq|head -n 8
```

Output

```json
[
  {
    "containerID": "cri-o://f88eea516f6b51b9bf772b17f88f73ccd920728a8ff4237a855d89a08d2499a9",
    "image": "ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-java:1.33.6",
    "imageID": "ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-java@sha256:502d3170177a0676db8b806eba047a520af9bb83400e734fc64f24a593b2ca64",
    "lastState": {},
    "name": "opentelemetry-auto-instrumentation-java",
    "ready": true,
```

- Check container log

```bash
oc logs $(oc get po -l app=backend -o custom-columns='Name:.metadata.name' -n $PROJECT --no-headers) -n $PROJECT | head -n 4
```

Output

```bash
Defaulted container "backend" out of: backend, opentelemetry-auto-instrumentation-java (init)
INFO exec -a "java" java -Dquarkus.http.host=0.0.0.0 -Djava.util.logging.manager=org.jboss.logmanager.LogManager -cp "." -jar /deployments/quarkus-run.jar
INFO running in /deployments
Picked up JAVA_TOOL_OPTIONS:  -javaagent:/otel-auto-instrumentation-java/javaagent.jar
OpenJDK 64-Bit Server VM warning: Sharing is only supported for boot loader classes because bootstrap classpath has been appended
```
- Verify applications in Dev Console

![](images/app-x.png)


#### Test RESTful App
- Test app

```bash
curl -v https://$(oc get route frontend -n $PROJECT -o jsonpath='{.spec.host}') 
```

Output

```bash
* Connection #0 to host frontend-demo.apps.cluster-4thxh.4thxh.sandbox2298.opentlc.com left intact
Frontend version: v1 => [Backend: http://simple-rest-python:5000/api, Response: 200, Body: Backend version:v1, Response:200, Host:backend-855ddff6c5-rlhgd, Status:200, Message: Hello, World]
```

- Check trace in console with Query  *{rootServiceName="frontend"}*
  
  Select service

  ![](images/trace-ui-with-root-frontend.png)

  Traces

  ![](images/trace-ui-with-root-frontend-2.png)

  - Overall Trace
  
  ![](images/trace-frontend-all.png)

  - Client information
  
  ![](images/frontend-trace-client-info.png)

## Grafana
- Create prject and install Grafana Operator

```bash
oc new-project grafana
oc create -f config/grafana-sub.yaml
```

- Create Grafana Dashboard

```bash
oc create -f config/grafana.yaml -n grafana
```

- Get user and password

```bash
USER=$(oc get secret grafana-tempo-admin-credentials -o jsonpath='{.data.GF_SECURITY_ADMIN_USER}' | base64 -d)
PASSWORD=$(oc get secret grafana-tempo-admin-credentials -o jsonpath='{.data.GF_SECURITY_ADMIN_PASSWORD}' | base64 -d)
```

- Login to Grafana Dashboard 

  Grafana URL

  ```bash
  echo "https://$(oc get route grafana-tempo-route -n grafana -o jsonpath='{.spec.host}')"
  ```

- Navigate to Connection then add Tempo Datasource
  
  ![](images/grafana-datasource.png)

- Config Tempo Datasource

    | Parameter | Value |  
    |-----------|-------|
    |URL | https://tempo-{name}-query-frontend.{namespace}.svc.cluster.local:3200 |
    |TLS Client Auth | true | 
    |Skip Verify TLS | true | 

   
    TLS Configuration

    In this demo name is *simple* and namespace is *demo*

    | Parameter | Value |  
    |-----------|-------|
    |ServerName | tempo-{name}-query-frontend.<namespace>.svc.cluster.local |  
    |Client Cert| oc get secret tempo-{name}-query-frontend-mtls -n {namespace} -o jsonpath='{.data.tls\\.crt}'\|base64 -d |  
    |Client Key | oc get secret tempo-{name}-query-frontend-mtls -n {namespace} -o jsonpath='{.data.tls\\.key}'\|base64 -d |  
    
    Custom HTTP Header

    | Parameter | Value |  
    |-----------|-------|
    |X-Scope-OrgID | Tenant ID specified in tempo configuration |
    
    Dev tenant ID is *1610b0c3-c509-4592-a256-a1871353dbfa*

- Navigate to Explore and select service frontend

  ![](images/grafana-tempo-explore-view.png)

-
  

<!-- - Create Dashboard -> Add Visualization -> Select Tempo -->
<!-- - Install [Grafana Operator](https://grafana.github.io/grafana-operator/docs/installation/kustomize/)

```bash
oc create -f https://github.com/grafana/grafana-operator/releases/latest/download/kustomize-cluster_scoped.yaml
``` -->






  







  
<!-- - Annotate deployment for auto-instrumentation

```bash
oc patch deployment/simple-go \
    -p '{"spec":{"template":{"metadata":{"annotations":{"otel-go-auto-target-exe":"/app/api"}}}}}' \
    -n $PROJECT
oc patch deployment/simple-go \
    -p '{"spec":{"template":{"metadata":{"annotations":{"instrumentation.opentelemetry.io/inject-go":"true"}}}}}' \
    -n $PROJECT
oc patch deployment/simple-go \
    -p '{"spec":{"template":{"metadata":{"annotations":{"openshift.io/required-scc":"otel-go-instrumentation-scc"}}}}}' \
    -n $PROJECT
```
- Set environment variables
```bash
oc set env deploy simple-go OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector-headless:4318 -n $PROJECT
oc set env deploy simple-go OTEL_SERVICE_NAME=simple-go -n $PROJECT
oc set env deploy simple-go OTEL_PROPAGATORS=tracecontext,b3 -n $PROJECT
oc set env deploy simple-go OTEL_GO_AUTO_TARGET_EXE=/app/api -n $PROJECT
oc scale deploy simple-go --replicas=0 -n $PROJECT;oc scale deploy simple-go --replicas=1 -n $PROJECT
``` -->


<!-- # Warning: 'bases' is deprecated. Please use 'resources' instead. Run 'kustomize edit fix' to update your Kustomization automatically.
# Warning: 'patchesStrategicMerge' is deprecated. Please use 'patches' instead. Run 'kustomize edit fix' to update your Kustomization automatically. -->

<!--
ghcr.io/open-telemetry/opentelemetry-go-instrumentation/autoinstrumentation-go:v0.20.0
>

registry.redhat.io/ubi8/nodejs-20:9.6-1745586361
grype reistry.redhat.io/ubi8/nodejs-20:latest --only-fixed