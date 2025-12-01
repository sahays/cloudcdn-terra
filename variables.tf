variable "project_id" {
  description = "The Google Cloud Project ID"
  type        = string
}

variable "region" {
  description = "The default region for the Terraform provider"
  type        = string
  default     = "asia-south1"
}

variable "bucket_location" {
  description = "The geographic location for the GCS bucket (e.g., asia-south1)"
  type        = string
  default     = "asia-south1"
}

variable "bucket_name_prefix" {
  description = "Prefix for the bucket name. Project Number will be appended for uniqueness."
  type        = string
  default     = "secure-cdn-bucket"
}

variable "lb_name_prefix" {
  description = "Prefix for the Load Balancer components (IP, URL Map, Proxy, Forwarding Rule)."
  type        = string
  default     = "cdn"
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    managed_by = "terraform"
    project    = "cdn-private-bucket"
  }
}
