Deploy the PA infrastructure using Terraform. Walks through init → plan → apply with explanations at each step.

All terraform commands use `-chdir=infra` so they run against the `infra/` directory from the repo root.

## 1. Pre-flight check

Verify `infra/terraform.tfvars` exists:
```
test -f infra/terraform.tfvars && echo "ok" || echo "missing"
```
If missing, tell the user to run `/install` first and stop.

## 2. terraform init

```
terraform -chdir=infra init
```

Print the output. If it fails, diagnose the error:
- Provider download issues: check internet connectivity
- Backend issues: verify `infra/` is writable

## 3. terraform plan

```
terraform -chdir=infra plan
```

Summarise what will be created/changed/destroyed in plain language. Call out anything destructive explicitly.

If plan fails with a 401 auth error, tell the user to refresh their OCI session:
```
! oci session authenticate --region il-jerusalem-1 --profile-name pa
```
Then retry.

## 4. Confirm with the user

Ask: "Does this plan look right? Type yes to apply, or describe what you'd like to change."

If the user wants changes, help them edit `infra/terraform.tfvars` or the relevant `infra/*.tf` file, then re-run plan.

## 5. terraform apply

Once confirmed:
```
terraform -chdir=infra apply -auto-approve
```

Stream output and report when complete. Print the final Terraform outputs.

## 6. Next steps

After a successful apply, print:
```
Deployment complete.

Your instance is live. Next steps:
  /setup-instance   — install Git and clone NanoClaw on the instance (do this first)
  /setup-sshm       — register the instance in ~/.ssh/config for sshm/ssh access
  /connect          — open a Bastion SSH session right now
```
