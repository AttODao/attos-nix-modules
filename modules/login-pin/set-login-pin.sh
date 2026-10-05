set -eu

user="${1:-attodao}"

allowed_users=" @ALLOWED_USERS@ "

case "$allowed_users" in
  *" $user "*) ;;
  *)
    echo "error: user '$user' is not enabled for login PIN" >&2
    exit 1
    ;;
esac

if [ "$(id -u)" -ne 0 ]; then
  echo "error: run as root, for example: sudo set-login-pin $user" >&2
  exit 1
fi

printf "New 6-digit PIN for %s: " "$user" >&2
read -r -s pin1
printf "\nConfirm 6-digit PIN: " >&2
read -r -s pin2
printf "\n" >&2

if [ "$pin1" != "$pin2" ]; then
  echo "error: PINs do not match" >&2
  exit 1
fi

case "$pin1" in
  [0-9][0-9][0-9][0-9][0-9][0-9]) ;;
  *)
    echo "error: PIN must be exactly 6 digits" >&2
    exit 1
    ;;
esac

install -d -m 0700 -o root -g root /etc/security/login-pin

# Feed the PIN through a private fd so it never appears in the process arguments.
hash="$(python3 - 3<<<"$pin1" <<'PY'
import base64
import hashlib
import os

with os.fdopen(3, encoding="utf-8") as pin_stream:
    pin = pin_stream.read().rstrip("\n")
iterations = 200000
salt = os.urandom(16)
digest = hashlib.pbkdf2_hmac(
    "sha256",
    pin.encode("utf-8"),
    salt,
    iterations,
)

print(
    "pbkdf2_sha256"
    + "$"
    + str(iterations)
    + "$"
    + base64.b64encode(salt).decode("ascii")
    + "$"
    + base64.b64encode(digest).decode("ascii")
)
PY
)"
unset pin1 pin2

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
printf "%s\n" "$hash" > "$tmp"
install -m 0600 -o root -g root "$tmp" "/etc/security/login-pin/$user.pbkdf2"
trap - EXIT
rm -f "$tmp"

echo "PIN updated for $user"
