#!/bin/bash
# setup-signing.sh
# Run once. Creates a free self-signed code signing certificate called
# "Typing Box Local Signing" in your login keychain. After this, build.sh signs
# with it, so macOS keeps Typing Box's Accessibility permission across rebuilds.
#
# The certificate only exists on this Mac. It isn't an Apple Developer certificate
# and doesn't let you share the app with other people.

set -euo pipefail

NAME="Typing Box Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
OPENSSL=/usr/bin/openssl     # macOS's own copy, so the export works with Keychain
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "The certificate \"$NAME\" already exists. Nothing to do."
    echo "To start over, delete it in Keychain Access, then run this script again."
    exit 0
fi

echo "Creating the certificate..."
cat > "$WORK/cert.cnf" <<CNF
[ req ]
distinguished_name = dn
x509_extensions = ext
prompt = no
[ dn ]
CN = $NAME
[ ext ]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CNF

"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -config "$WORK/cert.cnf" -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null

PASS="typingbox-$RANDOM$RANDOM"
"$OPENSSL" pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -name "$NAME" -out "$WORK/identity.p12" -passout "pass:$PASS"

echo "Adding it to your login keychain..."
security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign >/dev/null

echo "Checking that it can sign..."
cp /usr/bin/true "$WORK/test-binary"
if codesign --force --sign "$NAME" "$WORK/test-binary" 2>/dev/null; then
    echo "Signing works."
else
    echo "macOS needs to trust the certificate for code signing."
    echo "A password dialog will appear. Enter your Mac login password."
    security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"
    codesign --force --sign "$NAME" "$WORK/test-binary"
    echo "Signing works."
fi

cat <<DONE

Done. Next steps:
1. Run: bash build.sh
   If a dialog asks whether codesign can use the key, choose Always Allow.
2. This first signed build still counts as a new app, so reset the permission once:
   tccutil reset Accessibility io.github.jonathan-s01.typingbox
3. Open Typing Box and turn it on in System Settings, Privacy and Security, Accessibility.
After that, rebuilds keep the permission.
DONE
