data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

# Always picks the most recently published Canonical Ubuntu image that is
# compatible with the chosen shape - no hardcoded image OCID to go stale.
data "oci_core_images" "ubuntu" {
  compartment_id   = var.compartment_ocid
  operating_system = "Canonical Ubuntu"
  shape            = var.instance_shape
  sort_by          = "TIMECREATED"
  sort_order       = "DESC"
}
