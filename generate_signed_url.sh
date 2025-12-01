#!/bin/bash
# Helper script to generate signed URLs for Cloud CDN

set -e

# Check if required arguments are provided
if [ $# -lt 2 ]; then
    echo "Usage: $0 <url-prefix> <url-path> [expiration-seconds]"
    echo ""
    echo "Example: $0 http://YOUR_CDN_IP index.html 3600"
    echo ""
    echo "To get the signing key value, run:"
    echo "  terraform output -raw signing_key_value"
    exit 1
fi

URL_PREFIX="$1"
URL_PATH="$2"
EXPIRATION="${3:-3600}"  # Default to 1 hour

# Get the signing key value from Terraform output
KEY_NAME=$(terraform output -raw signing_key_name)
KEY_VALUE=$(terraform output -raw signing_key_value)

# Calculate expiration timestamp
EXPIRES=$(date -u -d "+${EXPIRATION} seconds" '+%s' 2>/dev/null || date -u -v "+${EXPIRATION}S" '+%s')

# Create the URL to sign
URL_TO_SIGN="${URL_PREFIX}/${URL_PATH}?Expires=${EXPIRES}&KeyName=${KEY_NAME}"

# Generate signature
# Note: The key needs to be base64-decoded first
SIGNATURE=$(echo -n "${URL_TO_SIGN}" | openssl dgst -sha1 -hmac "$(echo -n "${KEY_VALUE}" | base64 -d)" -binary | openssl base64 | tr '+/' '-_' | tr -d '=')

# Output the final signed URL
SIGNED_URL="${URL_TO_SIGN}&Signature=${SIGNATURE}"

echo "Signed URL (valid for ${EXPIRATION} seconds):"
echo "${SIGNED_URL}"
