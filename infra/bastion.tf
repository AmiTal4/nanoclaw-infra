resource "oci_bastion_bastion" "bastion" {
  bastion_type                 = "STANDARD"
  compartment_id               = var.compartment_ocid
  target_subnet_id             = oci_core_subnet.public_subnet.id
  name                         = "pabastion"
  client_cidr_block_allow_list = var.bastion_client_cidrs
}
