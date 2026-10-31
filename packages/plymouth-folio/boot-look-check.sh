# interstellar-boot-look-check: runs in the initrd before Plymouth starts.
#
# The boot loader may load a second archive after NixOS's initrd: the look
# the owner last chose, printed by boot_look.py, unpacked by the kernel into
# /etc/interstellar/boot-look. Plymouth is pointed at
# /run/interstellar/themes/interstellar-look first and falls back to the
# look built into this initrd when that is missing. This puts the archive's
# look there only when its manifest and every file in it check out, so an
# archive cut short, damaged or from another format version can only ever
# mean the built-in look, never a blank page. It never fails the boot: every
# refusal exits 0, and Plymouth starts after it either way.
#
# The two paths come from the environment only in tests (test_boot_look.py).
staging=${INTERSTELLAR_STAGING:-/etc/interstellar/boot-look}
themes=${INTERSTELLAR_THEMES:-/run/interstellar/themes}
name=interstellar-look

say() { echo "interstellar-boot-look: $*"; }
refuse() {
  say "refusing the look on the boot partition ($1); showing the built-in look"
  rm -rf "$themes/.$name.new"
  exit 0
}

if [ ! -d "$staging" ]; then
  say "no look on the boot partition; showing the built-in look"
  exit 0
fi
cd "$staging" || refuse "unreadable"

# The manifest's own checksum is the archive's last file.
[ -f MANIFEST.sha256 ] && [ -f MANIFEST ] || refuse "incomplete"
read -r sum file rest < MANIFEST.sha256 || true
[[ ${sum:-} =~ ^[0-9a-f]{64}$ ]] && [ "${file:-}" = MANIFEST ] && [ -z "${rest:-}" ] || refuse "manifest"
sha256sum --check --strict --status MANIFEST.sha256 || refuse "manifest checksum"

# Every listed file: a plain name, then all of them must match.
files=()
plymouth=0
script=0
while read -r sum file rest; do
  [[ ${sum:-} =~ ^[0-9a-f]{64}$ ]] && [[ ${file:-} =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] && [ -z "${rest:-}" ] \
    || refuse "manifest entry"
  case "$file" in
    "$name.plymouth") plymouth=1 ;;
    "$name.script") script=1 ;;
    MANIFEST | MANIFEST.sha256) refuse "manifest entry" ;;
  esac
  files+=("$file")
done < MANIFEST
[ "${#files[@]}" -ge 2 ] && [ "${#files[@]}" -le 64 ] || refuse "file count"
[ "$plymouth" = 1 ] && [ "$script" = 1 ] || refuse "no theme"
sha256sum --check --strict --status MANIFEST || refuse "checksum"

read -r look < LOOK 2>/dev/null || look="?"
mkdir -p "$themes"
rm -rf "$themes/.$name.new"
mkdir "$themes/.$name.new"
cp -- "${files[@]}" "$themes/.$name.new/" || refuse "copy"
rm -rf "$themes/$name"
mv -T "$themes/.$name.new" "$themes/$name" || refuse "install"
say "showing the look on the boot partition: $look"
