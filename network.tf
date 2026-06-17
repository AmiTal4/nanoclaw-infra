resource "oci_core_vcn" "vcn" {
  compartment_id = var.compartment_ocid
  cidr_block     = var.vcn_cidr
  display_name   = "personal assistant vcn"
  dns_label      = "pavcn"
}

resource "oci_core_internet_gateway" "igw" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.vcn.id
  display_name   = "personal assistant igw"
  enabled        = true
}

resource "oci_core_route_table" "public_rt" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.vcn.id
  display_name   = "personal assistant public rt"

  route_rules {
    destination       = "0.0.0.0/0"
    network_entity_id = oci_core_internet_gateway.igw.id
  }
}

# Security list: only SSH (22/tcp) inbound is allowed. All outbound traffic
# is allowed so the instance can reach the internet (apt updates, etc).
resource "oci_core_security_list" "ssh_only" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.vcn.id
  display_name   = "pa-ssh-only-sl"

  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
    stateless   = false
  }

  ingress_security_rules {
    source    = var.ssh_allowed_cidr
    protocol  = "6" # TCP
    stateless = false

    tcp_options {
      min = 22
      max = 22
    }
  }
}

resource "oci_core_subnet" "public_subnet" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.vcn.id
  cidr_block                 = var.subnet_cidr
  display_name               = "pa-public-subnet"
  dns_label                  = "pasubnet"
  route_table_id             = oci_core_route_table.public_rt.id
  security_list_ids          = [oci_core_security_list.ssh_only.id]
  prohibit_public_ip_on_vnic = false
}
