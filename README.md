# CDN with Private GCS Bucket

Terraform configuration for a Google Cloud CDN serving content from a **private** Cloud Storage bucket using signed URLs for access control.

## What It Does

- Creates a private GCS bucket with public access prevention enforced
- Sets up Cloud CDN with a global HTTP load balancer
- Configures signed URL authentication for secure content delivery
- Uploads sample `index.html` to the bucket

## Prerequisites

- Google Cloud project with billing enabled
- Terraform >= 1.0
- `gcloud` CLI authenticated
- `openssl` for generating signed URLs

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

   Note the `cdn_ip_address`, `service_account_email`, and `bucket_name` outputs.

3. **Manual IAM Configuration (Required)**

   Due to organization policy restrictions ("Domain Restricted Sharing"), Terraform cannot automatically grant the Cloud CDN service account access to the bucket. You must do this manually:

   ```bash
   # 1. Relax Org Policy (if "Domain Restricted Sharing" is enforced)
   # Create policy.yaml
   cat > policy.yaml <<EOF
   constraint: constraints/iam.allowedPolicyMemberDomains
   listPolicy:
     allValues: ALLOW
   EOF
   gcloud resource-manager org-policies set-policy policy.yaml --project=YOUR_PROJECT_ID
   rm policy.yaml

   # 2. Grant Access
   SA_EMAIL=$(terraform output -raw service_account_email)
   BUCKET_NAME=$(terraform output -raw bucket_name)

   gcloud storage buckets add-iam-policy-binding gs://$BUCKET_NAME \
       --member="serviceAccount:$SA_EMAIL" \
       --role="roles/storage.objectViewer"
   ```

4. **Generate signed URL**

   Wait ~15 minutes for the CDN configuration to propagate. Then:

   ```bash
   ./generate_signed_url.sh http://CDN_IP index.html 3600
   ```
   *Tip: Enclose the output URL in single quotes when using `curl`.*

## Key Design Decisions

**Private bucket with signed URLs**: Ensures content isn't publicly accessible. Only users with valid signed URLs can access objects, providing time-limited, cryptographically secure access control.

**60-second wait timer** (main.tf:99-102): Solves race condition where the `cloud-cdn-fill` service account is created asynchronously after adding a signed URL key. Without this, IAM binding fails.

**Uniform bucket-level access**: Simplifies permissions management by enforcing consistent access control across all objects.

**Project number suffix on bucket name**: Guarantees global uniqueness since bucket names share a global namespace.

## Files

- `main.tf` - Infrastructure definition
- `variables.tf` - Configurable parameters
- `generate_signed_url.sh` - Helper to create signed URLs
- `index.html` - Sample content

## Clean Up

```bash
terraform destroy
```
