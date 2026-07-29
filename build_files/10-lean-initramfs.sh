#!/usr/bin/env bash
set -euo pipefail

# Image smí mít právě jedno aktivní jádro. Kdyby upstream změnil layout, build
# musí raději spadnout než vydat image s neupraveným initramfs.
mapfile -t KERNELS < <(
    find /usr/lib/modules -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort
)
if [[ "${#KERNELS[@]}" -ne 1 ]]; then
    printf 'CHYBA: očekáváno právě jedno jádro, nalezeno %s: %s\n' \
        "${#KERNELS[@]}" "${KERNELS[*]:-žádné}" >&2
    exit 1
fi
KERNEL="${KERNELS[0]}"
INITRAMFS="/usr/lib/modules/${KERNEL}/initramfs.img"

echo "### Jádro: ${KERNEL}"
echo "### Původní initramfs: $(stat -c '%s B' "${INITRAMFS}")"

# Upstream NVIDIA image vynucuje moduly pro early KMS/Plymouth. Přesný název
# konfiguračního souboru se může změnit, proto hledáme podle obsahu. Soubory
# nemažeme: odložíme je mimo adresáře, které dracut načítá.
mapfile -t NVIDIA_DRACUT_CONFIGS < <(
    grep -RIlE \
        'force_drivers.*nvidia|add_drivers.*nvidia|install_items.*gsp_' \
        /usr/lib/dracut/dracut.conf.d /etc/dracut.conf.d 2>/dev/null || true
)
if [[ "${#NVIDIA_DRACUT_CONFIGS[@]}" -eq 0 ]]; then
    echo "CHYBA: nenalezena upstream dracut konfigurace NVIDIA; zkontroluj změnu base image" >&2
    exit 1
fi
for config in "${NVIDIA_DRACUT_CONFIGS[@]}"; do
    echo "### Vyřazuji upstream konfiguraci: ${config}"
    mv "${config}" "${config}.disabled-by-bluefin-nvidia-lean"
done

# Druhá pojistka: i kdyby jiná konfigurace nebo závislost chtěla ovladače
# přidat, dracut je do initramfs nesmí vložit.
install -d /etc/dracut.conf.d
cat > /etc/dracut.conf.d/99-bluefin-nvidia-lean.conf <<'EOF'
omit_drivers+=" nvidia nvidia_drm nvidia_modeset nvidia_uvm nvidia_peermem "
EOF

export DRACUT_NO_XATTR=1
dracut \
    --force \
    --no-hostonly \
    --reproducible \
    --tmpdir /boot \
    --kver "${KERNEL}" \
    --add ostree \
    "${INITRAMFS}"
chmod 0600 "${INITRAMFS}"

SIZE="$(stat -c '%s' "${INITRAMFS}")"
MAX_SIZE="$((290 * 1024 * 1024))"
echo "### Nový initramfs: ${SIZE} B (limit ${MAX_SIZE} B)"
if (( SIZE > MAX_SIZE )); then
    echo "CHYBA: initramfs je stále větší než 290 MiB; na stroji B ho netestuj" >&2
    exit 1
fi

# Kontrola obsahu je důležitější než samotná velikost. Výjimkou mohou být
# textové modprobe konfigurace; hledáme skutečné moduly a velké GSP binárky.
LIST="$(mktemp)"
trap 'rm -f "${LIST}"' EXIT
lsinitrd "${INITRAMFS}" > "${LIST}"
if grep -Eq '/nvidia(_drm|_modeset|_uvm|_peermem)?\.ko(\.(xz|zst|gz))?$|/gsp_[^/]+\.bin$' "${LIST}"; then
    echo "CHYBA: v initramfs zůstaly NVIDIA moduly nebo GSP firmware:" >&2
    grep -E '/nvidia(_drm|_modeset|_uvm|_peermem)?\.ko|/gsp_[^/]+\.bin' "${LIST}" >&2
    exit 1
fi

# Ovladač ale musí zůstat v root filesystemu pro pozdní načtení.
if ! modinfo -k "${KERNEL}" nvidia >/dev/null; then
    echo "CHYBA: NVIDIA modul v root filesystemu chybí" >&2
    exit 1
fi

echo "### OK: NVIDIA je v rootu, ale není v initramfs"
