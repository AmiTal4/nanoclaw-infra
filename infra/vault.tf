# Software-protected vault (free tier)
resource "oci_kms_vault" "pa_vault" {
  compartment_id = var.compartment_ocid
  display_name   = "pa-vault"
  vault_type     = "DEFAULT"
}

# Master encryption key inside the vault
resource "oci_kms_key" "pa_key" {
  compartment_id      = var.compartment_ocid
  display_name        = "pa-key"
  management_endpoint = oci_kms_vault.pa_vault.management_endpoint
  key_shape {
    algorithm = "AES"
    length    = 32
  }
}

# Secret placeholder — actual value set by /setup-bitwarden skill
resource "oci_vault_secret" "bws_browser_token" {
  compartment_id = var.compartment_ocid
  vault_id       = oci_kms_vault.pa_vault.id
  key_id         = oci_kms_key.pa_key.id
  secret_name    = "bws-browser-token"
  secret_content {
    content_type = "BASE64"
    content      = base64encode("PLACEHOLDER")
  }
  lifecycle {
    ignore_changes = [secret_content]
  }
}

# Dynamic group via identity domains API (required for tenancies that use identity domains;
# the classic oci_identity_dynamic_group resource silently drops matching_rule in such tenancies).
data "oci_identity_domains" "default" {
  compartment_id = var.tenancy_ocid
}

locals {
  idcs_endpoint = data.oci_identity_domains.default.domains[0].url
}

resource "oci_identity_domains_dynamic_resource_group" "pa_instance" {
  idcs_endpoint = local.idcs_endpoint
  display_name  = "pa-instance-group"
  # Match compute instances with instance.id — NOT resource.id. resource.id is
  # only valid for non-instance resource types; for a compute instance it is
  # silently never true, so the instance is never a member of the group and
  # every secret read returns 404 NotAuthorizedOrNotFound even though the rule
  # "looks" set. instance.id is the only correct variable for matching an instance.
  matching_rule = "instance.id = '${oci_core_instance.ubuntu_instance.id}'"
  schemas       = ["urn:ietf:params:scim:schemas:oracle:idcs:DynamicResourceGroup"]
  description   = "PA compute instance — for Vault secret access"
  # matching_rule is returned: request in the SCIM schema — omitted from GET
  # responses unless explicitly requested. Without this, terraform plan always
  # shows it as unknown even though it was correctly written.
  attribute_sets = ["all"]
}

# Policy: allow the instance to read secret contents from the vault.
# Resource type MUST be "secret-bundles" (plural) — this is the Secrets
# Retrieval API resource that grants reading/decrypting a secret's contents.
# "secret-bundle" (singular) is NOT a valid OCI resource type: the policy is
# accepted but matches nothing, producing 404 NotAuthorizedOrNotFound at fetch.
# Scoped to the single secret for least privilege.
resource "oci_identity_policy" "pa_vault_policy" {
  compartment_id = var.tenancy_ocid
  name           = "pa-vault-policy"
  description    = "Allow PA instance to read secrets from pa-vault"
  statements = [
    # Domain-qualified dynamic-group name ('Default'/'pa-instance-group'). In an
    # identity-domains tenancy a bare "dynamic-group pa-instance-group" can fail to
    # resolve to the identity-domain DynamicResourceGroup, so the grant applies to
    # nobody and reads return 404 NotAuthorizedOrNotFound. Qualify with the domain.
    "Allow dynamic-group 'Default'/'pa-instance-group' to read secret-bundles in tenancy where target.secret.id = '${oci_vault_secret.bws_browser_token.id}'"
  ]
}
