# --- OCI API authentication ---
variable "tenancy_ocid" {
  description = "OCID of your OCI tenancy"
  type        = string
}



variable "region" {
  description = "OCI region to deploy into (use your tenancy's home region for guaranteed Always Free capacity)"
  type        = string
  default     = "eu-frankfurt-1"
}

# --- Compartment ---
variable "compartment_ocid" {
  description = "OCID of the compartment to create resources in (root compartment = tenancy_ocid)"
  type        = string
}

# --- Networking ---
variable "vcn_cidr" {
  description = "CIDR block for the VCN"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "ssh_allowed_cidr" {
  description = "CIDR allowed to reach the instance over SSH (port 22). Restrict to your own IP, e.g. 203.0.113.10/32, for better security."
  type        = string
  default     = "0.0.0.0/0"
}

# --- Compute ---
variable "availability_domain_number" {
  description = "Which availability domain to use (1-based index)"
  type        = number
  default     = 1
}

variable "instance_shape" {
  description = "Always Free eligible shape: VM.Standard.E2.1.Micro (AMD, fixed) or VM.Standard.A1.Flex (Ampere ARM, flexible)"
  type        = string
  default     = "VM.Standard.E2.1.Micro"
}

variable "instance_ocpus" {
  description = "OCPUs to allocate (only used for Flex shapes, e.g. A1.Flex). Always Free allows up to 4 total."
  type        = number
  default     = 1
}

variable "instance_memory_in_gbs" {
  description = "Memory in GB to allocate (only used for Flex shapes). Always Free allows up to 24 GB total."
  type        = number
  default     = 6
}

variable "boot_volume_size_in_gbs" {
  description = "Boot volume size in GB (Always Free covers up to 200 GB across up to 2 boot volumes)"
  type        = number
  default     = 50
}

variable "ssh_public_key_path" {
  description = "Path to your local SSH public key, injected into the instance for the 'ubuntu' user"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}
