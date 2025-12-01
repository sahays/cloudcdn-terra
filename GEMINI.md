# Gemini Context: Secure Cloud CDN with Private GCS

## Project Overview

This project uses **Terraform** to deploy a secure content delivery architecture on Google Cloud Platform. It serves static content from a **private** Google Cloud Storage (GCS) bucket via **Cloud CDN**, enforcing access control through **Signed URLs**.

**Key Features:**
*   **Private Origin:** The GCS bucket has `public_access_prevention` enforced. Direct access is blocked.
*   **Signed URLs:** Content is only accessible via time-limited, cryptographically signed URLs generated for the CDN.
*   **Global Load Balancing:** Uses a Global HTTP Load Balancer to front the CDN.
*   **Race Condition Handling:** Includes a specific `time_sleep` resource to handle the asynchronous creation of the Google-managed "cloud-cdn-fill" service account.

## Architecture

1.  **Storage:** GCS Bucket (`main.tf`)
    *   Uniform Bucket Level Access: Enabled.
    *   Naming: `${var.bucket_name_prefix}-${project_number}` (Global uniqueness).
2.  **CDN & Networking:**
    *   `google_compute_backend_bucket`: Connects the LB to the bucket, with CDN enabled.
    *   `google_compute_backend_bucket_signed_url_key`: Generates the keys used for signing.
    *   Standard HTTP LB components: `url_map`, `target_http_proxy`, `forwarding_rule`.
3.  **IAM:**
    *   The automatically created `service-{project_number}@cloud-cdn-fill.iam.gserviceaccount.com` is granted `roles/storage.objectViewer` on the bucket.

## Key Files

*   **`main.tf`**: The primary Terraform configuration. Contains the race-condition fix (wait timer) and all resource definitions.
*   **`variables.tf`**: Input variables (`project_id`, `region`, `bucket_name_prefix`, etc.).
*   **`generate_signed_url.sh`**: A Bash utility script. It reads Terraform outputs (`signing_key_value`, `signing_key_name`) to generate a valid signed URL for testing.
*   **`index.html`**: Sample file uploaded to the bucket for verification.

## Usage & Workflow

### 1. Configuration
Create a `terraform.tfvars` file (do not commit this if it contains sensitive data, though this project only requires Project ID):

```hcl
project_id = "your-gcp-project-id"
region     = "asia-south1" # Optional
```

### 2. Deployment
```bash
terraform init
terraform apply
```
*Note: The apply process includes a 60-second sleep to wait for IAM propagation.*

### 3. Verification
After deployment, use the helper script to generate a link. You need the `CDN_IP` from the Terraform outputs.

```bash
# Syntax: ./generate_signed_url.sh <HTTP_URL_PREFIX> <FILE_PATH>
./generate_signed_url.sh http://$(terraform output -raw cdn_ip_address) index.html
```
Open the resulting link in a browser.

### 4. Cleanup
```bash
terraform destroy
```

## Development Notes

*   **Terraform Version:** `>= 1.0`
*   **Provider:** `hashicorp/google ~> 7.12`
*   **Security:** The signing key is generated via `random_id` and stored in the Terraform state. **Treat the state file as sensitive.**
*   **Gotchas:**
    *   **IAM Propagation:** If you remove the `time_sleep` resource, the `google_storage_bucket_iam_member` resource will likely fail because the service account doesn't exist yet.
    *   **OpenSSL:** The `generate_signed_url.sh` script relies on `openssl` being installed in the environment.
