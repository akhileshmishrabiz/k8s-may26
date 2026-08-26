#!/usr/bin/env bash
# Install Docker, Compose, and kernel settings SonarQube needs on EC2.
# Usage (from this directory, on the EC2 box):
#   sudo bash install.sh
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo bash install.sh"
  exit 1
fi

REAL_USER="${SUDO_USER:-${USER}}"
OS_ID="$(. /etc/os-release && echo "${ID}")"
OS_LIKE="$(. /etc/os-release && echo "${ID_LIKE:-}")"

echo "==> Detected OS: ${OS_ID}"

install_docker_amazon() {
  dnf install -y docker curl unzip --skip-broken
  # Compose plugin: Amazon Linux 2023 ships it as a separate package when available.
  if dnf list --available docker-compose-plugin >/dev/null 2>&1; then
    dnf install -y docker-compose-plugin
  elif ! command -v docker-compose >/dev/null 2>&1 && ! docker compose version >/dev/null 2>&1; then
    echo "==> Installing Docker Compose v2 plugin from GitHub"
    mkdir -p /usr/local/lib/docker/cli-plugins
    curl -fsSL "https://github.com/docker/compose/releases/download/v2.32.4/docker-compose-linux-x86_64" \
      -o /usr/local/lib/docker/cli-plugins/docker-compose
    chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
    mkdir -p /usr/libexec/docker/cli-plugins
    ln -sfn /usr/local/lib/docker/cli-plugins/docker-compose \
      /usr/libexec/docker/cli-plugins/docker-compose
  fi
}

install_docker_debian() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y ca-certificates curl gnupg git unzip
  install -m 0755 -d /etc/apt/keyrings
  if [[ ! -f /etc/apt/keyrings/docker.asc ]]; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
  fi
  CODENAME="$(. /etc/os-release && echo "${VERSION_CODENAME}")"
  if [[ "${OS_ID}" == "debian" ]]; then
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian ${CODENAME} stable" \
      > /etc/apt/sources.list.d/docker.list
  else
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${CODENAME} stable" \
      > /etc/apt/sources.list.d/docker.list
  fi
  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

echo "==> Installing Docker and Compose"

if [[ "${OS_ID}" == "amzn" ]] || [[ "${OS_ID}" == "rhel" ]] || [[ "${OS_ID}" == "centos" ]] || [[ "${OS_LIKE}" == *"rhel"* && "${OS_ID}" != "ubuntu" ]]; then
  if command -v dnf >/dev/null 2>&1; then
    install_docker_amazon
  else
    echo "This Amazon/RHEL-like image needs dnf. Install Docker manually and re-run."
    exit 1
  fi
elif [[ "${OS_ID}" == "ubuntu" ]] || [[ "${OS_ID}" == "debian" ]] || [[ "${OS_LIKE}" == *"debian"* ]]; then
  install_docker_debian
else
  echo "Unsupported OS '${OS_ID}'. Install Docker + Compose yourself, then re-run for sysctl."
  exit 1
fi

echo "==> Enabling Docker"
systemctl enable --now docker
usermod -aG docker "${REAL_USER}"

echo "==> Kernel settings for Elasticsearch (SonarQube)"
cat >/etc/sysctl.d/99-sonarqube.conf <<'EOF'
vm.max_map_count=262144
fs.file-max=131072
vm.swappiness=1
EOF
sysctl --system >/dev/null

# SonarQube + Postgres need ~3–4 GB. Add swap on small instances so the JVM can start.
MEM_KB="$(awk '/MemTotal/ {print $2}' /proc/meminfo)"
if [[ "${MEM_KB}" -lt 7000000 ]] && [[ ! -f /swapfile ]]; then
  echo "==> RAM is under 7 GB — creating a 4G swapfile"
  fallocate -l 4G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=4096
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  if ! grep -q '^/swapfile ' /etc/fstab; then
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
  fi
fi

# File descriptor limits used by the SonarQube container
if ! grep -q 'sonarqube nofile' /etc/security/limits.conf; then
  cat >>/etc/security/limits.conf <<'EOF'
* soft nofile 65536
* hard nofile 65536
* soft nproc 4096
* hard nproc 4096
EOF
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ ! -f "${SCRIPT_DIR}/.env" ]] && [[ -f "${SCRIPT_DIR}/.env.example" ]]; then
  cp "${SCRIPT_DIR}/.env.example" "${SCRIPT_DIR}/.env"
  echo "==> Created .env from .env.example (change SONAR_JDBC_PASSWORD before production use)"
fi

echo
echo "============================================================"
echo "Deps are ready."
echo
echo "1. Start a new SSH session (or run: newgrp docker)"
echo "   so your user can talk to the Docker socket."
echo "2. From this directory:"
echo "     docker compose up -d"
echo "3. Wait until SonarQube is UP (1–3 minutes):"
echo "     curl -s http://127.0.0.1:9000/api/system/status"
echo "4. Open http://<EC2_PUBLIC_IP>:9000"
echo "   first login: admin / admin  (you will be forced to change it)"
echo "============================================================"
