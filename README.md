# OpenShift - OpenTelemetry with Tempo
![](images/OpenTelemetry.png | width=100)

- [OpenShift - OpenTelemetry with Tempo](#openshift---opentelemetry-with-tempo)
  - [Operators](#operators)
    - [Tempo Operator](#tempo-operator)
      - [Tempo Monolithic](#tempo-monolithic)
    - [Distributed Tracing Data Collection Operator](#distributed-tracing-data-collection-operator)
      - [Config OTEL Collector](#config-otel-collector)
    - [Cluster Observability Operator](#cluster-observability-operator)
      - [Tracing UI](#tracing-ui)
  - [Todo Application (with OpenTelemetry library)](#todo-application-with-opentelemetry-library)
  - [OTEL Auto-Instrumentation](#otel-auto-instrumentation)
    - [Todo App (without OpenTelemetry library)](#todo-app-without-opentelemetry-library)
    - [Node.js and Go-lang App](#nodejs-and-go-lang-app)


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
```

Output

```bash
namespace/openshift-tempo-operator created
operatorgroup.operators.coreos.com/openshift-tempo-operator-svgqj created
subscription.operators.coreos.com/tempo-product created
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

- Create Tempo Monolithic instance in project demo

```bash
cat config/tempo-monolithic.yaml | sed 's/PROJECT/'$PROJECT'/g' | oc create -f -

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

### Distributed Tracing Data Collection Operator
- Install [Distributed Tracing Data Collection Operator](config/otel-sub.yaml)

```bash
oc create -f config/otel-sub.yaml
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

- Create OTEL collector

```bash
cat config/otel-collector-multi-tenant.yaml | sed 's/PROJECT/'$PROJECT'/' | oc apply -n $PROJECT -f -
oc wait --for condition=ready --timeout=180s pod -l app.kubernetes.io/managed-by=tempo-operator  -n $PROJECT 
oc get po -l  app.kubernetes.io/managed-by=opentelemetry-operator -n $PROJECT
```

Output

```bash
opentelemetrycollector.opentelemetry.io/otel created
pod/tempo-sample-0 condition met
NAME                              READY   STATUS    RESTARTS   AGE
otel-collector-8455b85888-n9srp   1/1     Running   0          50s
```

### Cluster Observability Operator
- Install [Cluster Observability Operator](config/cluster-observability-sub.yaml)

```bash
oc create -f config/observability-sub.yaml
```

Output

```bash
catalogsource.operators.coreos.com/observability-operator created
subscription.operators.coreos.com/observability-operator created
```

#### Tracing UI
- Create [Tracing UI Plugin](config/ui-pluging.yaml)

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
oc apply -k todo-kustomize/base -n $PROJECT
```
- Patch deployment to annotate with *instrumentation.opentelemetry.io/inject-java=true* and set environment variable

```bash
oc patch deployment/todo \
-p '{"spec":{"template":{"metadata":{"annotations":{"instrumentation.opentelemetry.io/inject-java":"true"}}}}}' \
-n $PROJECT
oc set env deploy todo \
OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector-headless:4318 \
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
- Test todo app again and verify that traces still created

### Node.js and Go-lang App
- Deploy Node.js, Go-lang and Java Apps
```bash
oc create -f config/frontend-go-backend.yaml -n $PROJECT
```
![](images/frontend-go-backend.png)

- Annotate each deployment for auto-instrumentation
- Backend (Java)
```bash
oc patch deployment/backend \
-p '{"spec":{"template":{"metadata":{"annotations":{"instrumentation.opentelemetry.io/inject-java":"true"}}}}}' \
-n $PROJECT
oc set env deploy backend \
OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector-headless:4318 -n $PROJECT
```
- Simple-go (Go-lang)
  - Create [SCC](config/otel-go-instrument-scc.yaml) for go-lang instrumentation and add scc to service account default
    ```bash
    oc create -f config/otel-go-instrument-scc.yaml -n $PROJECT
    oc adm policy add-scc-to-user otel-go-instrumentation-scc -z default
    ```
  - Annotate deployment
    ```bash
    oc patch deployment/simple-go \
    -p '{"spec":{"template":{"metadata":{"annotations":{"instrumentation.opentelemetry.io/inject-go":"true"}}}}}' \
    -n $PROJECT

    oc patch deployment/simple-go \
    -p '{"spec":{"template":{"metadata":{"annotations":{"openshift.io/scc":"otel-go-instrumentation-scc"}}}}}' \
    -n $PROJECT

    oc patch deployment/simple-go \
    -p '{"spec":{"template":{"metadata":{"annotations":{"instrumentation.opentelemetry.io/otel-go-auto-target-exe":"/app/api"}}}}}' \
    -n $PROJECT 
    ```
- Frontend (Node.js)
```bash
oc patch deployment/frontend \
-p '{"spec":{"template":{"metadata":{"annotations":{"instrumentation.opentelemetry.io/inject-nodejs":"true"}}}}}' \
-n $PROJECT
oc set env deploy frontend OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector-headless:4318
```
<!-- # Warning: 'bases' is deprecated. Please use 'resources' instead. Run 'kustomize edit fix' to update your Kustomization automatically.
# Warning: 'patchesStrategicMerge' is deprecated. Please use 'patches' instead. Run 'kustomize edit fix' to update your Kustomization automatically. -->

<!--
ghcr.io/open-telemetry/opentelemetry-go-instrumentation/autoinstrumentation-go:v0.20.0
>