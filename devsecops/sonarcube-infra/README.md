# SonarQube on EC2 (Docker Compose)

Self-hosted SonarQube Community for the Flask app in `devsecops/src`.

After the box is up you: install git → clone this repo → run `install.sh` → `docker compose up -d`.

Lab walkthrough (create a project, scan the app, read findings, GitHub Action): see [exercise.md](./exercise.md).

---

## 1. Launch the EC2 instance

| Setting | Value |
|---------|--------|
| AMI | Amazon Linux 2023 **or** Ubuntu 22.04 / 24.04 |
| Instance type | **t3.medium** (4 GB) works with swap. **t3.large** (8 GB) is more comfortable |
| Storage | **20 GB** gp3 (images + Postgres + Elasticsearch) |
| Key pair | one you can SSH with |
| Public IP | required if you will open the UI from your laptop or scan from GitHub Actions |

**Security group inbound**

| Port | Source | Why |
|------|--------|-----|
| 22 | your IP `/32` | SSH |
| 9000 | your IP `/32` | SonarQube UI + local scanner |
| 9000 | `0.0.0.0/0` | only if GitHub-hosted runners must reach this server (lab only) |

Do not open Postgres (`5432`) to the internet. Compose keeps it on the internal Docker network.

---

## 2. SSH in, install git, clone

**Amazon Linux 2023**

```bash
ssh -i your-key.pem ec2-user@<EC2_PUBLIC_IP>
sudo dnf install -y git
```

**Ubuntu**

```bash
ssh -i your-key.pem ubuntu@<EC2_PUBLIC_IP>
sudo apt-get update && sudo apt-get install -y git
```

Clone (use your fork URL if that is what you work from):

```bash
git clone https://github.com/<you>/k8s-may26.git
cd k8s-may26/devsecops/sonarcube-infra
```

---

## 3. One-shot deps: `install.sh`

```bash
sudo bash install.sh
```

The script:

- installs Docker Engine and the Compose v2 plugin
- starts and enables `docker`
- adds your SSH user to the `docker` group
- sets `vm.max_map_count=262144` (required by Elasticsearch inside SonarQube)
- adds a 4 GB swapfile when RAM is under 7 GB so a t3.medium can start
- copies `.env.example` → `.env` if `.env` is missing

**New SSH session** (or `newgrp docker`) so the group change applies:

```bash
exit
# ssh back in
cd k8s-may26/devsecops/sonarcube-infra
docker version
docker compose version
```

---

## 4. Start SonarQube

```bash
docker compose up -d
docker compose ps
```

First boot pulls images and runs DB migrations. Wait until the API says `UP` (often 1–3 minutes):

```bash
curl -s http://127.0.0.1:9000/api/system/status
# {"id":"...","version":"...","status":"UP"}
```

If it is still `STARTING`, watch logs:

```bash
docker compose logs -f sonarqube
```

Open `http://<EC2_PUBLIC_IP>:9000`.

| First login | Value |
|-------------|--------|
| user | `admin` |
| password | `admin` |

SonarQube forces a password change on first login. Store the new password; you will need it to create a token in [exercise.md](./exercise.md).

---

## 5. Useful commands

```bash
docker compose ps
docker compose logs -f sonarqube
docker compose restart sonarqube
docker compose down          # stop, keep volumes
docker compose down -v       # wipe DB + analysis history
```

---

## 6. If SonarQube will not start

| Symptom | Fix |
|---------|-----|
| `max virtual memory areas vm.max_map_count [65530] is too low` | `sudo sysctl -w vm.max_map_count=262144` then `docker compose restart sonarqube` |
| container killed / OOM | use t3.large, or confirm `/swapfile` exists (`swapon --show`) |
| `permission denied` talking to Docker | new SSH session after `install.sh`, or `sudo usermod -aG docker $USER` |
| UI not reachable | security group port 9000, and `curl` locally first |
| GitHub Action cannot reach host | port 9000 open to the internet (lab) or a reachable URL in `SONAR_HOST_URL` |

---

## What this folder is

| File | Role |
|------|------|
| `install.sh` | EC2 deps + kernel + swap |
| `docker-compose.yml` | SonarQube Community + Postgres 16 |
| `.env.example` | DB password and port |
| `exercise.md` | scan `devsecops/src` and wire GitHub Actions |
| `.github/workflows/devsecops-sonarqube.yaml` | CI scan (repo root, not this folder) |
