output "instance_id" {
  description = "OCID of the created instance"
  value       = oci_core_instance.ubuntu_instance.id
}

output "instance_private_ip" {
  description = "Private IP of the instance (reachable via Bastion only)"
  value       = oci_core_instance.ubuntu_instance.private_ip
}

output "bastion_id" {
  description = "OCID of the Bastion — read by scripts/connect.sh"
  value       = oci_bastion_bastion.bastion.id
}

output "region" {
  description = "OCI region — read by scripts/connect.sh"
  value       = var.region
}

output "ssh_private_key_path" {
  description = "Path to the SSH private key configured in terraform.tfvars"
  value       = var.ssh_private_key_path
}

output "ssh_public_key_path" {
  description = "Path to the SSH public key configured in terraform.tfvars"
  value       = var.ssh_public_key_path
}

output "vault_secret_ocid" {
  description = "OCID of the bws-browser-token secret in OCI Vault"
  value       = oci_vault_secret.bws_browser_token.id
}

output "compartment_ocid" {
  description = "Compartment OCID"
  value       = var.compartment_ocid
}
