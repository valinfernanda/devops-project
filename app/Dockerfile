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

ARG PYTHON_VERSION=3.13

# ----------------------------------------------------------------- builder ---
FROM python:${PYTHON_VERSION}-slim AS builder

ENV PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_ROOT_USER_ACTION=ignore

# A virtualenv keeps all installed packages in ONE folder we can copy later.
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Copy ONLY the lock file first. This layer is cached until requirements.txt
# changes, so editing app code does not reinstall every dependency.
COPY requirements.txt /tmp/requirements.txt
RUN pip install -r /tmp/requirements.txt

# -------------------------------------------------------------------- test ---
FROM builder AS test

COPY requirements-dev.txt /tmp/requirements-dev.txt
RUN pip install -r /tmp/requirements-dev.txt

WORKDIR /app
COPY . .
CMD ["pytest", "-v"]

# ----------------------------------------------------------------- runtime ---
FROM python:${PYTHON_VERSION}-slim AS runtime

# PYTHONDONTWRITEBYTECODE: don't write .pyc files (read-only friendly)
# PYTHONUNBUFFERED: print logs immediately (no buffering), so `docker logs` is live
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/opt/venv/bin:$PATH"

# Dedicated unprivileged user. A fixed UID (10001) lets Kubernetes enforce
# "runAsNonRoot" and makes file permissions predictable.
RUN groupadd --system --gid 10001 app \
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
# so `docker stop` / Kubernetes can shut it down gracefully.
CMD ["uvicorn", "taskapi.main:app", "--host", "0.0.0.0", "--port", "8000"]
