import base64
import hashlib
import hmac
import time
import urllib.parse

def generate_signed_url(url_prefix, url_path, key_name, key_value_b64url, expiration_seconds=3600):
    expires = int(time.time()) + expiration_seconds

    # Construct the URL to sign
    url_to_sign = f"{url_prefix}/{url_path}?Expires={expires}&KeyName={key_name}"

    # Decode the base64url key value
    # Add padding if missing, then decode
    missing_padding = len(key_value_b64url) % 4
    if missing_padding:
        key_value_b64url += '=' * (4 - missing_padding)
    key_value = base64.urlsafe_b64decode(key_value_b64url)

    # Generate signature
    signature = hmac.new(key_value, url_to_sign.encode('utf-8'), hashlib.sha1).digest()
    signed_signature = base64.urlsafe_b64encode(signature).decode('utf-8').rstrip('=')

    # Final signed URL
    signed_url = f"{url_to_sign}&Signature={signed_signature}"
    return signed_url

# Get values from terraform outputs (replace with actual outputs)
CDN_IP = "34.120.74.157" # From terraform output -raw cdn_ip_address
KEY_NAME = "cdn-signing-key" # From terraform output -raw signing_key_name
KEY_VALUE_B64URL = "jGmZRNCXK6mtVKmJ4BpEYQ" # From terraform output -raw signing_key_value

URL_PREFIX = f"http://{CDN_IP}"
URL_PATH = "index.html"

signed_url = generate_signed_url(URL_PREFIX, URL_PATH, KEY_NAME, KEY_VALUE_B64URL)
print(f"Generated Signed URL (Python):\n{signed_url}")
