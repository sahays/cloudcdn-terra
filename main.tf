terraform {
  required_version = ">= 1.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.12"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Backend configuration for remote state (uncomment and configure as needed)
  # backend "gcs" {
  #   bucket = "your-terraform-state-bucket"
  #   prefix = "cdn-private-bucket"
  # }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Get Project Details (specifically Project Number for the Service Account)
data "google_project" "project" {
  project_id = var.project_id
}

locals {
  # The Cloud CDN "Fill" service account is created automatically but asynchronously.
  # We construct the email here to keep the resource block clean.
  cloud_cdn_service_account = "service-${data.google_project.project.number}@cloud-cdn-fill.iam.gserviceaccount.com"
}

# 1. Create the Bucket
resource "google_storage_bucket" "cdn_bucket" {
  # Naming convention: prefix + project_number to ensure global uniqueness
  name                        = "${var.bucket_name_prefix}-${data.google_project.project.number}"
  location                    = var.bucket_location
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  storage_class               = "STANDARD"
  force_destroy               = true
  labels                      = var.labels
}

# 2. Upload Index File
resource "google_storage_bucket_object" "index_page" {
  name   = "index.html"
  bucket = google_storage_bucket.cdn_bucket.name
  source = "${path.module}/index.html"

  # Trigger replacement when file content changes
  content_type = "text/html"
  cache_control = "public, max-age=3600"
}

resource "google_project_service" "compute_api" {
  project = var.project_id
  service = "compute.googleapis.com"
  # Do not disable the service on destroy. This avoids issues if other resources also depend on it.
  disable_on_destroy = false
}

# 3. Create the Backend Bucket
resource "google_compute_backend_bucket" "cdn_backend" {
  depends_on  = [google_project_service.compute_api]
  name        = "${var.lb_name_prefix}-backend-bucket"
  bucket_name = google_storage_bucket.cdn_bucket.name
  enable_cdn  = true

  cdn_policy {
    cache_mode        = "CACHE_ALL_STATIC"
    default_ttl       = 3600
    max_ttl           = 86400
    client_ttl        = 7200
    negative_caching  = true
    serve_while_stale = 86400
  }
}

# 3a. Generate Random Key for Signed URLs
resource "random_id" "url_signature" {
  byte_length = 16
}

# 3b. Create Signed URL Key (This triggers creation of cloud-cdn-fill service account)
resource "google_compute_backend_bucket_signed_url_key" "cdn_key" {
  name           = "cdn-signing-key"
  backend_bucket = google_compute_backend_bucket.cdn_backend.name
  key_value      = random_id.url_signature.b64_url
}

# Wait for Backend Bucket to be fully ready before attaching to URL Map
resource "time_sleep" "wait_for_backend_bucket" {
  depends_on = [google_compute_backend_bucket.cdn_backend]
  create_duration = "30s"
}

# 4. Wait Timer (To solve the race condition)
# The cloud-cdn-fill service account is created when the signed URL key is added
resource "time_sleep" "wait_for_service_account" {
  depends_on = [google_compute_backend_bucket_signed_url_key.cdn_key]
  create_duration = "120s"
}

# 5. Grant Access - MANUAL STEP REQUIRED
# Due to "Domain Restricted Sharing" organization policies, we skip the automated
# IAM binding. You must manually grant 'roles/storage.objectViewer' to the
# service account displayed in the outputs.

output "service_account_email" {
  value       = local.cloud_cdn_service_account
  description = "The Cloud CDN service account that needs access to the bucket."
}

# --- Load Balancer Components ---

resource "google_compute_global_address" "cdn_ip" {
  name   = "${var.lb_name_prefix}-public-ip"
  labels = var.labels
}

resource "google_compute_url_map" "cdn_url_map" {
  name            = "${var.lb_name_prefix}-url-map"
  default_service = google_compute_backend_bucket.cdn_backend.id
  depends_on      = [time_sleep.wait_for_backend_bucket]
}

resource "google_compute_target_http_proxy" "cdn_proxy" {
  name    = "${var.lb_name_prefix}-http-proxy"
  url_map = google_compute_url_map.cdn_url_map.id
}

resource "google_compute_global_forwarding_rule" "cdn_forwarding_rule" {
  name       = "${var.lb_name_prefix}-forwarding-rule"
  target     = google_compute_target_http_proxy.cdn_proxy.id
  ip_address = google_compute_global_address.cdn_ip.address
  port_range = "80"
}

output "cdn_ip_address" {
  value       = google_compute_global_address.cdn_ip.address
  description = "The IP address of the CDN load balancer"
}

output "bucket_name" {
  value       = google_storage_bucket.cdn_bucket.name
  description = "The name of the created GCS bucket"
}

output "signing_key_name" {
  value       = google_compute_backend_bucket_signed_url_key.cdn_key.name
  description = "The name of the signing key for generating signed URLs"
}

output "signing_key_value" {
  value       = random_id.url_signature.b64_url
  description = "The base64-encoded signing key value (keep secret!)"
  sensitive   = true
}

