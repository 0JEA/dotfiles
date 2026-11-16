#!/usr/bin/env bash
# check-packages.sh: check that packages.md matches the package lists.
#
# Installed = pacstrap line in arch-install.sh + every pkglist-*.txt.
# Documented = every `name` in the first column of packages.md, except the
# "Not Installed by Scripts" section, whose names must NOT be installed.
# A row whose notes name a list file (`pkglist-laptop.txt`) must be in that list.
#
# Usage: bash install/check-packages.sh     (exit 1 on any mismatch)
set -euo pipefail
cd "$(dirname "$0")"

# pacstrap packages: the lines after "pacstrap -K /mnt \" up to the first line
# not ending in "\". "$UCODE_PKG" is picked at install time, so it is skipped.
pacstrap=$(awk '/^pacstrap /{f=1; next} f{print; if ($0 !~ /\\$/) exit}' arch-install.sh \
    | tr -d '\\' | tr ' ' '\n' | grep -v -e '^$' -e 'UCODE_PKG' || true)
[[ -n "$pacstrap" ]] || { echo "could not read the pacstrap line in arch-install.sh"; exit 2; }

installed=$( { echo "$pacstrap"; cat pkglist-*.txt; } | grep -v '^$' | sort -u)

# packages.md rows: "| `name` | notes |". Section 1 = normal, 2 = Not Installed.
rows=$(awk -F'|' '
    /^## Not Installed by Scripts/ {sec=2; next}
    /^## / {sec=1}
    sec && $2 ~ /`[^`]+`/ { n=$2; gsub(/[ `]/, "", n); print sec "\t" n "\t" $3 }
' packages.md)
documented=$(awk -F'\t' '$1==1 {print $2}' <<<"$rows" | sort -u)
not_installed=$(awk -F'\t' '$1==2 {print $2}' <<<"$rows" | sort -u)

fail=0
report() { [[ -n "$2" ]] && { echo "$1"; sed 's/^/  /' <<<"$2"; fail=1; }; return 0; }

report "Installed but not in packages.md:" "$(comm -23 <(echo "$installed") <(echo "$documented"))"
report "In packages.md but not installed by any list:" "$(comm -13 <(echo "$installed") <(echo "$documented"))"
report "Under \"Not Installed by Scripts\" but a list installs it:" "$(comm -12 <(echo "$installed") <(echo "$not_installed"))"

# Rows that say which list they come from must be in that list.
wrong_list=$(awk -F'\t' '$1==1' <<<"$rows" | while IFS=$'\t' read -r _ name notes; do
    list=$(grep -o 'pkglist-[a-z]*\.txt' <<<"$notes" | head -1 || true)
    [[ -z "$list" ]] && continue
    grep -qxF "$name" "$list" 2>/dev/null || echo "$name (notes say $list)"
done)
report "Rows that name a list file they are not in:" "$wrong_list"

# And every entry in a hardware list must say so in its row.
for list in pkglist-laptop.txt pkglist-nvidia.txt; do
    untagged=$(while read -r name; do
        [[ -z "$name" ]] && continue
        awk -F'\t' -v n="$name" '$1==1 && $2==n' <<<"$rows" | grep -qF "$list" || echo "$name"
    done < "$list")
    report "In $list but its packages.md row doesn't mention $list:" "$untagged"
done

if [[ $fail -eq 0 ]]; then
    echo "OK: packages.md matches $(wc -l <<<"$installed") installed packages" \
         "(pacstrap + $(ls pkglist-*.txt | wc -l) lists)"
fi
exit $fail
