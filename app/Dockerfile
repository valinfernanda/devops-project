# syntax=docker/dockerfile:1
# =============================================================================
# Task API: production Dockerfile (multi-stage)
#
#   docker build -t taskapi:local .                 → final runtime image (default)
#   docker build -t taskapi:test --target test .    → image with tests + pytest
#
# Stages:
#   builder → installs runtime dependencies into a virtualenv (/opt/venv)
#   test    → builder + dev dependencies + tests        (used by CI, never shipped)
#   runtime → slim base + the venv + app code, non-root (what gets deployed)
# =============================================================================

# Base image pinned by DIGEST (@sha256:...), not just by tag. A tag like
# "3.13-slim" is re-pointed to a new image every few weeks; a digest always
# means the exact same bytes → reproducible builds. Dependabot proposes digest
# updates as pull requests, so we still get security fixes, but reviewed.
# Both stages must use the same base (same Python), so keep the two lines in sync.

# ----------------------------------------------------------------- builder ---
ARG PYTHON_BASE_IMAGE=python:3.13-slim@sha256:e48f59cdba69a3cbd9ed2cf0f348d90d45a8d350d98134cf1070bc106ee9ed90
FROM ${PYTHON_BASE_IMAGE} AS builder

ENV PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_ROOT_USER_ACTION=ignore

# A virtualenv keeps all installed packages in ONE folder we can copy later.
# --without-pip: the venv gets NO pip of its own. The app never needs pip at
# runtime, and pip vendors libraries (urllib3, msgpack...) that scanners flag.
# We install INTO the venv with the base image's pip instead (--python ...).
RUN python -m venv --without-pip /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Copy ONLY the lock file first. This layer is cached until requirements.txt
# changes, so editing app code does not reinstall every dependency.
COPY requirements.txt /tmp/requirements.txt
RUN /usr/local/bin/pip --python /opt/venv/bin/python install -r /tmp/requirements.txt

# -------------------------------------------------------------------- test ---
FROM builder AS test

COPY requirements-dev.txt /tmp/requirements-dev.txt
RUN /usr/local/bin/pip --python /opt/venv/bin/python install -r /tmp/requirements-dev.txt

WORKDIR /app
COPY . .
CMD ["pytest", "-v"]

# ----------------------------------------------------------------- runtime ---
FROM ${PYTHON_BASE_IMAGE} AS runtime

# PYTHONDONTWRITEBYTECODE: don't write .pyc files (read-only friendly)
# PYTHONUNBUFFERED: print logs immediately (no buffering), so `docker logs` is live
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/opt/venv/bin:$PATH"

# Docker CACHES this RUN layer: once built, "apt-get upgrade" is NOT run again on later
# builds (locally, and in CI via the GitHub Actions cache), so new Debian fixes never
# arrive. Changing this date changes the layer → cache miss → fresh security updates.
# Bump it whenever Trivy reports a fixable OS-package CVE (2026-11-25: libzstd1).
ARG SECURITY_UPDATES_DATE=2026-11-25

# 1) Security updates: install Debian fixes released after the base image was built
#    (Trivy found fixable HIGH CVEs in zlib1g, then libzstd1). Clean apt lists in the SAME layer.
# 2) Remove the base image's pip: not needed to run the app, and it carries
#    vendored libraries with known CVEs.
# 3) Dedicated unprivileged user. A fixed UID (10001) lets Kubernetes enforce
#    "runAsNonRoot" and makes file permissions predictable.
RUN echo "Debian security updates as of ${SECURITY_UPDATES_DATE}" \
 && apt-get update \
 && apt-get upgrade -y --no-install-recommends \
 && rm -rf /var/lib/apt/lists/* \
 && /usr/local/bin/python -m pip uninstall -y pip \
 && groupadd --system --gid 10001 app \
 && useradd --system --uid 10001 --gid app --no-create-home --shell /usr/sbin/nologin app

WORKDIR /app

# Only the installed packages from the builder; no pip cache, no build tools.
COPY --from=builder /opt/venv /opt/venv

# Only what the app needs at runtime. Files stay owned by root (read-only for
# the app user), so a compromised app cannot modify its own code.
COPY taskapi ./taskapi
COPY migrations ./migrations
COPY alembic.ini .

USER 10001
EXPOSE 8000

# Docker's own health check (Kubernetes uses its own probes instead, Phase 3).
# Uses Python's standard library because slim images have no curl.
HEALTHCHECK --interval=15s --timeout=3s --start-period=10s --retries=3 \
  CMD ["python", "-c", "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=2).status == 200 else 1)"]

# Exec form (JSON array): uvicorn runs as PID 1 and receives SIGTERM directly,
# so `docker stop` / Kubernetes can shut it down gracefull  y.
CMD ["uvicorn", "taskapi.main:app", "--host", "0.0.0.0", "--port", "8000"]
