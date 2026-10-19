#!/bin/sh
# dodo-deploy: the gated deploy step of Wonderland's pipeline. It runs ONLY after the Security Scan
# stage (Checkov) has passed — i.e. once the bucket was approved for deployment, legitimately or not.
#
# It "deploys" the Terraform and then publishes Wonderland's release token ($flag, the Global-scope
# credential the pipeline bound) — but only when the deployed dodo bucket is actually publicly
# readable. On the two-machine lab there is no cloud, so publicness is read from the deployed IaC
# rather than from a live S3 ACL query; the outcome is the same: a public bucket got deployed.
#
# The token is NOT printed in plaintext: Jenkins' credential masker hides a bound secret's raw value
# AND its plain base64, so the token is reversed before being base64-encoded — a transform the
# masker does not precompute. Recover it with `base64 -d | rev`.
set -eu

if grep -Eq 'acl[[:space:]]*=[[:space:]]*"(public-read|public-read-write|authenticated-read)"' main.tf; then
  echo "deploy: dodo bucket ACL is PUBLIC — terraform apply, publishing release token"
  printf '%s\n' "$flag" | rev | base64
  echo "deploy: done"
else
  echo "deploy: dodo bucket is private — terraform apply, nothing public to publish"
fi
