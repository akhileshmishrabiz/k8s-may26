# Exercise: scan the Flask portal with SonarQube

App code: `devsecops/src` (LivingDevOps student portal — Flask, pytest, Python 3.13).

You already have SonarQube running on EC2 (`README.md`). This lab walks through creating a project, scanning that app, reading the report, and running the same scan from GitHub Actions.

---

## 0. What you should already have

- SonarQube UI at `http://<EC2_PUBLIC_IP>:9000`
- You logged in as `admin` and changed the default password
- This repo cloned (on the EC2 box, your laptop, or both)

Project key in `devsecops/src/sonar-project.properties` is **`student-portal`**. The token you create must be used with that key.

---

## 1. Create the project and an analysis token

In the SonarQube UI:

1. **Projects → Create Project → Manually**
2. Project display name: `Student Portal`
3. Project key: `student-portal` (must match `sonar.projectKey`)
4. Main branch: `main`
5. Skip the tutorial if it offers one — we will scan from CLI / GitHub Actions

Create a token:

1. Click your avatar → **My Account → Security**
2. Generate a token
   - Name: `ec2-lab` or `github-actions`
   - Type: **Global Analysis Token** (or Project Analysis Token scoped to `student-portal`)
   - Expiry: 30 days is enough for a lab
3. Copy it once. You cannot view it again.

Do not commit the token. You will pass it as `SONAR_TOKEN`.

---

## 2. How this app is wired for Sonar

File: `devsecops/src/sonar-project.properties`

| Property | Value | Meaning |
|----------|--------|---------|
| `sonar.projectKey` | `student-portal` | Must match the project you created |
| `sonar.sources` | `app` | Application package (routes, models, seed) |
| `sonar.tests` | `tests` | `test_app.py`, `test_smoke.py` |
| `sonar.exclusions` | `__pycache__`, `static`, `templates` | Skip generated / HTML / CSS |
| `sonar.python.version` | `3.13` | Matches `Dockerfile` and CI |
| `sonar.python.coverage.reportPaths` | `coverage.xml` | Cobertura XML from `pytest-cov` |

Host URL and token are **not** in that file. Pass them at scan time so they stay off git.

```bash
export SONAR_HOST_URL="http://<EC2_PUBLIC_IP>:9000"
export SONAR_TOKEN="<paste-token>"
```

From the EC2 box itself you can use `http://127.0.0.1:9000`.

---

## 3. First scan from the command line

Work from the app root so paths in `sonar-project.properties` resolve.

```bash
cd /path/to/k8s-may26/devsecops/src

python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

export DB_LINK="sqlite:///:memory:"
pytest --cov=app --cov-report=xml --cov-report=term-missing
# writes coverage.xml next to sonar-project.properties
```

Scan with the official scanner image (no local `sonar-scanner` install):

```bash
docker run --rm \
  --network host \
  -e SONAR_HOST_URL="${SONAR_HOST_URL}" \
  -e SONAR_TOKEN="${SONAR_TOKEN}" \
  -v "$(pwd):/usr/src" \
  sonarsource/sonar-scanner-cli
```

If you scan from a laptop against the EC2 UI, drop `--network host` — `SONAR_HOST_URL` already points at the public IP.

Wait until the scanner prints **EXECUTION SUCCESS**. Then open:

`http://<EC2_PUBLIC_IP>:9000/dashboard?id=student-portal`

---

## 4. Read the dashboard (do this on the first scan)

Click through these tiles and write down what you see:

| Tile | What it means for this repo |
|------|-----------------------------|
| **Reliability / Bugs** | Logic issues Sonar thinks can fail at runtime |
| **Security / Vulnerabilities** | Auth, injection, hardcoded secrets |
| **Security Hotspots** | Things a human must review (crypto, redirects) |
| **Maintainability / Code smells** | Duplication, complexity, unused code |
| **Coverage** | Lines in `app/` hit by `tests/` (from `coverage.xml`) |
| **Duplications** | Repeated blocks across routes / helpers |

Open **Issues** and filter by file. Useful starting files in this app:

- `app/__init__.py` — default `SECRET_KEY` when the env var is missing
- `data/admins.json` — seed admin passwords in source (lab-only)
- `app/routes/helpers.py` — `safe_next_url` (open-redirect hotspot if the check is incomplete)
- `app/routes/auth.py` — login / register validation
- `app/seed.py` — password resolution from JSON vs env

**Security Hotspots:** open each one, mark **Safe** or **Fixed** after you read the code. That is part of the exercise — do not blindly accept them.

---

## 5. Hands-on: make a finding appear, then clear it

Keep the scanner command from section 3. After each change, re-run pytest + scanner and refresh the dashboard.

### 5a. Introduce a smell Sonar will flag

In `devsecops/src/app/routes/helpers.py`, temporarily add:

```python
def unused_debug_helper(user_input):
    password = "ChangeMe123"  # sonar will flag this
    return eval(user_input)   # and this
```

Scan again. You should see:

- a **security hotspot / vulnerability** on `eval`
- a **hard-coded credential** on the password string

### 5b. Remove it and confirm the issue closes

Delete that function. Scan again. The new issues should move to **Closed** (or disappear from the open list) on the next analysis.

### 5c. Coverage (optional)

`pytest --cov=app` already covers auth, retros, teams, and tickets. Open **Coverage** on a file you did not touch (for example `app/routes/games.py` or `app/routes/wheel.py`). If coverage is low, that is expected — add one test in `tests/` only if you want to watch the percentage move.

---

## 6. Quality gate

**Administration → Quality Profiles / Quality Gates** (or project **Quality Gate**).

Default gate **Sonar way** typically requires:

- no new bugs
- no new vulnerabilities
- coverage / duplication conditions on **new code**

After your second scan, check whether the project is **Passed** or **Failed**. If it failed, the dashboard tells you which condition broke (often a new issue from 5a).

The GitHub Action in section 7 waits on this gate and fails the workflow when Sonar reports **ERROR**.

---

## 7. GitHub Action scan

Workflow file (repo root):

`.github/workflows/devsecops-sonarqube.yaml`

It:

1. fails fast if `SONAR_TOKEN` / `SONAR_HOST_URL` are missing, and curls `/api/system/status`
2. checks out the repo (`fetch-depth: 0` so blame / new-code works)
3. installs Python 3.13 and `devsecops/src` deps
4. runs `pytest --cov=app --cov-report=xml`
5. runs `SonarSource/sonarqube-scan-action` against `devsecops/src`
6. waits on the quality gate

### GitHub settings (Settings → Secrets and variables → Actions)

| Kind | Name | Example | Notes |
|------|------|---------|--------|
| **Secret** | `SONAR_TOKEN` | `squ_...` | token from section 1 |
| **Variable** (preferred) | `SONAR_HOST_URL` | `http://3.110.x.x:9000` | no trailing slash; a secret with the same name also works |

GitHub-hosted runners are on the public internet. Your EC2 security group must allow **inbound TCP 9000** from `0.0.0.0/0` for this lab (or from GitHub’s IP ranges if you want to lock it down).

The job will fail immediately if either value is missing or if it cannot reach SonarQube — fix that before looking at pytest or the scanner.

HTTP is fine for a short-lived lab. Do not put a real production token on a plaintext `http://` host.

### Run it

1. Push the workflow (and any app changes) to GitHub
2. **Actions → DevSecOps SonarQube → Run workflow**
3. When it finishes, refresh `http://<EC2_PUBLIC_IP>:9000/dashboard?id=student-portal`

To also run on push / PR, uncomment those blocks at the top of the workflow.

---

## 8. Checklist

- [ ] EC2 SonarQube is `UP` (`curl` `/api/system/status`)
- [ ] Project key `student-portal` exists
- [ ] Token stored only in env / GitHub secrets
- [ ] Local pytest wrote `coverage.xml`
- [ ] First CLI scan shows Coverage + Issues on the dashboard
- [ ] You opened at least one Security Hotspot in this app
- [ ] You added and removed the `eval` helper and saw issues open/close
- [ ] GitHub Action completed and the quality gate step passed (or failed for a reason you can explain)

---

## Troubleshooting

| Problem | What to check |
|---------|----------------|
| `Not authorized` / 401 | token revoked or wrong; create a new analysis token |
| Project not found | key is not `student-portal`, or token cannot see the project |
| Coverage is 0% | `coverage.xml` missing; run pytest from `devsecops/src`; property path is `coverage.xml` |
| Scanner cannot connect | `SONAR_HOST_URL`, security group 9000, Sonar still `STARTING` |
| Action times out on quality gate | first analysis is slow on t3.medium; wait and re-run |
| `report-task.txt` not found | scanner must finish successfully; file is `devsecops/src/.scannerwork/report-task.txt` |
