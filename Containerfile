# Bluefin pro stroj B (RTX 4070 Ti SUPER): oficiální NVIDIA image, ale malý
# initramfs bez early-KMS NVIDIA modulů a GSP firmwaru.
#
# NVIDIA ovladač i userspace zůstávají v kořenovém filesystemu. Po připojení
# rootu je načte udev/systemd; během časného bootu obraz drží EFI/simpledrm.
ARG BASE_IMAGE="ghcr.io/ublue-os/bluefin-nvidia-open"
ARG BASE_TAG="stable"

FROM ${BASE_IMAGE}:${BASE_TAG}

COPY build_files/ /tmp/build_files/

# Git na Windows nemusí zachovat executable bit.
RUN bash /tmp/build_files/10-lean-initramfs.sh \
 && rm -rf /tmp/build_files

RUN bootc container lint
