# Upstream

This lab reproduces one challenge — **Dodo** — from CI/CD Goat.

| What | Source | Licence |
| --- | --- | --- |
| The "Dodo" challenge (bypassing a CI security-scan deploy gate by overriding the scanner's configuration from the repository) | [CI/CD Goat](https://github.com/cider-security-research/cicd-goat) by Cider Security (now Palo Alto Networks), v1.2.7 | Apache-2.0 |
| Security class | [OWASP CICD-SEC-1: Insufficient Flow Control Mechanisms](https://owasp.org/www-project-top-10-ci-cd-security-risks/CICD-SEC-01-Insufficient-Flow-Control-Mechanisms) | — |
| Scanner | [Checkov](https://www.checkov.io/) by Prisma Cloud / Bridgecrew, pinned at 3.3.29 | Apache-2.0 |

Only the *vulnerability* is reproduced, not upstream's eight-machine CI/CD stack. The lab is two
machines — a Jenkins controller and a Gitea git host — which is the minimum this attack needs: a
pipeline that scans-then-deploys a repository on push, with the scan gate configurable from the repo.

Nothing is vendored from upstream. Upstream serves a large third-party project's source as the
`dodo` repository, bakes one fixed base64 flag into a Jenkins folder credential, and runs the real
cloud deploy against a LocalStack machine. This lab instead ships an **original**, minimal Terraform
module (`build/gitea/repo-src/`, authored here, no third-party code) with an original, fixed deploy
pipeline, and injects a **per-player** flag into the Jenkins credential store at run time, so each
player exfiltrates their own flag and nothing but the challenge idea comes from upstream.

The intended attack is identical to upstream's solution: set the dodo bucket's ACL to `public-read`
in `main.tf`, add a repository-local `.checkov.yaml`

```yaml
soft-fail: true
check:
  - MY_CHECK
```

so the scanner passes the public bucket, push, and read the flag from the build console. Checkov
really runs and really auto-loads that file, so the bypass is genuine, not simulated.

## Deviation 1 — the deploy (no cloud)

Upstream runs `terraform apply` against a LocalStack machine and then queries the live S3 bucket's
ACL (`awslocal s3api get-bucket-acl`) to decide whether to print the flag. This two-machine lab has
no cloud, so the gated deploy step reads the deployed bucket's publicness from the applied IaC
(`main.tf`) instead of from a live ACL query. The security gate — the actual subject of the
challenge — is **unchanged and real**: Checkov runs against the Terraform exactly as upstream does,
and the `.checkov.yaml` override is what lets a public bucket through. Only the post-gate "is the
deployed bucket public?" confirmation is read from the IaC rather than from a running S3 endpoint;
the outcome is the same (a public bucket was deployed, so the token is released).

## Deviation 2 — the trigger

Upstream relies on its global Gitea↔Jenkins webhook wiring to run the pipeline on push. This lab
uses the Jenkins **git** plugin's SCM polling (`pollSCM`, about once a minute) on the fixed pipeline
job — no inbound webhook, no Gitea plugin — which drops a Jenkins↔Gitea plugin version dependency
for a version-robust git poll that matters for a lab family meant to run unattended. The attack and
the player's steps are unchanged: push the malicious change to `main` and the pipeline runs on its
own. (The automated solver additionally nudges an immediate build so the self-check is deterministic.)

## A note on masking (the exfiltration encoding)

Upstream stores the flag base64-encoded in the credential and prints `echo $FLAG | base64 -d`,
relying on base64-decode producing a value the masker does not hold. On the modern Jenkins this lab
ships, the `credentials-binding` plugin masks a bound secret's raw value **and its plain base64**, so
the lab stores the **raw** flag and the deploy reverses it before base64-encoding
(`echo $flag | rev | base64`) — a transform the masker does not precompute. Recover it with
`base64 -d | rev`. The vulnerability is identical; only the encoding is updated to one current
masking does not catch. This is arguably a truer lesson for current CI: masking is a best-effort
guardrail, not a control, and a chosen transform defeats it.

## The crux: a fixed pipeline, a repo-configurable gate

The one structural point that makes this *flow control* rather than pipeline poisoning: the pipeline
is defined **in Jenkins** (`build/jenkins/casc/jobdsl/dodo.groovy`), not in a Jenkinsfile the
attacker controls. The attacker cannot change what the pipeline does — they can only change the
repository the pipeline scans and deploys. The sole control standing between a malicious change and
production is the security scan, and that scan reads its configuration from the attacker-controlled
repository, so it can be switched off from inside. That is CICD-SEC-1.
