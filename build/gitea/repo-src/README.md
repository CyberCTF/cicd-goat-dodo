# dodo

Terraform for Wonderland's **dodo** object store — a single, private S3 bucket where the Dodo keeps
the trophies from the Caucus-race ("everybody has won, and all must have prizes").

```bash
terraform init
terraform plan
terraform apply
```

## CI

Wonderland's Jenkins deploys this module. Before every deploy it runs a security scan
([Checkov](https://www.checkov.io/)) as a **gate**: the pipeline refuses to deploy a bucket that is
publicly readable, so `dodo` stays private. The scan honours a repository-local `.checkov.yaml`
configuration file when one is present.
