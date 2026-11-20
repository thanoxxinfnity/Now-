#!/usr/bin/env bash
# Creates ONE release keystore for Mugen AI and prints the four values for GitHub Secrets.
#
#   bash tool/make-keystore.sh [output-dir]      (default: ~/mugen-release-key)
#
# Keep the folder it writes: if the keystore is lost, installed apps can never be updated, only
# reinstalled. It is not inside the repository on purpose, and *.keystore is git-ignored anyway.
set -euo pipefail

out="${1:-$HOME/mugen-release-key}"
mkdir -p "$out"
store="$out/mugen-release.keystore"
if [ -e "$store" ]; then
  echo "Refusing to overwrite $store (an existing keystore is the key to your installed apps)." >&2
  exit 1
fi

# Letters and digits only, so no character needs escaping in a secret or a .properties file.
pass="$(openssl rand -hex 16)"
alias_name="mugen"
keytool -genkeypair -v -keystore "$store" -storetype PKCS12 \
  -alias "$alias_name" -keyalg RSA -keysize 2048 -validity 36500 \
  -storepass "$pass" -keypass "$pass" \
  -dname "CN=Mugen AI, OU=Mobile, O=Mugen, C=IN" >/dev/null 2>&1

b64="$out/KEYSTORE_BASE64.txt"
base64 -w0 "$store" > "$b64" 2>/dev/null || base64 "$store" | tr -d '\n' > "$b64"
printf '%s' "$pass" > "$out/PASSWORD.txt"
chmod 600 "$store" "$b64" "$out/PASSWORD.txt"

cat <<MSG
Keystore written to: $store
SHA-256 of its certificate (this must be the same in every release):
$(keytool -list -v -keystore "$store" -storepass "$pass" -alias "$alias_name" 2>/dev/null | grep -m1 "SHA256:" | sed 's/^ *//')

Add these four repository secrets (GitHub -> Settings -> Secrets and variables -> Actions):
  KEYSTORE_BASE64    contents of  $b64
  KEYSTORE_PASSWORD  contents of  $out/PASSWORD.txt
  KEY_ALIAS          $alias_name
  KEY_PASSWORD       same value as KEYSTORE_PASSWORD

With the GitHub CLI, from inside the repository:
  gh secret set KEYSTORE_BASE64   < "$b64"
  gh secret set KEYSTORE_PASSWORD < "$out/PASSWORD.txt"
  gh secret set KEY_PASSWORD      < "$out/PASSWORD.txt"
  gh secret set KEY_ALIAS --body "$alias_name"

Then BACK UP $out somewhere safe, and delete the two .txt files once the secrets are saved.
MSG
