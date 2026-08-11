#!/usr/bin/env bash
set -euo pipefail

install -d "$STAGE/usr/include" "$STAGE/usr/share/vulkan"
cp -a include/vulkan include/vk_video "$STAGE/usr/include/"
cp -a registry "$STAGE/usr/share/vulkan/"
test -f "$STAGE/usr/include/vulkan/vulkan.h"
test -f "$STAGE/usr/include/vk_video/vulkan_video_codec_h264std.h"
test -f "$STAGE/usr/share/vulkan/registry/vk.xml"
