#!/usr/bin/env bash
# =============================================================================
# Phase 0 / Step 0.4: Install the DevOps toolbox inside WSL Ubuntu 22.04
#
# Installs: kubectl, kind, Terraform, Helm, Ansible, k9s
#
# Usage (inside Ubuntu, from the project folder):
#   sudo bash scripts/00-install-tools.sh
#
# The script is IDEMPOTENT: running it again is safe. It simply re-installs or
# upgrades to the versions pinned below.
# =============================================================================

# --- Safety switches ---------------------------------------------------------
# -e          : stop immediately if any command fails
# -u          : treat use of an undefined variable as an error (catches typos)
# -o pipefail : a pipeline (a | b) fails if ANY part fails, not only the last
set -euo pipefail

# --- Pinned versions ---------------------------------------------------------
# Pinning = always installing a known version instead of "whatever is latest".
# This makes the setup reproducible: you get the same result next month.
KUBECTL_VERSION="v1.37.2"
KIND_VERSION="v0.33.0"
ARCH="amd64"

# A temporary folder for downloads, deleted automatically when the script exits
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

step() { printf '\n==> %s\n' "$*"; }

if [[ $EUID -ne 0 ]]; then
  echo "This script installs system-wide tools. Run it with: sudo bash $0" >&2
  exit 1
fi

# -----------------------------------------------------------------------------
step "1/7 Base packages (curl, gpg, unzip, ...)"
# -----------------------------------------------------------------------------
export DEBIAN_FRONTEND=noninteractive      # never stop to ask questions
apt-get update -y
apt-get install -y curl ca-certificates gnupg lsb-release unzip \
  software-properties-common git bash-completion

# -----------------------------------------------------------------------------
step "2/7 kubectl ${KUBECTL_VERSION} (Kubernetes command-line client)"
# -----------------------------------------------------------------------------
# Download the binary AND its official checksum, then verify they match.
# If the file was corrupted or tampered with, sha256sum --check fails and the
# script stops (thanks to set -e) before anything gets installed.
curl -fsSLo "$TMP/kubectl"        "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl"
curl -fsSLo "$TMP/kubectl.sha256" "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl.sha256"
echo "$(cat "$TMP/kubectl.sha256")  $TMP/kubectl" | sha256sum --check
install -o root -g root -m 0755 "$TMP/kubectl" /usr/local/bin/kubectl

# -----------------------------------------------------------------------------
step "3/7 kind ${KIND_VERSION} (Kubernetes IN Docker)"
# -----------------------------------------------------------------------------
KIND_URL="https://github.com/kubernetes-sigs/kind/releases/download/${KIND_VERSION}/kind-linux-${ARCH}"
curl -fsSLo "$TMP/kind-linux-${ARCH}"           "$KIND_URL"
curl -fsSLo "$TMP/kind-linux-${ARCH}.sha256sum" "${KIND_URL}.sha256sum"
( cd "$TMP" && sha256sum --check "kind-linux-${ARCH}.sha256sum" )
install -o root -g root -m 0755 "$TMP/kind-linux-${ARCH}" /usr/local/bin/kind

# -----------------------------------------------------------------------------
step "4/7 Terraform (from HashiCorp's official apt repository)"
# -----------------------------------------------------------------------------
# 1) Download HashiCorp's signing key: apt uses it to verify every package.
# 2) Register their repository, trusting ONLY that key for it (signed-by=...).
# 3) Install with apt, so future upgrades are just: sudo apt upgrade terraform
curl -fsSL https://apt.releases.hashicorp.com/gpg \
  | gpg --dearmor --yes -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
  > /etc/apt/sources.list.d/hashicorp.list
apt-get update -y
apt-get install -y terraform

# -----------------------------------------------------------------------------
step "5/7 Helm 4 (Kubernetes package manager, official install script)"
# -----------------------------------------------------------------------------
# USE_SUDO=false because we are already root.
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4 \
  | USE_SUDO=false bash

# -----------------------------------------------------------------------------
step "6/7 Ansible (from the official Ansible PPA)"
# -----------------------------------------------------------------------------
# Ubuntu 22.04's default Ansible is old; the PPA provides current releases.
add-apt-repository --yes --update ppa:ansible/ansible
apt-get install -y ansible

# -----------------------------------------------------------------------------
step "7/7 k9s (terminal UI for Kubernetes)"
# -----------------------------------------------------------------------------
curl -fsSLo "$TMP/k9s.tar.gz" \
  "https://github.com/derailed/k9s/releases/latest/download/k9s_Linux_${ARCH}.tar.gz"
tar -xzf "$TMP/k9s.tar.gz" -C "$TMP" k9s
install -o root -g root -m 0755 "$TMP/k9s" /usr/local/bin/k9s

# -----------------------------------------------------------------------------
step "Installed versions"
# -----------------------------------------------------------------------------
echo "kubectl  : $(kubectl version --client 2>/dev/null | head -1)"
echo "kind     : $(kind version)"
echo "terraform: $(terraform version | head -1)"
echo "helm     : $(helm version --short)"
echo "ansible  : $(ansible --version | head -1)"
echo "k9s      : $(k9s version --short 2>/dev/null | head -1)"
echo
echo "All tools installed."
