#!/bin/bash
# One-time setup: creates a local code-signing certificate ("Claude Usage
# Local") so every build of the app has the same signature. macOS then
# remembers "Always Allow" for the app's saved logins across updates, instead
# of asking for your password again after each rebuild.
#
# Run it yourself: scripts/create-signing-cert.sh
# macOS asks for your password once, to trust the certificate for signing.
# Undo: Keychain Access → login → My Certificates → delete "Claude Usage Local".
set -euo pipefail

NAME="Claude Usage Local"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -q "$NAME"; then
    echo "\"$NAME\" is already set up."
    exit 0
fi

dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT

cat > "$dir/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

# macOS's own LibreSSL writes a PKCS#12 file that `security import` accepts
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$dir/key.pem" -out "$dir/cert.pem" -config "$dir/cert.cnf" 2>/dev/null
/usr/bin/openssl pkcs12 -export -inkey "$dir/key.pem" -in "$dir/cert.pem" \
    -out "$dir/identity.p12" -passout pass:claude-usage -name "$NAME"

security import "$dir/identity.p12" -k "$KEYCHAIN" -P claude-usage -T /usr/bin/codesign
echo "Trusting the certificate for code signing (macOS asks for your password)…"
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$dir/cert.pem"

if security find-identity -v -p codesigning | grep -q "$NAME"; then
    echo "Done. Rebuild with scripts/build-local.sh --install; choose \"Always Allow\" one last time."
else
    echo "The certificate was imported but isn't valid for signing yet." >&2
    exit 1
fi
