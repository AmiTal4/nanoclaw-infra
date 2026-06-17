output "instance_public_ip" {
  description = "Public IP address of the Ubuntu instance"
  value       = oci_core_instance.ubuntu_instance.public_ip
}

output "instance_id" {
  description = "OCID of the created instance"
  value       = oci_core_instance.ubuntu_instance.id
}

output "ssh_command" {
  description = "Ready-to-use SSH command"
  value       = "ssh -i <path-to-private-key> ubuntu@${oci_core_instance.ubuntu_instance.public_ip}"
}
