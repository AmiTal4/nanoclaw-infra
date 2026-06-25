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

# Dynamic group: the PA instance can authenticate as itself
resource "oci_identity_dynamic_group" "pa_instance" {
  compartment_id = var.tenancy_ocid
  name           = "pa-instance-group"
  description    = "PA compute instance — for Vault secret access"
  matching_rule  = "resource.id = '${oci_core_instance.ubuntu_instance.id}'"
}

# Policy: allow the instance to read secrets from the vault
resource "oci_identity_policy" "pa_vault_policy" {
  compartment_id = var.tenancy_ocid
  name           = "pa-vault-policy"
  description    = "Allow PA instance to read secrets from pa-vault"
  statements = [
    "Allow dynamic-group pa-instance-group to read secret-family in compartment id ${var.compartment_ocid} where target.vault.id = '${oci_kms_vault.pa_vault.id}'"
  ]
}
