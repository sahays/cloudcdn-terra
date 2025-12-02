terraform {
  required_version = ">= 1.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.12"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
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

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

# Get Project Details
data "google_project" "project" {
  project_id = var.project_id
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

# 3. Create Service Account for CDN Access
resource "google_service_account" "cdn_sa" {
  account_id   = "cdn-access-sa"
  display_name = "Service Account for CDN Private Bucket Access"
}

# 4. Grant Access to the Service Account
resource "google_storage_bucket_iam_member" "cdn_access" {
  bucket = google_storage_bucket.cdn_bucket.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.cdn_sa.email}"
}

# 5. Generate HMAC Keys for the Service Account
resource "google_storage_hmac_key" "cdn_hmac_key" {
  service_account_email = google_service_account.cdn_sa.email
}

# 6. Create Internet NEG pointing to GCS
resource "google_compute_global_network_endpoint_group" "gcs_neg" {
  name                  = "${var.lb_name_prefix}-gcs-neg"
  network_endpoint_type = "INTERNET_FQDN_PORT"
  default_port          = 443
}

resource "google_compute_global_network_endpoint" "gcs_endpoint" {
  global_network_endpoint_group = google_compute_global_network_endpoint_group.gcs_neg.id
  fqdn                          = "${google_storage_bucket.cdn_bucket.name}.storage.googleapis.com"
  port                          = 443
}

# 7. Create Backend Service with Private Origin Authentication
resource "google_compute_backend_service" "cdn_backend" {
  provider              = google-beta
  name                  = "${var.lb_name_prefix}-backend-service"
  load_balancing_scheme = "EXTERNAL"
  protocol              = "HTTPS"
  enable_cdn            = true

  backend {
    group = google_compute_global_network_endpoint_group.gcs_neg.id
  }

  cdn_policy {
    cache_mode                   = "FORCE_CACHE_ALL"
    default_ttl                  = 3600
    client_ttl                   = 7200
    negative_caching             = true
    serve_while_stale            = 86400
    signed_url_cache_max_age_sec = 3600
  }

  custom_request_headers = [
    "Host: ${google_storage_bucket.cdn_bucket.name}.storage.googleapis.com"
  ]

  security_settings {
    aws_v4_authentication {
      access_key_id = google_storage_hmac_key.cdn_hmac_key.access_id
      access_key    = google_storage_hmac_key.cdn_hmac_key.secret
      origin_region = var.bucket_location
    }
  }

  depends_on = [
    google_compute_global_network_endpoint.gcs_endpoint
  ]
}

# --- Load Balancer Components ---

resource "google_compute_global_address" "cdn_ip" {
  name   = "${var.lb_name_prefix}-public-ip"
  labels = var.labels
}

resource "google_compute_url_map" "cdn_url_map" {
  name            = "${var.lb_name_prefix}-url-map"
  default_service = google_compute_backend_service.cdn_backend.id
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