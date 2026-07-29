# Bluefin NVIDIA lean — experiment pro stroj B

Odvozený image pro RTX 4070 Ti SUPER. Zachovává oficiální
`bluefin-nvidia-open`, ale přegeneruje initramfs bez NVIDIA modulů a GSP
firmwaru. Ovladač se načte až po připojení kořenového filesystemu.

> **Stav 2026-07-29:** CI build prošel. Initramfs se zmenšil z 345 230 987 B
> na 249 136 996 B a kontrola potvrdila, že NVIDIA modul zůstal v rootu, ale
> není v initramfs. Na železe zatím neověřeno. Jde o experimentální workaround
> upstream chyby GRUBu; funkční rollback na plain Bluefin musí zůstat zachovaný.

## Obsah repozitáře

```text
Containerfile
build_files/10-lean-initramfs.sh
.github/workflows/build.yml
```

V GitHubu nastav **Settings → Actions → General → Workflow permissions → Read
and write permissions**. Push na `main` spouští build a publikuje:

```text
ghcr.io/tomasvicar/bluefin-nvidia-lean:latest
```

Build úmyslně selže, když:

- nenajde právě jedno jádro;
- upstream změní NVIDIA dracut konfiguraci;
- výsledný initramfs překročí 290 MiB (funkční plain ISO mělo 282 MB);
- v initramfs zůstane NVIDIA modul nebo GSP firmware;
- NVIDIA modul naopak zmizí z root filesystemu.

## Bezpečný první test na stroji B

Nejdřív si zapiš současný stav:

```bash
sudo bootc status
findmnt /boot /boot/efi
```

Pak image pouze stáhni a připrav jako nový deployment:

```bash
sudo bootc switch ghcr.io/tomasvicar/bluefin-nvidia-lean:latest
sudo bootc status
```

Před rebootem ověř initramfs nového deploymentu. Přesná cesta se vezme z BLS
entry v `/boot/loader/entries/`; soubor musí mít méně než 290 MiB.

Po rebootu jsou možné tři výsledky:

1. Naběhne desktop: ověř `nvidia-smi`, `lsmod | grep nvidia`, oba monitory a
   suspend/resume.
2. Naběhne textová konzole: přihlas se a zjisti `journalctl -b -k`; ovladač se
   pravděpodobně nenačetl pozdě.
3. Nenabootuje: v GRUBu vyber předchozí plain deployment. Když ani ten nejde,
   nabootuj plain USB a proveď `bootc rollback`.

Teprve po úspěšném bootu zapisuj MOK klíč:

```bash
ujust enroll-secure-boot-key
sudo systemctl reboot
```

## Co se musí ověřit

```bash
nvidia-smi
lsmod | grep nvidia
bootc status
journalctl -b -k | grep -Ei 'nvidia|nouveau|simpledrm'
podman run --rm --device nvidia.com/gpu=all \
  nvcr.io/nvidia/cuda:12.6.0-base-ubi9 nvidia-smi
```

Nejdůležitější neověřený předpoklad: EFI framebuffer/simpledrm udrží obraz až
do pozdního načtení NVIDIA modulu. CPU `i7-14700KF` nemá integrovanou grafiku,
takže případná černá obrazovka nemusí znamenat, že systém nenabootoval.
