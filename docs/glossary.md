# Glossary

Every technical term used in this project, in plain English, with where it first appears.
Also: **HB** = [github-handbook](github-handbook.md).
Phases: **P0** = [00-setup](00-setup.md) · **P1** = [01-app-docker](01-app-docker.md) · **P2** = [02-ci](02-ci.md) · **Git** = [git-github-basics](git-github-basics.md).
Updated every phase.

---

## A–C

| Term | Plain-English meaning | Where |
|---|---|---|
| **Action** (GitHub) | A reusable building block for workflows, e.g. `actions/checkout` | P2 2.1 |
| **actionlint** | A linter that checks GitHub Actions workflow files for mistakes | P2 2.7 |
| **Alembic** | Tool that applies versioned database changes (migrations) | P1 1.4 |
| **Annotation** | A CI message attached to a specific file and line, shown on the PR | P2 2.14 |
| **apt** | Ubuntu/Debian's package installer (`apt-get install …`) | P0 0.4, P1 1.8 |
| **Artifact** (Phase 3+) | A file produced by a build, kept for later | — |
| **Base image** | The image a Dockerfile starts `FROM` (ours: `python:3.13-slim`) | P1 1.8 |
| **Bound parameter** | Sending a value to the database separately from the SQL text, so it can't be run as SQL | P2 2.12 |
| **Branch** | A movable label for a line of work in Git; `main` is the main line | Git §4 |
| **Branch protection / Ruleset** | GitHub rules that block direct pushes and require green checks before merging | P2 2.11 |
| **Build cache** | Docker re-uses unchanged layers instead of rebuilding them | P1 1.7–1.9 |
| **Build context** | The folder sent to Docker when building (`.` in `docker build .`) | P1 1.8 |
| **Checksum** (SHA-256) | A fingerprint of a file; if it matches the publisher's, the file is genuine | P0 0.4 |
| **CI** (Continuous Integration) | Automatically lint, test and build every change | P2 2.1 |
| **CNI** | Kubernetes networking plugin; gives every pod an IP address | P0 0.6 |
| **CodeQL** | GitHub's code analyzer that finds security bugs by following data flow | P2 2.8 |
| **Commit** | A saved snapshot of the project in Git, with an ID (SHA) | Git §3 |
| **Compose** (Docker Compose) | Runs several containers together from one `compose.yaml` | P1 1.10 |
| **Concurrency** (Actions) | Setting that cancels an outdated pipeline run when a newer push arrives | P2 2.7 |
| **Conflict** (merge conflict) | Two branches changed the same lines; a human must choose | Git §9 |
| **Container** | A running instance of an image: an isolated process with its own filesystem | P1 |
| **Context** (kubeconfig) | A named "which cluster + which user" pair that `kubectl` talks to | P0 0.6 |
| **Control plane** | The "brain" of Kubernetes: API server, scheduler, etcd, controllers | P0 0.6 |
| **CVE** | A public ID for a known security vulnerability | P2 2.5 |

## D–H

| Term | Plain-English meaning | Where |
|---|---|---|
| **Dependabot** | GitHub bot that opens PRs to update dependencies | P2 2.8 |
| **Dependency** | A library your code uses (e.g. FastAPI) | P1 1.5 |
| **Digest** (`@sha256:…`) | The content hash of an image; unlike a tag, it can never point to something else | P2 2.6 |
| **Docker Desktop** | Windows/Mac app that runs the Docker engine inside a small Linux VM (WSL2) | P0 0.2 |
| **`.dockerignore`** | Files never sent to Docker builds (e.g. `.env`) | P1 1.8 |
| **Dockerfile** | Recipe to build an image, one instruction per line | P1 1.7 |
| **`.env` / `.env.example`** | Local secrets file (never committed) / its committed template | P1 1.10 |
| **Environment variable** | A named setting passed to a process from outside (`APP_DATABASE_URL`) | P1 1.1 |
| **Exec form vs shell form** | `CMD ["uvicorn", …]` (app is PID 1, gets signals) vs `CMD uvicorn …` (runs via `sh`) | P1 1.7 |
| **Exit code** | Number a command returns: `0` = success, anything else = failure. CI uses it to decide ✅/❌ | P1, P2 |
| **Fail fast** | Run cheap checks first and stop early on failure | P2 2.7 |
| **Bisect** (`git bisect`) | Binary search through commits to find the one that broke something | HB 2.9 |
| **Blame** (`git blame`) | Shows who last changed each line of a file | HB 2.9 |
| **CODEOWNERS** | File that auto-assigns required reviewers per folder | HB D8 |
| **Environment** (GitHub) | Named deploy target (dev/prod) with approvals and its own secrets | HB D9 |
| **Fast-forward** | Updating a branch by just moving its label forward (no merge needed) | Git §7 |
| **Fixture** (pytest) | Reusable setup/cleanup code for tests | P1 1.6 |
| **Fetch** vs **Pull** | fetch = download news only; pull = fetch + update your branch and files | HB 2.2 |
| **Force-with-lease** | A safer force push: refuses if someone else pushed meanwhile | HB P3 |
| **Formatter** | Tool that rewrites code layout consistently (`ruff format`) | P2 2.2 |
| **gitleaks** | Scanner that finds secrets (passwords, keys) in Git history | P2 2.4 |
| **`.gitattributes`** | Tells Git how to treat files; ours forces Linux (LF) line endings | P0 0.5, P1 |
| **`.gitignore`** | Files Git must never track | P0 0.5 |
| **GHCR** | GitHub Container Registry, where our images are published | P2 2.10 |
| **`GITHUB_TOKEN`** | Automatic, short-lived token GitHub gives each workflow run | P2 2.7 |
| **hadolint** | Linter for Dockerfiles | P2 2.3 |
| **HEAD** (Git) | "Where I am now": the current branch/commit | Git §4 |
| **Health check** | A periodic test that a container is working (`/health`) | P1 1.8 |
| **Helm** | Package manager for Kubernetes (Phase 3) | P0 0.4 |
| **Hyper-V** | Windows' built-in virtualization; minikube's old VM used it | P0 0.2c |

## I–N

| Term | Plain-English meaning | Where |
|---|---|---|
| **Idempotent** | Running it twice gives the same result as once (safe to re-run) | P0 0.4 |
| **Image** (container image) | A packaged, read-only filesystem + start command; containers are created from it | P1 |
| **Integration test** | A test of several real pieces together (API + real database) | P1 1.6 |
| **kind** | Tool that creates Kubernetes clusters where each node is a Docker container | P0 0.6 |
| **kubectl** | The command-line "remote control" for Kubernetes | P0 0.4 |
| **Layer** (image layer) | Each Dockerfile instruction produces a cached layer | P1 1.7 |
| **Least privilege** | Give every component only the permissions it needs | P2 2.7 |
| **Linter** | Tool that finds bugs and bad patterns without running code (`ruff check`) | P2 2.2 |
| **Liveness probe** (`/health`) | "Is the process alive?" Failure → restart | P1 1.3 |
| **Lock file** (`requirements.txt`) | Exact versions of every dependency, so installs are reproducible | P1 1.5 |
| **Merge** | Combining a branch's changes into another branch | Git §7 |
| **Migration** | A versioned script that changes the database schema | P1 1.4 |
| **Mocking / monkeypatch** | Replacing a real function with a fake one in a test | P1 1.6 |
| **Multi-stage build** | Dockerfile with several `FROM` stages; the final image copies only what it needs | P1 1.8 |
| **Named volume** | Docker-managed storage that survives container removal (`db-data`) | P1 1.14 |
| **Node** (Kubernetes) | A machine (VM, or a container in kind) that runs pods | P0 0.6 |
| **Non-root user** | Running the app as an unprivileged user (UID 10001), not as root | P1 1.8 |

## O–R

| Term | Plain-English meaning | Where |
|---|---|---|
| **ORM** | Library that maps database tables to code classes (SQLAlchemy) | P1 1.3 |
| **`origin`** | Conventional name for the GitHub copy of your repo | Git §5 |
| **PID 1** | The first process in a container; receives stop signals | P1 1.7 |
| **Pinning** | Fixing an exact version/digest/SHA instead of "latest" | P0 0.4, P2 2.6 |
| **Pod** | The smallest unit Kubernetes runs: one or more containers | P0 0.6 |
| **PPA** | Extra Ubuntu package source (we used Ansible's official PPA) | P0 0.4 |
| **Profile** (Compose) | A group of services only started when asked (`tests`, `test-db`) | P1 1.10 |
| **Prune** (Docker) | Delete unused containers/images/cache | P0 0.2b |
| **Pull request (PR)** | A GitHub request to merge a branch, with review + CI checks | Git §6, P2 2.13 |
| **Push / pull / fetch** | Upload commits / download + update / download only | Git §5 |
| **Rebase** | Replay your commits on top of another branch (straight history) | HB 2.3, 2.5 |
| **Release** (GitHub) | A version (tag) with notes and downloads | HB D4 |
| **Revert** | A new commit that undoes an earlier one (safe for pushed commits) | HB 2.6 |
| **Readiness probe** (`/ready`) | "Can it serve traffic now?" Failure → no traffic, no restart | P1 1.3 |
| **Registry** | A server that stores images (Docker Hub, GHCR) | P2 |
| **Regression test** | A test that ensures a fixed bug never comes back | P2 2.12 |
| **Repository (repo)** | A project tracked by Git (locally and on GitHub) | Git §1 |
| **ruff** | Fast Python linter + formatter | P2 2.2 |
| **Runner** | The fresh VM GitHub lends to run a CI job | P2 2.1 |

## S–Z

| Term | Plain-English meaning | Where |
|---|---|---|
| **SARIF** | Standard file format for scanner results; GitHub shows it in the Security tab | P2 2.7 |
| **SAST** | Static Application Security Testing: analyzing code without running it (CodeQL) | P2 2.8 |
| **Script injection** (Actions) | Attacker-controlled text (e.g. a branch name) executed inside a workflow script | P2 2.7 |
| **Secret scanning** | Searching code/history for leaked passwords and keys | P2 2.4 |
| **Service container** (Actions) | A container running next to a CI job (our PostgreSQL) | P2 2.7 |
| **Severity** | How bad a vulnerability is: LOW / MEDIUM / HIGH / CRITICAL | P2 2.5 |
| **SHA** (commit SHA) | A commit's unique ID, e.g. `2c0c748` | Git §3 |
| **Smoke test** | A quick check that the basics work | P0 0.6 |
| **SQL injection** | User input interpreted as SQL commands, letting attackers read or change data | P2 2.12 |
| **Stash** | Temporarily park uncommitted work | HB 2.7 |
| **Squash and merge** | Combine all branch commits into one commit on `main` | Git §7 |
| **Staging area** | Git's "basket" of changes for the next commit (`git add`) | Git §2 |
| **Status check** | A CI result (✅/❌) attached to a commit; rulesets can require them | P2 2.11 |
| **Supply-chain attack** | Compromising a dependency/tool you use, instead of you directly | P2 2.6 |
| **Tag** (Git tag) | A permanent name on a commit, e.g. `v1.0.0` | HB 2.8 |
| **Tag** (image tag) | A human name for an image version (`:main`, `:sha-2c0c748`); can be moved | P2 2.6 |
| **Terraform** | Tool that creates infrastructure from code files (Phase 4) | P0 0.4 |
| **tmpfs** | Storage in RAM; fast and wiped on stop (our `test-db`) | P1 1.13 |
| **Trivy** | Vulnerability scanner for dependencies and images | P2 2.5 |
| **Trunk-based / GitHub Flow / Git Flow** | Team branching strategies | HB Part 4 |
| **12-factor app** | A checklist for cloud-friendly apps (config in env vars, logs to stdout…) | P1 1.1 |
| **Unit test** | A fast test of one piece of logic in isolation (no database) | P1 1.6 |
| **Vendored dependency** | A library copied *inside* another package (pip ships its own urllib3) | P2 2.5 |
| **Virtualenv (venv)** | An isolated folder of Python packages | P1 1.8 |
| **`.vhdx`** | A virtual hard disk file (Docker Desktop and WSL store data in one) | P0 0.2 |
| **Workflow** (Actions) | A YAML file in `.github/workflows/` describing a pipeline | P2 2.1 |
| **WSL2** | Windows Subsystem for Linux: a real Linux (Ubuntu) inside Windows | P0 0.3 |
