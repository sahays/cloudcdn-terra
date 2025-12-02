# CDN with Private GCS Bucket

Terraform configuration for a Google Cloud CDN serving content from a **private** Cloud Storage bucket using HMAC-based private origin authentication.

## What It Does

- Creates a private GCS bucket with public access prevention enforced
- Sets up Cloud CDN with a global HTTP load balancer
- Uses HMAC keys with AWS V4 signature authentication for private origin access
- No client-side authentication required - CDN handles it transparently
- Uploads sample `index.html` to the bucket

## Prerequisites

- Google Cloud project with billing enabled
- Terraform >= 1.0
- `gcloud` CLI authenticated

## Setup

1. **Configure variables**

   Create `terraform.tfvars`:
   ```hcl
   project_id = "your-gcp-project-id"
   ```

2. **Deploy infrastructure**

   ```bash
   terraform init
   terraform apply
   ```

   Note the `cdn_ip_address` and `bucket_name` outputs.

3. **Test access**

   Wait 5-10 minutes for the CDN to propagate globally, then:

   ```bash
   curl http://CDN_IP/index.html
   ```

   No signed URLs needed - the CDN handles authentication automatically.

## Key Design Decisions

**HMAC-based private origin authentication**: CDN uses HMAC keys to sign requests to GCS using AWS V4 signatures. The bucket stays private while CDN has transparent access. No signed URLs or client-side authentication needed.

**Internet NEG with bucket-specific FQDN** (main.tf:91): The NEG endpoint must use `{bucket-name}.storage.googleapis.com`, not just `storage.googleapis.com`. This matches the Host header and ensures proper routing to the private bucket.

**`FORCE_CACHE_ALL` without `max_ttl`** (main.tf:108): Google Cloud CDN requires omitting `max_ttl` when using `FORCE_CACHE_ALL` mode. The `max_ttl` parameter only applies to `CACHE_ALL_STATIC` mode which respects origin cache headers.

**Backend service (not backend bucket)**: Private origin authentication requires an Internet NEG backend service instead of a backend bucket. This incurs additional egress charges on cache misses but enables private bucket access.

**Project number suffix on bucket name**: Guarantees global uniqueness since bucket names share a global namespace.

## Files

- `main.tf` - Infrastructure definition
- `variables.tf` - Configurable parameters
- `index.html` - Sample content

## Clean Up

```bash
terraform destroy
```
