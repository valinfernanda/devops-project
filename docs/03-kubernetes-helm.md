# Phase 3: Kubernetes + Helm

> 🎯 **Phase objective:** run the Task API on a real, multi-node **Kubernetes** cluster on your laptop, the
> way it runs in production: several copies, health probes, a database with its own disk, zero-downtime
> updates, autoscaling, and an HTTP front door. First **by hand** (plain YAML, so you see every piece),
> then packaged as a **Helm chart** with separate dev and prod settings.

**Status:** ✅ done (24 Nov 2026)

**Legend:** ✅ done · ⚠️ problem found · 👤 you must do this · 🧪 experiment

> New words (Pod, Deployment, Service, PVC, HPA, Gateway…) are all in the [glossary](glossary.md).
> Owner of this phase: **🛠️ DevOps**. Programmers deliver the image and the `/health` + `/ready` endpoints;
> everything here is how the platform runs them.

---

## Where are we now?

```mermaid
flowchart TD
    P2(["Phase 2: CI → image in GHCR ✅"]) --> A
    A["3.1 Kubernetes in plain words ✅"] --> B["3.2 3-node cluster with kind ✅"]
    B --> C["3.3 Namespace + ConfigMap + Secret ✅"]
    C --> D["3.4 PostgreSQL: StatefulSet + disk ✅"]
    D --> E["3.5 Migrations as a Job ✅"]
    E --> F["3.6 API: Deployment + Service + probes ✅"]
    F --> G["3.7 Front door: Gateway API (Envoy) ✅"]
    G --> H["3.8 🧪 7 experiments ✅"]
    H --> I["3.9 Helm chart: dev + prod ✅"]
    I --> P4(["Phase 4: Terraform"])

    classDef done fill:#2e7d32,color:#fff
    class A,B,C,D,E,F,G,H,I,P2 done
```

### What we end up with

```mermaid
flowchart LR
    laptop["Your laptop<br/>http://taskapi.localhost:8090"] -->|"kind port mapping<br/>127.0.0.1:8090 → node:30080"| np
    subgraph cluster["kind cluster 'devops-lab' (3 Docker containers = 3 nodes)"]
        subgraph egs["namespace envoy-gateway-system (PLATFORM)"]
            np["Service NodePort 30080"] --> envoy["Envoy proxy pod"]
        end
        subgraph ns["namespace taskapi (APP)"]
            route["HTTPRoute<br/>host taskapi.localhost"]
            svc["Service taskapi :80"]
            api1["Pod taskapi #1<br/>(worker)"]
            api2["Pod taskapi #2<br/>(worker2)"]
            job["Job taskapi-migrate<br/>(alembic upgrade head)"]
            pgsvc["Service postgres<br/>(headless)"]
            pg["Pod postgres-0<br/>StatefulSet"]
            pvc[("PVC data-postgres-0<br/>1Gi")]
            cm["ConfigMap"]
            sec["Secret (password)"]
        end
        envoy -.reads.-> route
        envoy --> svc --> api1 & api2
        api1 & api2 --> pgsvc --> pg --> pvc
        job --> pgsvc
        cm -.env.-> api1 & api2 & job
        sec -.env.-> api1 & api2 & job & pg
    end
    ghcr["GHCR<br/>ghcr.io/valinfernanda/taskapi:sha-…"] -.image pull.-> api1 & api2 & job
```

### New files in this phase

```
k8s/
├── kind-cluster.yaml            ← the cluster: 1 control-plane + 2 workers, port 8090 → 30080
├── platform/                    ← PLATFORM layer (DevOps): shared by every app
│   ├── gateway.yaml             ← EnvoyProxy + GatewayClass + Gateway (the front door)
│   └── namespaces.yaml          ← namespaces for the Helm releases (dev, prod)
└── manifests/                   ← APP layer, by hand (Steps 3.3–3.8), applied in file-name order
    ├── 00-namespace.yaml
    ├── 10-configmap.yaml
    ├── 20-postgres.yaml         ← Service + StatefulSet (+ disk)
    ├── 30-migrate-job.yaml
    ├── 40-api.yaml              ← Deployment + Service
    ├── 50-httproute.yaml        ← HTTPRoute + BackendTrafficPolicy
    └── 60-hpa.yaml              ← autoscaler
helm/taskapi/                    ← the same app as a Helm chart (Step 3.9)
```

Every YAML file is commented line by line: **read the files alongside this guide**.

---

## Step 3.1: Kubernetes in plain words ✅

### 🎯 Objective
Know what Kubernetes does and the 10 objects we'll use, before typing any command.

### ❓ Why Kubernetes, if Docker Compose already runs our app?
Compose runs containers on **one** machine and does what you tell it, once. Kubernetes runs containers on
**many** machines and keeps doing it forever:

| Need | Docker Compose | Kubernetes |
|---|---|---|
| Run on several machines | ❌ one host | ✅ a cluster of nodes |
| A container crashes | `restart:` on the same host | ✅ replaced, on any healthy node |
| A whole machine dies | ❌ app is down | ✅ pods rescheduled to other nodes |
| New version | stop → start (downtime) | ✅ rolling update, zero downtime |
| More traffic | ❌ manual | ✅ autoscaling (HPA) |
| Traffic only to healthy copies | ❌ | ✅ readiness probes |

### 📚 Concept: desired state + controllers (the one idea behind everything)
You never tell Kubernetes "start a container". You **declare the desired state** in YAML
("I want 2 copies of image X, with 128 Mi RAM each") and `kubectl apply` it. Then **controllers**
(programs in the control plane) loop forever: *compare desired vs actual → fix the difference*.
A pod dies? actual (1) ≠ desired (2) → a new pod is created. That's **self-healing** (Experiment A).

```mermaid
flowchart LR
    you["You: kubectl apply -f x.yaml"] -->|desired state| api["API server<br/>(stores it in etcd)"]
    api --> ctrl["Controllers<br/>loop: desired vs actual"]
    ctrl -->|create/delete pods| sched["Scheduler<br/>picks a node"]
    sched --> kubelet["kubelet on the node<br/>starts containers"]
    kubelet -->|reports actual state| api
```

### The objects we use, in one table

| Object | One-line meaning | Compose equivalent | Step |
|---|---|---|---|
| **Namespace** | A folder for objects | the project name | 3.3 |
| **ConfigMap** | Non-secret settings → env vars | `environment:` | 3.3 |
| **Secret** | Sensitive settings (password) | `.env` | 3.3 |
| **Pod** | 1+ containers that run together (smallest unit) | a container | 3.4+ |
| **StatefulSet** | Pods with stable names + own disk (databases) | `db:` service + volume | 3.4 |
| **PersistentVolumeClaim** | "I need 1 Gi of disk" | named volume `db-data` | 3.4 |
| **Job** | Run a pod until it succeeds once | `migrate:` with `restart: "no"` | 3.5 |
| **Deployment** | Keep N identical pods running, roll out new versions | `api:` service | 3.6 |
| **Service** | Stable name/IP in front of pods, load-balancing | the service name `db` | 3.6 |
| **HTTPRoute** (Gateway API) | Route outside HTTP traffic to a Service | `ports: 8000:8000` | 3.7 |
| **HorizontalPodAutoscaler** | Change the number of pods with the load | — | 3.8 G |

### Pod statuses you'll see (and what they mean)

| Status | Meaning | Usual cause |
|---|---|---|
| `Pending` | Not started yet | No node has enough CPU/RAM, or waiting for a disk |
| `ContainerCreating` | Pulling the image / mounting volumes | First start is slow (image download) |
| `Running` + `0/1` READY | Process runs, but readiness fails | Dependency (DB) down, app still starting |
| `Running` + `1/1` | ✅ healthy and receiving traffic | |
| `Completed` | Finished successfully (Jobs) | |
| `ImagePullBackOff` / `ErrImagePull` | Can't download the image | Typo in the tag, private registry (Experiment D) |
| `CrashLoopBackOff` | Container keeps crashing | App error at startup: check `kubectl logs --previous` |
| `OOMKilled` | Used more memory than its limit | Limit too low, or a memory leak |

---

## Step 3.2: A 3-node cluster with kind ✅

### 🎯 Objective
Create a Kubernetes cluster with **1 control-plane node + 2 worker nodes**, reachable from the laptop on port 8090.

### ❓ Why 3 nodes and not 1?
With one node you can't see the things that make Kubernetes worth it: pods spread over nodes, a pod moving
to another node, "what if a node dies". kind makes extra nodes cheap (each node is just a Docker container).

### 🛠️ Tool
**kind** v0.33.0 (installed in Phase 0). Node image `kindest/node:v1.37.0`, **pinned by digest** in the config,
the same practice as our Dockerfile base image.

### The config: [`k8s/kind-cluster.yaml`](../k8s/kind-cluster.yaml)
Key part, the "door" from the laptop into the cluster:

```yaml
extraPortMappings:
  - containerPort: 30080        # port on the control-plane node (a NodePort, Step 3.7)
    hostPort: 8090              # port on your laptop
    listenAddress: "127.0.0.1"  # only from this laptop, not from your Wi-Fi network
```

### ⌨️ Commands (inside Ubuntu, in the project folder)

```bash
docker compose stop                                  # free RAM; Phase 1 stack not needed now (data kept)
kind create cluster --config k8s/kind-cluster.yaml   # ~45 s
kubectl get nodes -o wide
kubectl get pods -A                                  # -A = all namespaces
```

### 📤 Output

```
Creating cluster "devops-lab" ...
 ✓ Ensuring node image (kindest/node:v1.37.0) 🖼️
 ✓ Preparing nodes 📦 📦 📦
 ✓ Writing configuration 📜
 ✓ Starting control-plane 🕹️
 ✓ Installing CNI 🔌
 ✓ Installing StorageClass 💾
 ✓ Joining worker nodes 🚜
Set kubectl context to "kind-devops-lab"
real    0m44.673s

NAME                       STATUS   ROLES           AGE   VERSION   INTERNAL-IP   OS-IMAGE                       CONTAINER-RUNTIME
devops-lab-control-plane   Ready    control-plane   34s   v1.37.0   172.18.0.4    Debian GNU/Linux 13 (trixie)   containerd://2.3.4
devops-lab-worker          Ready    <none>          18s   v1.37.0   172.18.0.2    Debian GNU/Linux 13 (trixie)   containerd://2.3.4
devops-lab-worker2         Ready    <none>          17s   v1.37.0   172.18.0.3    Debian GNU/Linux 13 (trixie)   containerd://2.3.4
```

> Right after creation the nodes showed `NotReady` for a few seconds: that's normal, the network plugin
> (CNI) was still starting. `kubectl wait --for=condition=Ready node --all --timeout=120s` waits for it.

**What kind installed for us** (`kubectl get pods -A`), the parts of the "brain" from Step 3.1:

| Pod (namespace `kube-system`) | Role |
|---|---|
| `kube-apiserver-…` | The API every `kubectl` command talks to |
| `etcd-…` | The database where the desired state is stored |
| `kube-scheduler-…` | Picks a node for each new pod |
| `kube-controller-manager-…` | The controllers (Deployment, Job, StatefulSet…) |
| `coredns-…` (×2) | Cluster DNS: `postgres` → the database pod's IP |
| `kindnet-…` (one per node) | The CNI: gives every pod an IP, connects nodes |
| `kube-proxy-…` (one per node) | Makes Service IPs work (load-balancing rules) |
| `local-path-provisioner` (ns `local-path-storage`) | Creates disks for PVCs (StorageClass `standard`) |

### 🧯 Real error we hit: port 8080 already taken

The first try used `hostPort: 8080`:

```
ERROR: failed to create cluster: ... docker: Error response from daemon: ports are not available:
exposing port TCP 127.0.0.1:8080 -> 127.0.0.1:0: listen tcp4 127.0.0.1:8080: bind:
An attempt was made to access a socket in a way forbidden by its access permissions.
```

kind cleaned up after itself (`Deleted nodes: [...]`). How we found the cause (PowerShell):

```powershell
netsh int ipv4 show excludedportrange protocol=tcp     # ports Windows/Hyper-V reserves → 8080 NOT in the list
Get-NetTCPConnection -LocalPort 8080 -State Listen     # who listens on 8080?
#   LocalAddress LocalPort OwningProcess
#   ::                8080          7392
Get-Process -Id 7392                                    # → "java": another program on this laptop
```

**Fix:** don't kill someone else's program; pick a free port (`8090`) and re-run `kind create cluster`.
Two typical causes of this error on Windows: **another program** uses the port (our case), or the port is in a
**Hyper-V reserved range** (the `netsh` list). Same diagnosis either way.

---

## Step 3.3: Namespace + ConfigMap + Secret ✅

### 🎯 Objective
Create the app's own namespace with strict security, its settings (ConfigMap) and its password (Secret).

### Files
- [`00-namespace.yaml`](../k8s/manifests/00-namespace.yaml): namespace `taskapi` with the labels
  `pod-security.kubernetes.io/enforce: restricted` (Pod Security Admission) and `gateway-access: "true"` (Step 3.7).
- [`10-configmap.yaml`](../k8s/manifests/10-configmap.yaml): `APP_LOG_LEVEL`, `POSTGRES_DB`, `POSTGRES_USER`,
  `DB_HOST`, `DB_PORT`.

### 📚 Concept: "restricted" Pod Security
With this label, the API server **refuses** any pod in the namespace that could run as root, keeps Linux
capabilities, allows privilege escalation, or has no seccomp profile. It forces every manifest we write to be
secure; you'll see these lines in every pod: `runAsNonRoot: true`, `allowPrivilegeEscalation: false`,
`capabilities: drop: ["ALL"]`, `seccompProfile: RuntimeDefault`.

### 📚 Concept: why the Secret is NOT a file in Git
A Kubernetes Secret is only **base64-encoded**, not encrypted: anyone who can read the YAML can decode it.
So we create it **with a command**, with a random password that never appears on screen or in Git:

### ⌨️ Commands

```bash
kubectl apply -f k8s/manifests/00-namespace.yaml -f k8s/manifests/10-configmap.yaml
kubectl -n taskapi create secret generic taskapi-db --from-literal=password="$(openssl rand -hex 24)"
#  -n taskapi            → in namespace taskapi
#  generic               → a plain key/value Secret
#  --from-literal=k=v    → key "password", value = 48 random hex characters
#  $(openssl rand -hex 24) → the shell runs openssl first and pastes its output; you never see it
kubectl -n taskapi get configmap,secret
kubectl -n taskapi describe secret taskapi-db      # shows the SIZE of each value, never the value
```

### 📤 Output

```
namespace/taskapi created
configmap/taskapi-config created
secret/taskapi-db created

NAME                         DATA   AGE
configmap/kube-root-ca.crt   1      1s        ← added automatically to every namespace
configmap/taskapi-config     5      1s
NAME                TYPE     DATA   AGE
secret/taskapi-db   Opaque   1      1s

Data
====
password:  48 bytes
```

> 💡 Hex (0-9, a-f) on purpose: the password goes into a URL (`postgresql://user:PASSWORD@host/db`), and
> characters like `@`, `/` or `:` would break it.
> In real production the Secret comes from a vault (Azure Key Vault + External Secrets Operator, Phase 8).

---

## Step 3.4: PostgreSQL: StatefulSet + its own disk ✅

### 🎯 Objective
Run the database inside the cluster, with data on a persistent disk that survives pod restarts.

### File: [`20-postgres.yaml`](../k8s/manifests/20-postgres.yaml)
A **headless Service** (`clusterIP: None`) + a **StatefulSet** with `volumeClaimTemplates`.

### 📚 Concept: why StatefulSet, not Deployment?

| | Deployment | StatefulSet |
|---|---|---|
| Pod names | random (`taskapi-6c7f9cc974-68bz9`) | stable (`postgres-0`) |
| Disk | shared or none | **one PVC per pod**, re-attached to the same pod name |
| Start order | all at once | one by one, in order |
| Good for | stateless apps (our API) | databases, queues |

### 📚 Concept: how a pod gets a disk
`volumeClaimTemplates` → Kubernetes creates a **PVC** `data-postgres-0` ("I need 1 Gi") → the **StorageClass**
`standard` (kind's local-path provisioner) creates a folder on the node = a **PV** → the PVC is **Bound** to it →
mounted into the pod at `/var/lib/postgresql/data`.

### ⌨️ Commands

```bash
kubectl apply -f k8s/manifests/20-postgres.yaml
kubectl -n taskapi rollout status statefulset/postgres --timeout=180s   # wait until ready
kubectl -n taskapi get pods,pvc -o wide
kubectl get pv                                                          # PVs are cluster-wide (no -n)
```

### 📤 Output

```
service/postgres created
statefulset.apps/postgres created
Waiting for 1 pods to be ready...
partitioned roll out complete: 1 new pods have been updated...

NAME             READY   STATUS    RESTARTS   AGE   IP           NODE
pod/postgres-0   1/1     Running   0          50s   10.244.2.3   devops-lab-worker2

NAME                                    STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS
persistentvolumeclaim/data-postgres-0   Bound    pvc-bc6103ed-96e4-4d59-b671-f23a10dbcb5a   1Gi        RWO            standard

NAME                                       CAPACITY   RECLAIM POLICY   STATUS   CLAIM
pvc-bc6103ed-96e4-4d59-b671-f23a10dbcb5a   1Gi        Delete           Bound    taskapi/data-postgres-0
```

> ⚠️ `RECLAIM POLICY: Delete` = deleting the PVC deletes the data. Deleting the **pod** (or even the
> StatefulSet) does **not** delete the PVC: Experiment F proves the data survives.
> In production you'd use a managed database (Azure Database for PostgreSQL) or an operator (CloudNativePG)
> for backups, failover and upgrades. Running it ourselves here is for learning the building blocks.

---

## Step 3.5: Migrations as a Job ✅

### 🎯 Objective
Create the tables (`alembic upgrade head`) **once**, before the API serves traffic, the Kubernetes version of
compose's one-off `migrate` service.

### File: [`30-migrate-job.yaml`](../k8s/manifests/30-migrate-job.yaml)
- An **init container** `wait-for-db` (image `postgres:17-alpine`, only for its `pg_isready` tool) loops until
  the database accepts connections: the equivalent of compose's `depends_on: condition: service_healthy`.
- The main container uses **the same image as the API** with `command: ["alembic", "upgrade", "head"]`.
- `backoffLimit: 4` (retry 4 times), `activeDeadlineSeconds: 300` (give up after 5 min), `restartPolicy: Never`.

### 📚 Concept: building the database URL from pieces
The app wants one variable, `APP_DATABASE_URL`, but the password lives in a Secret and the rest in a ConfigMap.
Kubernetes can **combine** env vars defined earlier in the same container with `$(NAME)`:

```yaml
envFrom:
  - configMapRef: { name: taskapi-config }          # POSTGRES_USER, DB_HOST, DB_PORT, POSTGRES_DB
env:
  - name: DB_PASSWORD
    valueFrom: { secretKeyRef: { name: taskapi-db, key: password } }
  - name: APP_DATABASE_URL                           # must come AFTER the variables it uses
    value: "postgresql+psycopg://$(POSTGRES_USER):$(DB_PASSWORD)@$(DB_HOST):$(DB_PORT)/$(POSTGRES_DB)"
```

### ⌨️ Commands

```bash
kubectl apply -f k8s/manifests/30-migrate-job.yaml
kubectl -n taskapi wait --for=condition=complete job/taskapi-migrate --timeout=240s
kubectl -n taskapi get job,pods -l app.kubernetes.io/component=migrate   # -l = filter by label
kubectl -n taskapi logs job/taskapi-migrate -c wait-for-db               # -c = which container
# Proof that the tables exist: run psql INSIDE the database pod
kubectl -n taskapi exec postgres-0 -- sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "\dt" -c "select * from alembic_version"'
```

### 📤 Output

```
job.batch/taskapi-migrate created
job.batch/taskapi-migrate condition met

NAME                        STATUS     COMPLETIONS   DURATION   AGE
job.batch/taskapi-migrate   Complete   1/1           78s        78s      ← 78 s: mostly the first image download
NAME                        READY   STATUS      RESTARTS   AGE
pod/taskapi-migrate-r7dx7   0/1     Completed   0          78s

postgres:5432 - accepting connections                                     ← the init container's log

 Schema |      Name       | Type  |  Owner
--------+-----------------+-------+---------
 public | alembic_version | table | taskapi
 public | tasks           | table | taskapi
 version_num
-------------
 0001
```

> 💡 `kubectl logs job/taskapi-migrate -c migrate` printed **nothing**: not an error. Our `alembic.ini` has no
> logging section, so Alembic works silently. That's why we verify with `psql` instead.
> A Job can't be changed after creation; to run it again: `kubectl -n taskapi delete job taskapi-migrate`,
> then `apply` again. Helm automates this (Step 3.9, hooks).

---

## Step 3.6: The API: Deployment + Service + probes ✅

### 🎯 Objective
Run 2 copies of the API from the **image CI built** (`ghcr.io/valinfernanda/taskapi:sha-2273a31`), with health
probes, resource limits and strict security, behind a Service.

### File: [`40-api.yaml`](../k8s/manifests/40-api.yaml), the important choices

| Setting | Value | Why |
|---|---|---|
| `image` | `…:sha-2273a31` | **Immutable** tag = one exact commit on main. Never `:latest` or `:main` in a cluster: you couldn't tell what runs, or roll back |
| `replicas` | 2 | One copy can restart while the other serves |
| `strategy.rollingUpdate` | `maxSurge: 1`, `maxUnavailable: 0` | Updates add a new pod first, remove an old one only when the new is ready → zero downtime (Experiment C) |
| `startupProbe` | `/health`, up to 60 s | Slow boot doesn't count as "dead" |
| `livenessProbe` | `/health` | Stuck process → restart. **Never** checks the DB (Phase 1, Step 1.3) |
| `readinessProbe` | `/ready` | DB unreachable → no traffic, no restart (Experiment E) |
| `resources.requests` | 100m CPU, 128Mi | What the scheduler reserves on a node (100m = 0.1 CPU) |
| `resources.limits.memory` | 256Mi | Above this → `OOMKilled`. No CPU limit on purpose: CPU limits cause throttling; requests already guarantee a share |
| `securityContext` | non-root 10001, read-only root FS, drop ALL | The UID matches our Dockerfile's user |
| `topologySpreadConstraints` | spread by `kubernetes.io/hostname` | The 2 copies land on **different nodes** |

### ⌨️ Commands

```bash
kubectl apply -f k8s/manifests/40-api.yaml
kubectl -n taskapi rollout status deployment/taskapi --timeout=180s
kubectl -n taskapi get deploy,rs,pods,svc,endpointslices -o wide
kubectl -n taskapi logs deploy/taskapi --tail=5
```

### 📤 Output (shortened)

```
deployment.apps/taskapi created
service/taskapi created
Waiting for deployment "taskapi" rollout to finish: 0 of 2 updated replicas are available...
Waiting for deployment "taskapi" rollout to finish: 1 of 2 updated replicas are available...
deployment "taskapi" successfully rolled out

NAME                      READY   UP-TO-DATE   AVAILABLE   IMAGES
deployment.apps/taskapi   2/2     2            2           ghcr.io/valinfernanda/taskapi:sha-2273a31
NAME                                 DESIRED   CURRENT   READY
replicaset.apps/taskapi-6c7f9cc974   2         2         2          ← the Deployment created a ReplicaSet...
NAME                           READY   STATUS    IP           NODE
pod/taskapi-6c7f9cc974-68bz9   1/1     Running   10.244.1.3   devops-lab-worker     ← ...which created the pods,
pod/taskapi-6c7f9cc974-q5swt   1/1     Running   10.244.2.4   devops-lab-worker2    ← on DIFFERENT nodes ✅
NAME               TYPE        CLUSTER-IP      PORT(S)
service/postgres   ClusterIP   None            5432/TCP
service/taskapi    ClusterIP   10.96.140.230   80/TCP
NAME                                            PORTS   ENDPOINTS
endpointslice.discovery.k8s.io/taskapi-tklfs    8000    10.244.1.3,10.244.2.4   ← the Service's current pod list

INFO:     10.244.1.1:46630 - "GET /ready HTTP/1.1" 200 OK          ← the kubelet's probes, every 5 s
INFO:     10.244.1.1:59204 - "GET /health HTTP/1.1" 200 OK
```

The chain: **Deployment → ReplicaSet → Pods**, and **Service → EndpointSlice → Pod IPs** (only *ready* pods get traffic).

### ✅ Verify: talk to the API through a temporary tunnel

```bash
kubectl -n taskapi port-forward svc/taskapi 8001:80 &     # laptop:8001 → Service port 80 → pod:8000
curl -s localhost:8001/health
curl -s -X POST localhost:8001/tasks -H 'Content-Type: application/json' -d '{"title":"Learn Kubernetes"}'
curl -s localhost:8001/tasks
kill %1                                                    # stop the tunnel
```

```
{"status":"ok","version":"sha-2273a31"}
{"id":1,"title":"Learn Kubernetes","done":false,"created_at":"2026-11-24T12:55:33.182450Z"}
[{"id":1,"title":"Learn Kubernetes","done":false,"created_at":"2026-11-24T12:55:33.182450Z"}]
```

> `port-forward` is a **debugging** tool (one user, dies with the terminal). Real traffic goes through the
> Gateway, next step.

---

## Step 3.7: The front door: Gateway API with Envoy Gateway ✅

### 🎯 Objective
Make the API reachable at **http://taskapi.localhost:8090** from the laptop's browser, the way real clusters
receive outside traffic.

### ❓ Why not "Ingress + ingress-nginx" (what most tutorials show)?
The **ingress-nginx** controller, the most used one for years, was **retired in March 2026**: no more fixes,
not even security fixes. The Kubernetes project recommends the **Gateway API**, its successor
([Kubernetes blog](https://kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/)). We use **Envoy Gateway**
v1.10.0 as the implementation (others: NGINX Gateway Fabric, Istio, Cilium, Traefik, kgateway).
You'll still meet Ingress in older clusters: it's the same idea with fewer features.

### 📚 Concept: Gateway API splits the job by ROLE

| Object | Answers | Owned by | Our file |
|---|---|---|---|
| `GatewayClass` | Which software implements gateways? | Cluster admin | `k8s/platform/gateway.yaml` |
| `Gateway` | Which ports / which namespaces may attach? (the front door) | Platform / DevOps | `k8s/platform/gateway.yaml` |
| `HTTPRoute` | Host `taskapi.localhost`, path `/` → Service `taskapi` | App team | `k8s/manifests/50-httproute.yaml` |

With Ingress, one object mixed all of this, so app teams could break the shared door. Here the Gateway only
accepts routes from namespaces labelled `gateway-access: "true"` (`allowedRoutes.namespaces.from: Selector`).

### 📚 Concept: how a request gets from the browser to a pod

```mermaid
sequenceDiagram
    participant B as Browser / curl
    participant K as kind node container<br/>(control-plane)
    participant E as Envoy pod<br/>(envoy-gateway-system)
    participant S as Service taskapi
    participant P as API pod
    B->>K: GET http://taskapi.localhost:8090/tasks<br/>(*.localhost = 127.0.0.1)
    Note over K: Docker port mapping 8090 → 30080<br/>NodePort 30080 → Envoy Service
    K->>E: forwarded (externalTrafficPolicy: Cluster)
    Note over E: HTTPRoute: Host taskapi.localhost → backend taskapi:80
    E->>P: picks a READY endpoint from the EndpointSlice
    P-->>B: 200 [{"id":1,...}]
```

### ⌨️ Commands

```bash
# 1) Install Envoy Gateway (controller + Gateway API CRDs) with Helm
helm install eg oci://docker.io/envoyproxy/gateway-helm --version v1.10.0 \
  -n envoy-gateway-system --create-namespace --wait --timeout 5m
#   eg                 → release name (Helm's name for this installation)
#   oci://...          → the chart, downloaded from a container registry
#   --version v1.10.0  → pinned, like everything else
#   --wait             → don't return until the pods are ready
kubectl get crd | grep gateway        # the new object types Helm added

# 2) The platform part (front door) and the app part (route)
kubectl apply -f k8s/manifests/00-namespace.yaml        # adds the gateway-access label
kubectl apply -f k8s/platform/gateway.yaml
kubectl -n envoy-gateway-system wait --for=condition=Programmed gateway/main --timeout=180s
kubectl apply -f k8s/manifests/50-httproute.yaml

# 3) Check and call it
kubectl -n envoy-gateway-system get gateway,svc,pods -o wide
kubectl -n taskapi get httproute taskapi -o jsonpath='{range .status.parents[*].conditions[*]}{.type}={.status}{"\n"}{end}'
curl -s http://taskapi.localhost:8090/health
```

### 📤 Output

```
Pulled: docker.io/envoyproxy/gateway-helm:v1.10.0
STATUS: deployed

envoyproxy.gateway.envoyproxy.io/kind-nodeport created
gatewayclass.gateway.networking.k8s.io/envoy created
gateway.gateway.networking.k8s.io/main created
gateway.gateway.networking.k8s.io/main condition met
httproute.gateway.networking.k8s.io/taskapi created

NAME                                     CLASS   ADDRESS      PROGRAMMED
gateway.gateway.networking.k8s.io/main   envoy   172.18.0.4   True
NAME                                               TYPE       PORT(S)
service/envoy-envoy-gateway-system-main-b3b376e9   NodePort   80:30080/TCP      ← our fixed NodePort ✅
NAME                                                            READY   NODE
pod/envoy-envoy-gateway-system-main-b3b376e9-59d9c7c6b7-vglhs   2/2     devops-lab-worker
pod/envoy-gateway-867b7df877-48sd2                              1/1     devops-lab-worker

Accepted=True
ResolvedRefs=True

{"status":"ok","version":"sha-2273a31"}
```

And from **Windows** (PowerShell), the same URL works:

```powershell
curl.exe -s http://taskapi.localhost:8090/tasks
# [{"id":1,"title":"Learn Kubernetes","done":false,"created_at":"2026-11-24T12:55:33.182450Z"}]
```

Open **<http://taskapi.localhost:8090/docs>** in your browser: the same Swagger UI as Phase 1, now served by
Kubernetes. The badge shows the image version the pods run (`sha-2273a31`):

![Swagger UI served through the Gateway](images/03-swagger-via-gateway.png)

### 🧯 A trap we avoided: `externalTrafficPolicy`
`kubectl explain envoyproxy.spec.provider.kubernetes.envoyService` showed that Envoy's Service defaults to
`externalTrafficPolicy: Local` = "only serve requests that arrive on the node where an Envoy pod runs".
Our traffic enters through the **control-plane** node (that's where the port mapping is), but the Envoy pod runs
on a **worker** → every request would time out. We set `externalTrafficPolicy: Cluster` (forward from any node).
Lesson: `kubectl explain <type>.<field>` shows the built-in documentation of any field, including CRDs.

> 💡 The HTTPRoute's **status** is the first thing to check when a route doesn't work: `Accepted=False` usually
> means the namespace isn't allowed by the Gateway (missing label), `ResolvedRefs=False` means the Service name
> or port is wrong.

---
## Step 3.8: 🧪 Seven experiments: break things on purpose ✅

### 🎯 Objective
**Prove** that each setting from Steps 3.4–3.7 does what we claimed, by breaking things on purpose. This is what
separates "I copied a YAML" from "I know how it behaves in an incident".

| # | Experiment | Question | Result |
|---|---|---|---|
| A | Delete an API pod | Does Kubernetes heal itself? | ✅ new pod in ~5 s |
| B | Unknown hostname | Does the Gateway only route our host? | ✅ 404 for other hosts |
| C | Rolling update under load | Zero downtime? | ✅ 180/180 requests = 200 |
| D | Deploy a broken image | Does a bad release take the site down? | ✅ no; `rollout undo` fixes it |
| E | Kill the database | Liveness vs readiness for real | ⚠️ found **2 real problems**, fixed, ✅ |
| F | Delete the database pod | Does the data survive? | ✅ yes (PVC) |
| G | Load test | Does the HPA add pods? | ✅ 2 → 6 pods, then back to 2 |

> All outputs below are real. Commands are run inside Ubuntu, in the project folder.

---

### Experiment A: self-healing (delete a pod)

```bash
kubectl -n taskapi get pods -l app.kubernetes.io/component=api -o wide
kubectl -n taskapi delete pod <one-api-pod-name> --wait=false
kubectl -n taskapi get pods -l app.kubernetes.io/component=api -o wide     # immediately after
kubectl -n taskapi rollout status deploy/taskapi
```

```
NAME                       READY   STATUS    AGE     NODE
taskapi-6c7f9cc974-68bz9   1/1     Running   3m58s   devops-lab-worker     ← we delete this one
taskapi-6c7f9cc974-q5swt   1/1     Running   3m58s   devops-lab-worker2

pod "taskapi-6c7f9cc974-68bz9" deleted from taskapi namespace

NAME                       READY   STATUS    AGE   NODE
taskapi-6c7f9cc974-gvwjr   0/1     Running   1s    devops-lab-worker     ← replacement, 1 s old, not ready yet
taskapi-6c7f9cc974-q5swt   1/1     Running   4m    devops-lab-worker2    ← kept serving meanwhile

deployment "taskapi" successfully rolled out                              ← 5 s later: 2/2 ready again
```

**Why:** the ReplicaSet controller saw actual (1) ≠ desired (2) and created a pod. Note the replacement is
`0/1` for a moment: it only gets traffic once its readiness probe passes.

---

### Experiment B: routing by hostname

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://taskapi.localhost:8090/health    # -w prints only the status code
curl -s -o /dev/null -w "%{http_code}\n" http://other.localhost:8090/health
```

```
200
404      ← same IP and port, but no HTTPRoute for "other.localhost" → Envoy answers 404 itself
```

**Why:** one Gateway serves many apps; the `Host` header decides which HTTPRoute applies. In a company,
`api.example.com` and `shop.example.com` can share one load balancer this way.

---

### Experiment C: zero-downtime rolling update

While a background loop sends **one request every 0.1 s**, we switch to another image version:

```bash
# background load: 75 seconds of requests, recording only the status codes
( end=$((SECONDS+75)); while [ $SECONDS -lt $end ]; do
    curl -s -m 2 -o /dev/null -w "%{http_code}\n" http://taskapi.localhost:8090/health; sleep 0.1
  done ) > /tmp/codes.txt &

# the update: new image + matching APP_VERSION, in one change
kubectl -n taskapi patch deployment taskapi -p '{"spec":{"template":{"spec":{"containers":[{"name":"api","image":"ghcr.io/valinfernanda/taskapi:sha-5618b63","env":[{"name":"APP_VERSION","value":"sha-5618b63"}]}]}}}}'
kubectl -n taskapi annotate deployment taskapi kubernetes.io/change-cause="image sha-5618b63 (PR #5)" --overwrite
kubectl -n taskapi rollout status deploy/taskapi
kubectl -n taskapi get rs -o wide
kubectl -n taskapi rollout history deploy/taskapi
wait; sort /tmp/codes.txt | uniq -c        # count each status code
```

```
deployment.apps/taskapi patched
Waiting for deployment "taskapi" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "taskapi" rollout to finish: 1 old replicas are pending termination...
deployment "taskapi" successfully rolled out

NAME                 DESIRED   CURRENT   READY   IMAGES
taskapi-6c7f9cc974   0         0         0       ghcr.io/valinfernanda/taskapi:sha-2273a31   ← old ReplicaSet, scaled to 0 (kept for rollback)
taskapi-7c9dbbb6fd   2         2         2       ghcr.io/valinfernanda/taskapi:sha-5618b63   ← new ReplicaSet

REVISION  CHANGE-CAUSE
1         <none>
2         image sha-5618b63 (PR #5)

    180 200        ← 180 requests during the update, ALL returned 200 ✅
```

**Why it works:** `maxSurge: 1, maxUnavailable: 0` → start 1 new pod → wait until it's **ready** → only then
remove 1 old pod → repeat. Readiness probes are what make "ready" trustworthy.

```mermaid
sequenceDiagram
    participant D as Deployment controller
    participant Old as Old ReplicaSet (v1)
    participant New as New ReplicaSet (v2)
    Note over Old: 2 pods ready
    D->>New: scale to 1 (surge: 3 pods total)
    Note over New: pod 1 passes readiness
    D->>Old: scale to 1
    D->>New: scale to 2
    Note over New: pod 2 passes readiness
    D->>Old: scale to 0 (kept for rollback)
```

> 💡 `kubernetes.io/change-cause` is just an annotation shown in `rollout history`. Without it you only see
> `<none>`, and nobody knows what revision 7 was. In GitOps (Phase 6) Git history replaces this.

---

### Experiment D: a broken release, and rollback

A typo in the image tag, the kind of mistake that happens in real life:

```bash
kubectl -n taskapi set image deployment/taskapi api=ghcr.io/valinfernanda/taskapi:sha-doesnotexist
kubectl -n taskapi annotate deployment taskapi kubernetes.io/change-cause="typo: image tag does not exist" --overwrite
kubectl -n taskapi get pods -l app.kubernetes.io/component=api          # ~25 s later
kubectl -n taskapi describe pod <the-new-pod> | sed -n '/^Events:/,$p'   # WHY is it failing?
curl -s http://taskapi.localhost:8090/health                             # is the site down?
```

```
NAME                       READY   STATUS             RESTARTS   AGE
taskapi-7c9dbbb6fd-6bbzl   1/1     Running            0          106s    ← old pods: still serving
taskapi-7c9dbbb6fd-rwlj9   1/1     Running            0          2m
taskapi-8b7ccd5d8-hx4f8    0/1     ImagePullBackOff   0          27s     ← new pod: can't get its image

Events:
  Normal   Pulling  ...  Pulling image "ghcr.io/valinfernanda/taskapi:sha-doesnotexist"
  Warning  Failed   ...  Failed to pull image "...:sha-doesnotexist": ... not found
  Warning  Failed   ...  Error: ErrImagePull
  Normal   BackOff  ...  Back-off pulling image "...:sha-doesnotexist"
  Warning  Failed   ...  Error: ImagePullBackOff

{"status":"ok","version":"sha-5618b63"}     ← the site is UP ✅ (maxUnavailable: 0 → old pods never removed)
```

**Rollback:**

```bash
kubectl -n taskapi rollout history deploy/taskapi
kubectl -n taskapi rollout undo deploy/taskapi        # back to the previous revision
kubectl -n taskapi rollout status deploy/taskapi
kubectl -n taskapi rollout history deploy/taskapi
```

```
REVISION  CHANGE-CAUSE
1         <none>
2         image sha-5618b63 (PR #5)
3         typo: image tag does not exist

Warning: resource deployments/taskapi was previously managed with 'kubectl apply'. Rolling back will not update
the kubectl.kubernetes.io/last-applied-configuration annotation, which may cause unexpected behavior on future
'kubectl apply' operations. Consider using 'kubectl apply' with your previous configuration file instead.
deployment.apps/taskapi rolled back
deployment "taskapi" successfully rolled out

REVISION  CHANGE-CAUSE
1         <none>
3         typo: image tag does not exist
4         image sha-5618b63 (PR #5)     ← revision 2 came back as NEW revision 4
```

> ⚠️ **That warning matters.** `rollout undo` changed the cluster, but **not** the YAML file. The file and the
> cluster now disagree, and the next `kubectl apply` of the file silently wins. This "drift" is exactly the problem
> **GitOps** solves (Phase 6): the fix for a bad release is a `git revert` + merge, and ArgoCD applies it, so Git
> stays the single source of truth. `rollout undo` is the emergency button, not the normal process.

**How to read a failing pod, in order:** `kubectl get pods` (status) → `kubectl describe pod` (**Events** at the
bottom: scheduling, image pulls, probe failures) → `kubectl logs` (the app's own output; add `--previous` for the
crashed container before the current one).

---

### Experiment E: the database dies (liveness vs readiness, for real) ⚠️

**Expected** (from Phase 1, Step 1.12): API pods become **not ready** (no traffic) but are **not restarted**.

```bash
kubectl -n taskapi scale statefulset postgres --replicas=0         # "turn the database off"
kubectl -n taskapi get pods
curl -s -w " [HTTP %{http_code}]\n" http://taskapi.localhost:8090/tasks
kubectl -n taskapi get events --field-selector reason=Unhealthy | tail -3
```

#### First run: two surprises

```
NAME                       READY   STATUS      RESTARTS   AGE
taskapi-7c9dbbb6fd-6bbzl   0/1     Running     0          2m11s    ← not ready ✅, 0 restarts ✅
taskapi-7c9dbbb6fd-rwlj9   0/1     Running     0          2m25s

Internal Server Error [HTTP 500]                                   ← ❌ surprise 1: we expected 503

Readiness probe failed: Get "http://10.244.2.6:8000/ready": context deadline exceeded   ← ❌ surprise 2: TIMEOUT,
                                                                                           not a clean 503
```

#### Investigation (how a DevOps engineer digs in)

**Surprise 2 first: why does `/ready` time out?** Measure it from inside a pod:

```bash
kubectl -n taskapi exec <api-pod> -- python -c "import time,urllib.request as u
t=time.time()
try: u.urlopen('http://127.0.0.1:8000/ready')
except Exception as e: print('ready', e.code)
print('took %.1f s' % (time.time()-t))"
```

```
ready 503
took 4.1 s          ← the app DOES answer 503, but after 4.1 s; the probe gives up after 2 s (timeoutSeconds: 2)
```

Where do 4 seconds go? Look at the pod's DNS settings, then time the lookup itself:

```bash
kubectl -n taskapi exec <api-pod> -- cat /etc/resolv.conf
kubectl -n taskapi exec <api-pod> -- python -c "import socket,time
for h in ('postgres','postgres.taskapi.svc.cluster.local.'):
    t=time.time()
    try: socket.getaddrinfo(h,5432); r='found'
    except Exception as e: r=type(e).__name__
    print('%-40s %-10s %.2f s' % (h, r, time.time()-t))"
```

```
search taskapi.svc.cluster.local svc.cluster.local cluster.local
nameserver 10.96.0.10
options ndots:5

postgres                                 gaierror   4.07 s    ← short name: 4 seconds to say "doesn't exist"
postgres.taskapi.svc.cluster.local.      gaierror   0.00 s    ← full name with trailing dot: instant
```

📚 **Concept: the DNS search list.** `ndots:5` means "a name with fewer than 5 dots is probably short: try it with
each `search` suffix first". So `postgres` is tried as `postgres.taskapi.svc.cluster.local`,
`postgres.svc.cluster.local`, `postgres.cluster.local`, then `postgres` itself, which leaves the cluster and goes
to the upstream DNS (your laptop's), and that's the slow part. While the database exists, the first try succeeds
immediately, so you never notice. A **trailing dot** means "this name is complete": one query, no search.

**Surprise 1: why 500 and not 503?** Look at the EndpointSlice and at Envoy's own view of the backends:

```bash
kubectl -n taskapi get endpointslice -l kubernetes.io/service-name=taskapi \
  -o jsonpath='{range .items[*].endpoints[*]}{.addresses[0]} ready={.conditions.ready}{"\n"}{end}'
# Envoy's admin page (port 19000 on the Envoy pod) lists every backend with its health flags
kubectl -n envoy-gateway-system port-forward <envoy-pod> 19000:19000 &
curl -s localhost:19000/clusters | grep taskapi | grep health_flags
```

```
10.244.2.5 ready=false                                         ← Kubernetes correctly marks both pods not ready
10.244.2.6 ready=false
httproute/taskapi/taskapi/rule/0::10.244.2.5:8000::health_flags::/eds_status_draining
httproute/taskapi/taskapi/rule/0::10.244.2.6:8000::health_flags::/eds_status_draining
```

Envoy knows both pods are unhealthy, and **still** sends traffic to them. That's Envoy's **panic mode**: if more
than 50% of backends are unhealthy, it assumes the *health checks* are wrong and balances across **all** of them
(designed to avoid turning a monitoring bug into a total outage). So the request reached a pod with no database,
and the app answered with an unhandled error → **500**. (`kubectl explain backendtrafficpolicy.spec.healthCheck.panicThreshold`
documents it: *"To disable panic mode, set value to 0"*.)

#### The two fixes

| Problem | Fix | File |
|---|---|---|
| Slow DNS → readiness probe times out | `DB_HOST: "postgres.taskapi.svc.cluster.local."` (fully qualified + trailing dot) | `10-configmap.yaml` |
| Panic mode → traffic to broken pods → 500 | `BackendTrafficPolicy` with `healthCheck.panicThreshold: 0` | `50-httproute.yaml` |

```bash
kubectl apply -f k8s/manifests/10-configmap.yaml -f k8s/manifests/50-httproute.yaml
kubectl -n taskapi rollout restart deployment/taskapi     # ← needed! see the box below
kubectl -n taskapi exec <api-pod> -- printenv DB_HOST
```

> ⚠️ **A ConfigMap change does NOT reach running pods.** Environment variables are read once, when the container
> starts. After changing a ConfigMap you must restart the pods (`kubectl rollout restart` = a rolling update with
> no image change, so still zero downtime). The Helm chart (Step 3.9) does this automatically with a checksum.

#### Second run: everything as designed ✅

```
NAME                       READY   STATUS    RESTARTS   AGE
taskapi-5dbc9d85dc-dj4nr   0/1     Running   0          26s     ← not ready, no restarts

ready 503 {"status":"not ready","reason":"database unreachable"}
took 0.04 s                                                      ← was 4.1 s

no healthy upstream [HTTP 503]                                   ← was 500: Envoy answers itself, fast and honest

# database back:
kubectl -n taskapi scale statefulset postgres --replicas=1
[{"id":1,"title":"Learn Kubernetes",...}] [HTTP 200]             ← recovered by itself, no restarts needed
```

```mermaid
flowchart LR
    subgraph before["Before the fixes"]
        a1["DB down"] --> a2["/ready takes 4 s<br/>(DNS search list)"] --> a3["probe timeout → not ready"]
        a3 --> a4["0 ready pods → Envoy panic mode"] --> a5["traffic sent anyway → app error → 500"]
    end
    subgraph after["After the fixes"]
        b1["DB down"] --> b2["/ready answers 503 in 0.04 s"] --> b3["not ready"]
        b3 --> b4["panic mode off"] --> b5["Envoy: 503 no healthy upstream"]
    end
```

> 👩‍💻 **For the programmer side** (not fixed here; it's app code): when the database fails during a request, the
> app returns a generic **500**. A friendlier app would catch database connection errors and return **503**
> (`Service Unavailable`, "try again later"). With our fixes users never reach that code path in this scenario,
> but it would still show up if the database died *during* a request.

---

### Experiment F: does the data survive a database pod delete?

```bash
curl -s -X POST http://taskapi.localhost:8090/tasks -H 'Content-Type: application/json' -d '{"title":"Survive a pod delete"}'
kubectl -n taskapi delete pod postgres-0
kubectl -n taskapi rollout status statefulset/postgres
kubectl -n taskapi get pod postgres-0 -o wide
kubectl -n taskapi get pvc
curl -s http://taskapi.localhost:8090/tasks
```

```
{"id":2,"title":"Survive a pod delete",...}
pod "postgres-0" deleted from taskapi namespace

NAME         READY   STATUS    RESTARTS   AGE   IP           NODE
postgres-0   1/1     Running   0          12s   10.244.2.8   devops-lab-worker2   ← SAME name, new pod (new IP)
NAME              STATUS   VOLUME                                     CAPACITY
data-postgres-0   Bound    pvc-bc6103ed-96e4-4d59-b671-f23a10dbcb5a   1Gi        ← SAME volume as in Step 3.4

[{"id":1,"title":"Learn Kubernetes",...},{"id":2,"title":"Survive a pod delete",...}]   ← both tasks still there ✅
```

**Why:** the StatefulSet recreated the pod with the **same name** `postgres-0`, and the PVC `data-postgres-0`
belongs to that name, so the same disk was mounted again. The pod's IP changed, which is exactly why apps use
the Service's DNS name, never a pod IP.

> ⚠️ kind's `local-path` disks live on **one node** (here `worker2`). If that node were deleted, the data would be
> gone. Cloud disks (Azure Disk in Phase 8) can move between nodes; and real databases need **backups** anyway.

---
### Experiment G: autoscaling under load (HPA)

#### G.1 Install metrics-server
The HPA needs to know how much CPU each pod uses. **metrics-server** collects it from every node's kubelet.

```bash
helm install metrics-server metrics-server --repo https://kubernetes-sigs.github.io/metrics-server/ \
  --version 3.14.0 -n kube-system --set "args={--kubelet-insecure-tls}" --wait --timeout 3m
#   --repo …             → install straight from the chart repository URL (no "helm repo add" needed)
#   --set "args={…}"     → override one chart value: extra command-line flags for metrics-server
#   --kubelet-insecure-tls → kind's kubelets use self-signed certificates; OK on a laptop, NOT in production
kubectl top nodes            # works ~45 s after install
kubectl -n taskapi top pods
```

```
  Chart version: 3.14.0
  App version:   0.9.0
  Image tag:     registry.k8s.io/metrics-server/metrics-server:v0.9.0

NAME                       CPU(cores)   CPU(%)   MEMORY(bytes)   MEMORY(%)
devops-lab-control-plane   416m         3%       1206Mi          7%
devops-lab-worker          114m         0%       469Mi           3%
devops-lab-worker2         172m         1%       458Mi           2%
```

#### G.2 Put the files back in charge, then create the HPA

```bash
kubectl apply -f k8s/manifests/40-api.yaml     # Experiments C/D changed the cluster by hand → re-apply the file
kubectl apply -f k8s/manifests/60-hpa.yaml
kubectl -n taskapi get hpa
```

```
deployment.apps/taskapi configured          ← "configured" = the file DIFFERED from the cluster: drift from
                                              Experiments C/D (image sha-5618b63) is overwritten → back to sha-2273a31
horizontalpodautoscaler.autoscaling/taskapi created
NAME      REFERENCE            TARGETS       MINPODS   MAXPODS   REPLICAS
taskapi   Deployment/taskapi   cpu: 4%/50%   2         6         2
```

The HPA rule ([`60-hpa.yaml`](../k8s/manifests/60-hpa.yaml)): keep average CPU at **50% of the request**
(request = 100m, so ~50m per pod), between **2 and 6** pods:

> desired pods = ceil( current pods × current % ÷ target % ). Example: 2 × 1009 ÷ 50 = 40.4 → capped at **6**.

#### G.3 Generate load
A throwaway pod in a separate namespace runs 8 parallel loops calling the API through its Service DNS name
for 3 minutes (namespace `load` has no "restricted" label, so a quick `kubectl run` is allowed there):

```bash
kubectl create namespace load
kubectl -n load run load --image=busybox:1.37 --restart=Never -- sh -c \
  'for i in 1 2 3 4 5 6 7 8; do (while true; do wget -q -O /dev/null http://taskapi.taskapi.svc.cluster.local/tasks; done) & done; sleep 180'
watch -n 5 kubectl -n taskapi get hpa        # or: kubectl -n taskapi get hpa -w
```

`taskapi.taskapi.svc.cluster.local` = *service*.*namespace*.svc.cluster.local: the full DNS name of a Service,
callable from **any** namespace.

#### 📤 What happened (every 20 s)

```
                     TARGETS            MINPODS   MAXPODS   REPLICAS
t=+20s    cpu: 4%/50%          2         6         2        ← metrics lag: ~1 scrape interval behind
t=+40s    cpu: 4%/50%          2         6         2
t=+60s    cpu: 1009%/50%       2         6         6        ← 10× the target → straight to the maximum
t=+80s    cpu: 651%/50%        2         6         6
t=+120s   cpu: 410%/50%        2         6         6
t=+180s   cpu: 407%/50%        2         6         6        ← still above target, but maxReplicas reached
```

```
$ kubectl -n taskapi get pods -l app.kubernetes.io/component=api -o wide
NAME                       READY   STATUS    NODE
taskapi-7bb99f6747-84fbd   1/1     Running   devops-lab-worker2
taskapi-7bb99f6747-dp7wj   1/1     Running   devops-lab-worker2
taskapi-7bb99f6747-gx4m5   1/1     Running   devops-lab-worker
taskapi-7bb99f6747-p8gkb   1/1     Running   devops-lab-worker2
taskapi-7bb99f6747-rlplv   1/1     Running   devops-lab-worker
taskapi-7bb99f6747-rwbnd   1/1     Running   devops-lab-worker         ← 3 + 3: topology spread at work

$ kubectl -n taskapi top pods
NAME                       CPU(cores)   MEMORY(bytes)
postgres-0                 434m         73Mi        ← the database is working hard too
taskapi-7bb99f6747-84fbd   407m         66Mi
...                        (all 6 API pods ~370–440m)

$ kubectl -n taskapi describe hpa taskapi        (Events)
  Warning  FailedGetResourceMetric  … did not receive metrics for targeted pods (pods might be unready)
  Normal   SuccessfulRescale        … New size: 6; reason: cpu resource utilization (percentage of request) above target
```

Then the load stopped (`kubectl delete namespace load`) and we watched it scale **down**:

```
after +20s    cpu: 373%/50%    6
after +40s    cpu: 5%/50%      6     ← load gone, but the HPA waits (stabilizationWindowSeconds: 60)
after +60s    cpu: 6%/50%      6
after +80s    cpu: 4%/50%      6
after +100s   cpu: 4%/50%      2     ← back to minReplicas
```

#### What this teaches

| Observation | Lesson |
|---|---|
| Up in one jump (2 → 6), down only after 60 s of calm | Scale-**up** is fast on purpose; scale-**down** waits so a short dip doesn't remove pods you need a minute later ("flapping"). Default is 300 s; we set 60 s to see it |
| CPU stayed at ~400% even with 6 pods | Our load generator is *unlimited* (8 loops as fast as possible): more pods = more throughput, not less CPU per pod. With real users, load per pod drops as pods are added |
| `maxReplicas` reached and still above target | In real life, check the cluster can actually fit `maxReplicas` pods (requests × max), or pods stay `Pending` |
| The first `FailedGetResourceMetric` warnings | Normal right after creating an HPA: new pods have no metrics for the first ~30 s |
| No CPU **limit** → each pod used ~400m with a 100m request | Requests are a guaranteed minimum, not a cap. That's why we set memory limits but no CPU limit (Step 3.6) |
| The database was at 434m too | Scaling the API doesn't scale the database: the next bottleneck moves downstream |

> ⚠️ Once the HPA owns the replica count, the `replicas: 2` line in `40-api.yaml` fights it: every
> `kubectl apply` of that file resets to 2. The Helm chart omits `replicas` when autoscaling is on (Step 3.9).

---
## Step 3.9: The same app as a Helm chart (dev + prod) ✅

### 🎯 Objective
Package everything from Steps 3.3–3.8 into **one reusable chart**, then install it twice, as **dev** and
**prod**, with different settings and no copy-pasted YAML.

### ❓ Why Helm? What was wrong with plain YAML?
Try to run a second copy (prod) with plain YAML and you'd have to copy all 7 files and edit names, namespaces,
replica counts, hostnames… by hand. Plus:

| Plain YAML problem we hit | Helm's answer |
|---|---|
| A second environment = copy-paste everything | **One chart + a values file per environment** |
| ConfigMap change didn't restart pods (Exp. E) | `checksum/config` annotation → automatic rollout |
| Job can't be re-applied; migrations by hand | Migration Job as a **hook** (`post-install`, `pre-upgrade`) |
| `replicas:` fights the HPA (Exp. G) | `{{ if not .Values.autoscaling.enabled }}replicas: …{{ end }}` |
| Secret created by hand, must stay stable | `lookup` reuses the existing password on upgrade |
| `rollout undo` drifted from the files (Exp. D) | `helm rollback`: Helm stores every release revision (still drift vs Git → GitOps in Phase 6) |
| "Is it working?" checked by hand | `helm test` runs a test pod |

### 📚 Concept: chart, values, release

```mermaid
flowchart LR
    chart["Chart helm/taskapi/<br/>templates/*.yaml with {{ .Values.x }}"]
    v["values.yaml<br/>(defaults)"]
    vd["values-dev.yaml<br/>(only differences)"]
    vp["values-prod.yaml<br/>(only differences)"]
    chart & v & vd -->|"helm upgrade --install<br/>-n taskapi-dev -f values-dev.yaml"| rd["Release 'taskapi'<br/>in taskapi-dev"]
    chart & v & vp -->|"helm upgrade --install<br/>-n taskapi-prod -f values-prod.yaml"| rp["Release 'taskapi'<br/>in taskapi-prod"]
```

- **Chart**: a folder of templates + default values ([`helm/taskapi/`](../helm/taskapi/)).
- **Values**: the settings poured into the templates. Priority: `values.yaml` < `-f` files (in order) < `--set`.
- **Release**: one installed copy of a chart, with a name, a namespace and a **revision history**.

### The chart, file by file

```
helm/taskapi/
├── Chart.yaml                ← name, chart version (0.1.0), appVersion (default image tag: sha-2273a31)
├── values.yaml               ← ALL settings with defaults + comments: read this first
├── values-dev.yaml           ← dev: 1 replica, debug logs, host taskapi-dev.localhost
├── values-prod.yaml          ← prod: HPA 3–10, PDB minAvailable 2, bigger requests, 5Gi disk, host taskapi.localhost
└── templates/
    ├── _helpers.tpl          ← reusable snippets: names, labels, image, DB env vars, security settings
    ├── configmap.yaml
    ├── secret.yaml           ← random password, kept across upgrades (lookup) and uninstalls (resource-policy: keep)
    ├── postgres.yaml         ← Service + StatefulSet, only if postgres.enabled
    ├── migrate-job.yaml      ← Helm HOOK: post-install + pre-upgrade
    ├── deployment.yaml       ← checksum/config annotation; no replicas when HPA is on
    ├── service.yaml
    ├── httproute.yaml        ← HTTPRoute (+ BackendTrafficPolicy: panic mode off)
    ├── hpa.yaml              ← only if autoscaling.enabled
    ├── pdb.yaml              ← only if podDisruptionBudget.enabled
    ├── NOTES.txt             ← text printed after install
    └── tests/test-health.yaml ← "helm test": calls /ready from inside the cluster
```

### 📚 Concept: reading a template
From [`templates/deployment.yaml`](../helm/taskapi/templates/deployment.yaml):

```yaml
spec:
  {{- if not .Values.autoscaling.enabled }}      # {{- … }} = template logic; "-" trims whitespace
  replicas: {{ .Values.replicaCount }}           # value from values*.yaml
  {{- end }}
  template:
    metadata:
      labels:
        {{- include "taskapi.selectorLabels" . | nindent 8 }}   # call a helper, indent 8 spaces
      annotations:
        checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
```

| Syntax | Meaning |
|---|---|
| `{{ .Values.x }}` | A value from the values files |
| `{{ .Release.Name }}` / `.Release.Namespace` | Name / namespace given at install time |
| `{{ .Chart.AppVersion }}` | From `Chart.yaml` |
| `{{ if … }} … {{ end }}` | Include a block only when true |
| `{{ include "name" . }}` | Insert a helper from `_helpers.tpl` |
| `\| nindent 8` / `\| quote` / `\| default x` | Pipes: indent, add quotes, fallback value |
| `{{ required "msg" .Values.x }}` | Fail the install with "msg" if x is empty |

**See the YAML Helm would produce, without touching the cluster** (the #1 debugging tool):

```bash
helm lint helm/taskapi -f helm/taskapi/values-prod.yaml                           # syntax + best practices
helm template taskapi helm/taskapi -n taskapi-prod -f helm/taskapi/values-prod.yaml   # render everything
helm template taskapi helm/taskapi -f helm/taskapi/values-dev.yaml -s templates/deployment.yaml   # one file
```

```
==> Linting helm/taskapi
[INFO] Chart.yaml: icon is recommended
1 chart(s) linted, 0 chart(s) failed
```

What each environment renders (`helm template … | grep '^kind:'`):

| Object | dev | prod |
|---|---|---|
| Secret, ConfigMap, 2 Services, Deployment, StatefulSet, HTTPRoute, BackendTrafficPolicy, migrate Job, test Pod | ✅ | ✅ |
| HorizontalPodAutoscaler | — | ✅ (3–10 pods) |
| PodDisruptionBudget | — | ✅ (min 2 available) |
| `replicas:` in the Deployment | `1` | *(omitted: the HPA decides)* |

And a guardrail working (`required` in `_helpers.tpl`):

```bash
helm template taskapi helm/taskapi --set postgres.enabled=false
# Error: execution error at (taskapi/templates/migrate-job.yaml:42:24): database.externalHost is required when postgres.enabled=false
```

### 📚 Concept: why migrations are a hook (`post-install,pre-upgrade`)

```mermaid
sequenceDiagram
    participant H as helm upgrade --install
    participant K as Kubernetes
    Note over H,K: FIRST INSTALL
    H->>K: Secret, ConfigMap, Services, StatefulSet, Deployment, HTTPRoute
    H->>K: wait until ready (--wait)
    H->>K: post-install hook: migrate Job → tables created
    Note over H,K: EVERY UPGRADE (e.g. new image)
    H->>K: pre-upgrade hook: migrate Job with the NEW image
    Note over K: new schema in place BEFORE new code runs
    H->>K: apply changed objects → rolling update
```

- Not `pre-install`: on the very first install the Secret and database don't exist yet, so the Job would fail.
- `pre-upgrade`: new code may need the new columns, so migrate **before** rolling out. This also means
  migrations must be **backward compatible** (old pods still run for a moment during the rollout): add a
  column in one release, start using it in the next. That's a programmer + DevOps agreement.
- `hook-delete-policy: before-hook-creation`: the previous Job is deleted right before a new one is created,
  so the last run's logs stay readable.

### ⌨️ Install it: dev, then prod

The hand-made version (namespace `taskapi`) is removed first: its HTTPRoute uses the same hostname as prod.
The namespaces come from the **platform** side ([`k8s/platform/namespaces.yaml`](../k8s/platform/namespaces.yaml)),
not from `helm --create-namespace`, which would create them **without** the security and gateway labels.

```bash
kubectl delete namespace taskapi                 # deletes EVERYTHING inside it, including the PVC (= the data)
kubectl apply -f k8s/platform/namespaces.yaml

helm upgrade --install taskapi helm/taskapi -n taskapi-dev -f helm/taskapi/values-dev.yaml --wait --timeout 5m
#   upgrade --install → install if missing, upgrade if present: the same command every time (idempotent)
#   taskapi           → release name
#   helm/taskapi      → the chart folder
#   -f …              → extra values file(s), applied on top of values.yaml
#   --wait            → return only when everything is ready (and hooks are done)

helm list -A
helm test taskapi -n taskapi-dev
kubectl -n taskapi-dev logs taskapi-test-health
curl -s http://taskapi-dev.localhost:8090/health

helm upgrade --install taskapi helm/taskapi -n taskapi-prod -f helm/taskapi/values-prod.yaml --wait --timeout 6m
kubectl -n taskapi-prod get pods -o wide
kubectl -n taskapi-prod get hpa,pdb
```

### 📤 Output

```
Release "taskapi" does not exist. Installing it now.
STATUS: deployed
REVISION: 1

NAME                          READY   STATUS      AGE
pod/taskapi-c554787cf-vqm5v   1/1     Running     26s      ← dev: 1 replica (values-dev.yaml)
pod/taskapi-migrate-l7wr6     0/1     Completed   9s       ← the post-install hook ran AFTER the rest was ready
pod/taskapi-postgres-0        1/1     Running     26s
NAME                                          HOSTNAMES
httproute.gateway.networking.k8s.io/taskapi   ["taskapi-dev.localhost"]

TEST SUITE:     taskapi-test-health
Phase:          Succeeded
http://taskapi/ready 200 {"status":"ready"}                ← helm test: called from INSIDE the cluster ✅

{"status":"ok","version":"sha-2273a31"}                    ← http://taskapi-dev.localhost:8090/health

--- prod ---
NAME                       READY   STATUS      NODE
taskapi-6944d4cb94-8lmxj   1/1     Running     devops-lab-worker     ← 3 replicas (HPA minReplicas)
taskapi-6944d4cb94-sf7z9   1/1     Running     devops-lab-worker2
taskapi-6944d4cb94-w2r8k   1/1     Running     devops-lab-worker2
taskapi-migrate-2gzb4      0/1     Completed   devops-lab-worker2
taskapi-postgres-0         1/1     Running     devops-lab-worker

NAME                                          REFERENCE            TARGETS              MINPODS   MAXPODS   REPLICAS
horizontalpodautoscaler.autoscaling/taskapi   Deployment/taskapi   cpu: <unknown>/50%   3         10        3
NAME                                 MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS
poddisruptionbudget.policy/taskapi   2               N/A               1      ← a node drain may evict only 1 pod at a time

NAME            NAMESPACE              REVISION   STATUS     CHART                  APP VERSION
eg              envoy-gateway-system   1          deployed   gateway-helm-v1.10.0   v1.10.0
metrics-server  kube-system            1          deployed   metrics-server-3.14.0  0.9.0
taskapi         taskapi-dev            1          deployed   taskapi-0.1.0          sha-2273a31
taskapi         taskapi-prod           1          deployed   taskapi-0.1.0          sha-2273a31
```

> `cpu: <unknown>` right after install is normal: metrics-server needs ~30–60 s to collect the new pods' CPU.
> `helm list -A` also shows the two platform charts we installed earlier: Helm isn't only for our own app.

**Two environments, two separate databases**, same cluster, same chart:

```bash
curl -s -X POST http://taskapi.localhost:8090/tasks     -H 'Content-Type: application/json' -d '{"title":"Hello from prod"}'
curl -s -X POST http://taskapi-dev.localhost:8090/tasks -H 'Content-Type: application/json' -d '{"title":"Hello from dev"}'
curl -s http://taskapi.localhost:8090/tasks
curl -s http://taskapi-dev.localhost:8090/tasks
```

```
[{"id":1,"title":"Hello from prod",...}]     ← prod only sees prod data
[{"id":1,"title":"Hello from dev",...}]      ← dev only sees dev data (both are id 1: separate databases)
```

### ⌨️ Upgrade, history, rollback

```bash
helm upgrade taskapi helm/taskapi -n taskapi-dev -f helm/taskapi/values-dev.yaml --set image.tag=sha-5618b63 --wait
kubectl -n taskapi-dev get jobs                          # the pre-upgrade hook ran a NEW migrate Job
curl -s http://taskapi-dev.localhost:8090/health
helm history taskapi -n taskapi-dev
helm rollback taskapi 1 -n taskapi-dev --wait            # back to revision 1
helm history taskapi -n taskapi-dev
curl -s http://taskapi-dev.localhost:8090/health
```

```
Release "taskapi" has been upgraded. Happy Helming!
REVISION: 2
NAME              STATUS     COMPLETIONS   DURATION   AGE
taskapi-migrate   Complete   1/1           6s         13s       ← 13 s old: re-created by the hook for this upgrade
{"status":"ok","version":"sha-5618b63"}

# password fingerprint before upgrade: 8deb3acf6a86  after: 8deb3acf6a86   ← "lookup" kept the same password ✅

REVISION  UPDATED                    STATUS      CHART          APP VERSION   DESCRIPTION
1         Tue Nov 24 14:14:58 2026   superseded  taskapi-0.1.0  sha-2273a31   Install complete
2         Tue Nov 24 14:16:04 2026   superseded  taskapi-0.1.0  sha-2273a31   Upgrade complete
3         Tue Nov 24 14:16:20 2026   deployed    taskapi-0.1.0  sha-2273a31   Rollback to 1

Rollback was a success! Happy Helming!
{"status":"ok","version":"sha-2273a31"}
```

> ⚠️ Two things to notice in `helm history`:
> - The **APP VERSION** column shows `sha-2273a31` for revision 2 too, though it ran `sha-5618b63`: that column is
>   `appVersion` from `Chart.yaml`, not the `--set image.tag` we passed. The real source of truth is
>   `helm get values taskapi -n taskapi-dev --revision 2`. That's why CI should bump the chart (or a values file in
>   Git) instead of using `--set` by hand: Phase 6.
> - A rollback runs **no migration**. If revision 2 had added a column, the database keeps it after the rollback.
>   Schema changes must be backward compatible (Step 3.9 hook concept): the old code must run on the new schema.

### ⌨️ Config change → automatic rollout (the checksum)

```bash
helm upgrade taskapi helm/taskapi -n taskapi-dev -f helm/taskapi/values-dev.yaml --set app.logLevel=warning --wait
kubectl -n taskapi-dev get pods -l app.kubernetes.io/component=api
kubectl -n taskapi-dev get configmap taskapi-config -o jsonpath='{.data}'
helm get values taskapi -n taskapi-dev                  # what was passed to this release (files + --set)
```

```
REVISION: 4
NAME                       READY   STATUS        AGE
taskapi-57cd74cbdd-4cbz7   1/1     Running       9s      ← NEW pod: the ConfigMap's checksum changed → new pod template
taskapi-c554787cf-fw65v    1/1     Terminating   34s     ← old pod leaving

{"APP_LOG_LEVEL":"warning"}

USER-SUPPLIED VALUES:
app:
  logLevel: warning
httpRoute:
  hostname: taskapi-dev.localhost
postgres:
  storage: 1Gi
replicaCount: 1
```

No `kubectl rollout restart` needed this time: compare with Experiment E.

> 💡 You may briefly see an API pod with status **`Completed`** during a rollout. That's an old pod whose uvicorn
> exited cleanly (exit code 0) after SIGTERM, a sign the graceful shutdown from our Dockerfile's exec-form `CMD`
> works. It disappears a few seconds later.

### 📚 Concept: who owns what in a Helm world

| Piece | Owner | Why |
|---|---|---|
| Cluster, Envoy Gateway, metrics-server, namespaces + their labels | 🛠️ Platform / DevOps | Shared by every team; security decisions |
| The chart (`helm/taskapi/`) | 🤝 DevOps writes it, app team reviews | Encodes how the app runs: probes, resources, hooks |
| `values-prod.yaml` | 🛠️ DevOps (with app team input) | Capacity, autoscaling, disruption budget |
| The image tag deployed | 🤖 CI / GitOps (Phase 6) | Never typed by hand in production |

### Rebuild everything with one command
[`scripts/k8s-up.sh`](../scripts/k8s-up.sh) chains Steps 3.2, 3.7, 3.8 G (metrics-server) and 3.9. It's
**idempotent** (`helm upgrade --install`, `kubectl apply`, "cluster already exists" check), so you can run it
again any time:

```bash
bash scripts/k8s-up.sh          # cluster + platform + dev
bash scripts/k8s-up.sh prod     # ... + prod
```
Tested by re-running it on the existing cluster (output shortened):

```
==> 1/5 kind cluster 'devops-lab'
already exists
==> 2/5 Envoy Gateway v1.10.0 (Gateway API implementation)
STATUS: deployed                       ← slowest step on re-runs: the chart's certgen hook pulls an image
==> 3/5 metrics-server (for kubectl top + HPA)
STATUS: deployed
==> 4/5 platform: Gateway + namespaces
gateway.gateway.networking.k8s.io/main unchanged
namespace/taskapi-dev unchanged        ← "unchanged" = nothing to do: that's idempotency
==> 5/5 app: Helm release(s)
STATUS: deployed
==> done
taskapi   taskapi-dev    5   deployed   taskapi-0.1.0   sha-2273a31
taskapi   taskapi-prod   2   deployed   taskapi-0.1.0   sha-2273a31
```

---

## 🧯 Troubleshooting: symptom → first command

| Symptom | First command | Typical cause |
|---|---|---|
| `kind create cluster` fails: *ports are not available* | `Get-NetTCPConnection -LocalPort <port> -State Listen` (PowerShell) | Another program uses the port (Step 3.2) |
| Pod `Pending` | `kubectl describe pod <p>` → Events | Not enough CPU/RAM for the requests; PVC not bound |
| `ImagePullBackOff` | `kubectl describe pod <p>` → Events | Wrong tag, private image (Experiment D) |
| `CrashLoopBackOff` | `kubectl logs <p> --previous` | App crashes at start (bad config, missing env var) |
| `Running` but `0/1` | `kubectl describe pod <p>` → *Readiness probe failed* | Dependency down; probe path/port wrong; probe timeout (Experiment E) |
| Pod rejected: *violates PodSecurity "restricted"* | read the message: it lists the missing fields | `runAsNonRoot`, `allowPrivilegeEscalation`, `capabilities`, `seccompProfile` |
| Changed a ConfigMap, nothing happens | `kubectl exec <p> -- printenv X` | Env vars are read at start → `kubectl rollout restart` |
| Gateway URL → 404 | `kubectl get httproute -A` + its `status` | Hostname mismatch; namespace missing `gateway-access` label (`Accepted=False`) |
| Gateway URL → 503 *no healthy upstream* | `kubectl get pods` / `get endpointslices` | No ready pod behind the Service (that's correct behavior!) |
| Gateway URL → timeout | `kubectl -n envoy-gateway-system get svc,pods -o wide` | NodePort not 30080, `externalTrafficPolicy: Local` (Step 3.7) |
| `kubectl top` → *metrics not available* | `kubectl -n kube-system get pods \| grep metrics` | metrics-server missing or not ready yet (~45 s) |
| HPA `cpu: <unknown>` | `kubectl describe hpa <name>` | Pods have no CPU **request**, or metrics not collected yet |
| `helm install` → *cannot re-use a name that is still in use* | `helm list -A` | Use `helm upgrade --install` (idempotent) |
| Helm template error | `helm template … --debug` | YAML indentation (`nindent`), missing value (`required`) |
| Everything is weird | `kubectl get events -A --sort-by=.metadata.creationTimestamp \| tail -30` | Read the most recent events cluster-wide |

---

## ✅ Phase 3 summary

**What you have now**
- A 3-node Kubernetes cluster on your laptop (kind, Kubernetes v1.37), rebuildable with one command:
  `bash scripts/k8s-up.sh`.
- The Task API running from the **CI-built image** on GHCR, with 3 kinds of probes, resource requests/limits,
  "restricted" pod security, spread across nodes, zero-downtime rolling updates.
- PostgreSQL as a StatefulSet with a persistent disk; migrations as a Job with an init container.
- A modern front door: **Gateway API + Envoy Gateway**, platform (`Gateway`) separated from app (`HTTPRoute`).
- Autoscaling (HPA + metrics-server), proven under load: 2 → 6 → 2 pods.
- A **Helm chart** with dev and prod values, migration hooks, auto-restart on config change, stable secrets,
  `helm test`, upgrade + rollback, installed twice in the same cluster.

**Concepts you met**
desired state & controllers · control plane vs nodes · Pod / ReplicaSet / Deployment / StatefulSet / Job ·
Service, headless Service, EndpointSlice, cluster DNS (`svc.namespace.svc.cluster.local`) · ConfigMap & Secret,
`$(VAR)` composition · PV / PVC / StorageClass · Pod Security Admission · startup / liveness / readiness probes ·
requests vs limits, OOMKilled · rolling update (`maxSurge`/`maxUnavailable`), rollout history, rollback, drift ·
topology spread · Gateway API (GatewayClass/Gateway/HTTPRoute), NodePort, `externalTrafficPolicy` · Envoy panic
mode · DNS search list & `ndots` · metrics-server, HPA math & stabilization · Helm chart/values/release,
templates & helpers, hooks, `lookup`, checksum annotations, `helm test`, PodDisruptionBudget

**Real problems we found and fixed**
1. **Port 8080 already in use** by a Java program → kind's host port moved to 8090 (Step 3.2)
2. **ingress-nginx is retired** (March 2026) → Gateway API with Envoy Gateway instead of the classic Ingress (Step 3.7)
3. **`externalTrafficPolicy: Local`** default would have timed out every request → `Cluster` (Step 3.7)
4. **Readiness probe timed out** during a DB outage: the DNS search list made a failed lookup take 4.07 s →
   fully-qualified host with a trailing dot, 0.04 s (Experiment E)
5. **Envoy panic mode** sent traffic to not-ready pods → HTTP 500 → `panicThreshold: 0` → honest 503 (Experiment E)
6. **ConfigMap changes don't restart pods** → `kubectl rollout restart` by hand; `checksum/config` in Helm (Exp. E, Step 3.9)
7. **`rollout undo` drifts from the YAML files** (kubectl's own warning) → files re-applied; GitOps fixes it for good in Phase 6 (Exp. D, G)
8. **`replicas:` fights the HPA** → omitted in the Helm chart when autoscaling is on (Exp. G, Step 3.9)
9. Found for the **programmer side**, not fixed: the app answers 500 instead of 503 when the database fails mid-request (Exp. E)

**Redo-it-yourself checklist** (without looking at the steps)
1. Write a kind config with 1 control-plane + 2 workers and a port mapping; create the cluster; list the system pods and say what each does.
2. Create a namespace with the `restricted` pod-security label; a ConfigMap; a Secret **from a command**.
3. Run PostgreSQL as a StatefulSet with a PVC; prove the data survives deleting the pod.
4. Run migrations as a Job with an init container that waits for the database.
5. Deploy the API (2 replicas, 3 probes, requests/limits, non-root) + a Service; reach it with `port-forward`.
6. Install Envoy Gateway; create GatewayClass + Gateway + HTTPRoute; open `http://taskapi.localhost:8090/docs`.
7. Do a rolling update under load and count the status codes; deploy a broken tag and roll back.
8. Scale the database to 0: explain *why* the API pods are not ready but not restarted.
9. Install metrics-server, create an HPA, generate load, watch it scale up and back down.
10. Install the Helm chart as dev and prod; upgrade, check `helm history`, roll back; run `helm test`.

**Clean up / start again**

```bash
kind delete cluster --name devops-lab        # removes the 3 node containers and everything inside
bash scripts/k8s-up.sh prod                  # rebuild everything (cluster + platform + dev + prod) in ~3 min
docker compose start                         # Phase 1 stack back on http://localhost:8000 (when needed)
```

**Next → Phase 4: Terraform.** Today the cluster, Envoy Gateway, metrics-server and the namespaces were created
with commands typed (or chained in a script). In Phase 4 we describe all of it **as code** with Terraform: the kind
cluster, the Helm releases and the platform objects, with `terraform plan` showing every change before it happens,
the same workflow we'll later use to build AKS on Azure.
