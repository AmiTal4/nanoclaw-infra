Validate and install all prerequisites for the PA infrastructure repo. Walk the user through each step interactively, checking each tool before moving on.

Work through the following checks in order. For each one: check if it's already satisfied, report pass/fail clearly, and only prompt the user if action is needed.

---

## 1. Terraform

Run: `terraform --version`

- If found: print the version and continue.
- If not found: tell the user to install Terraform from https://developer.hashicorp.com/terraform/install and wait for them to confirm before continuing. After confirmation, re-check.

---

## 2. OCI CLI

Run: `oci --version`

- If found: print the version and continue.
- If not found: guide the user to install it:
  - macOS: `brew install oci-cli`
  - Linux: `pip3 install oci-cli`
  - Windows (Git Bash): `pip3 install oci-cli` or use the Windows installer from https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm
  After installation, re-check.

---

## 3. SSH key pair

Check whether `~/.ssh/id_rsa` and `~/.ssh/id_rsa.pub` exist:
```
test -f "$HOME/.ssh/id_rsa" && echo "private: ok" || echo "private: missing"
test -f "$HOME/.ssh/id_rsa.pub" && echo "public: ok" || echo "public: missing"
```

- If both exist: continue.
- If missing: ask the user if they want to generate a new key pair now. If yes:
  ```
  ssh-keygen -t ed25519 -f "$HOME/.ssh/id_rsa" -N ""
  ```
  Then re-check.

---

## 4. OCI CLI profile `pa`

Check if the `[pa]` profile section exists in `~/.oci/config`:
```
grep -c "^\[pa\]" "$HOME/.oci/config" 2>/dev/null || echo "0"
```

- If found (count > 0): run `oci session validate --profile pa` to check token validity.
  - If valid: continue.
  - If expired: tell the user to run this themselves (it's interactive):
    ```
    ! oci session authenticate --region il-jerusalem-1 --profile-name pa
    ```
    Then re-validate.
- If not found: tell the user to run the authenticate command above to create the profile.

---

## 5. terraform.tfvars

Check if `infra/terraform.tfvars` exists:
```
test -f infra/terraform.tfvars && echo "exists" || echo "missing"
```

- If exists: read the file and check that no placeholder values containing `XXXX` remain. If any do, show them to the user and ask them to fill them in.
- If missing:
  1. Copy the example: `cp infra/terraform.tfvars.example infra/terraform.tfvars`
  2. Read and show the user which values need filling in (`tenancy_ocid`, `compartment_ocid`, region, etc.)
  3. Tell the user to edit `infra/terraform.tfvars`, then confirm when done.
  4. After confirmation, re-read and verify no `XXXX` placeholders remain.

---

## Done

Once all 5 checks pass, print a summary and suggest the next step:

```
All prerequisites are set up.

Next step: run /deploy to provision your OCI instance.
```
