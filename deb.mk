# ---------------------------------------------------------------------------
# Standalone .deb packaging for toybox (opt-in targets only).
#
# 用法（在 source build/envsetup.sh && lunch 之后的 shell 里执行）：
#
#   cd external/toybox
#   command make deb         生成 toybox_<ver>_armhf.deb
#                            动态链接版本：/system/bin/toybox + 每个 applet 的符号链接，
#                            Depends 从二进制的 ELF NEEDED 自动生成
#                            （bionic 提供 libc/libm/libdl，其余库各自成包）
#
#   command make deb-static  生成 toybox-static_<ver>_armhf.deb
#                            静态链接版本：只包含单个 /system/bin/toybox，无任何依赖
#
# 注意：envsetup.sh 里 make 是个 shell 函数（会转发给 AOSP 构建），所以这里
# 要用 command make 调用真正的 make。
#
# 这两个目标不会被 AOSP 的默认构建（Android.mk / droid）引用；直接编译
# toybox 时仍然走 Android.mk，与上游行为一致。
# ---------------------------------------------------------------------------

DEB_TOP := $(abspath $(CURDIR)/../..)
DEB_PRODUCT_OUT ?= $(if $(ANDROID_PRODUCT_OUT),$(ANDROID_PRODUCT_OUT),$(DEB_TOP)/out/target/product/generic)
DEB_TOYBOX := $(DEB_PRODUCT_OUT)/system/bin/toybox
DEB_TOYBOX_STATIC := $(DEB_PRODUCT_OUT)/recovery/root/sbin/toybox_static
DEB_WORK := $(CURDIR)/out-deb

DEB_VERSION := $(shell sed -n 's/^#define TOYBOX_VERSION "\(.*\)"/\1/p' $(CURDIR)/main.c)-android
# 架构映射（TARGET_ARCH / libc.so 推断 / 默认 arm，学 Debian：arm64 不是 aarch64）
include $(DEB_TOP)/build/make/tools/deb/arch.mk
DEB_MAINTAINER := CaremiumOS Developers <caremium-os@googlegroups.com>

# bionic 版本跟随平台实际版本（build/make/core/version_defaults.mk）
DEB_BIONIC_VERSION := $(shell sed -n 's/^PLATFORM_VERSION\.OPM1 := //p' $(DEB_TOP)/build/make/core/version_defaults.mk)
ifeq ($(strip $(DEB_BIONIC_VERSION)),)
DEB_BIONIC_VERSION := 8.1.0
endif

# 已启用的 applet 列表在 deb 目标里从 generated/newtoys.h 提取
# （generated/newtoys.h 由 .config 生成）

$(DEB_TOYBOX):
	@test -n "$(ANDROID_BUILD_TOP)" || \
	    { echo "错误：请先 source build/envsetup.sh && lunch <product>"; exit 1; }
	$(MAKE) -C $(DEB_TOP) toybox

$(DEB_TOYBOX_STATIC):
	@test -n "$(ANDROID_BUILD_TOP)" || \
	    { echo "错误：请先 source build/envsetup.sh && lunch <product>"; exit 1; }
	$(MAKE) -C $(DEB_TOP) toybox_static

.PHONY: deb deb-static deb-clean

deb: $(DEB_TOYBOX)
	@set -e; \
	root=$(DEB_WORK)/toybox; \
	rm -rf $$root; mkdir -p $$root/DEBIAN $$root/system/bin; \
	install -m 0755 $(DEB_TOYBOX) $$root/system/bin/toybox; \
	for a in $$(sed -n 's/.*NEWTOY(\([^,]*\),.*/\1/p;s/.*OLDTOY(\([^,]*\),.*/\1/p' $(CURDIR)/generated/newtoys.h | grep -v '^-' | grep -v '^toybox$$' | sort -u); do \
	    ln -sf toybox $$root/system/bin/$$a; \
	done; \
	depends="bionic (>= $(DEB_BIONIC_VERSION))"; \
	for lib in $$(readelf -d $(DEB_TOYBOX) | sed -n 's/.*Shared library: \[\(lib.*\)\.so\]/\1/p'); do \
	    case $$lib in \
	        libc|libm|libdl) ;; \
	        *) depends="$$depends, $$lib" ;; \
	    esac; \
	done; \
	size=$$(du -sk $$root | cut -f1); \
	sed -e "s|@PACKAGE@|toybox|g" \
	    -e "s|@VERSION@|$(DEB_VERSION)|g" \
	    -e "s|@ARCH@|$(DEB_ARCH)|g" \
	    -e "s|@MAINTAINER@|$(DEB_MAINTAINER)|g" \
	    -e "s|@INSTALLED_SIZE@|$$size|g" \
	    -e "s|@DEPENDS@|$$depends|g" \
	    $(CURDIR)/deb/control.in > $$root/DEBIAN/control; \
	echo 2.0 > $(DEB_WORK)/debian-binary; \
	tar --owner=0 --group=0 --numeric-owner -czf $(DEB_WORK)/control.tar.gz -C $$root/DEBIAN .; \
	tar --owner=0 --group=0 --numeric-owner -czf $(DEB_WORK)/data.tar.gz -C $$root ./system; \
	rm -f $(CURDIR)/toybox_$(DEB_VERSION)_$(DEB_ARCH).deb; \
	ar rc $(CURDIR)/toybox_$(DEB_VERSION)_$(DEB_ARCH).deb \
	    $(DEB_WORK)/debian-binary $(DEB_WORK)/control.tar.gz $(DEB_WORK)/data.tar.gz; \
	echo "生成 $(CURDIR)/toybox_$(DEB_VERSION)_$(DEB_ARCH).deb"; \
	echo "Depends: $$depends"

deb-static: $(DEB_TOYBOX_STATIC)
	@set -e; \
	root=$(DEB_WORK)/toybox-static; \
	rm -rf $$root; mkdir -p $$root/DEBIAN $$root/system/bin; \
	install -m 0755 $(DEB_TOYBOX_STATIC) $$root/system/bin/toybox; \
	size=$$(du -sk $$root | cut -f1); \
	sed -e "s|@PACKAGE@|toybox-static|g" \
	    -e "s|@VERSION@|$(DEB_VERSION)|g" \
	    -e "s|@ARCH@|$(DEB_ARCH)|g" \
	    -e "s|@MAINTAINER@|$(DEB_MAINTAINER)|g" \
	    -e "s|@INSTALLED_SIZE@|$$size|g" \
	    $(CURDIR)/deb/control-static.in > $$root/DEBIAN/control; \
	echo 2.0 > $(DEB_WORK)/debian-binary; \
	tar --owner=0 --group=0 --numeric-owner -czf $(DEB_WORK)/control.tar.gz -C $$root/DEBIAN .; \
	tar --owner=0 --group=0 --numeric-owner -czf $(DEB_WORK)/data.tar.gz -C $$root ./system; \
	rm -f $(CURDIR)/toybox-static_$(DEB_VERSION)_$(DEB_ARCH).deb; \
	ar rc $(CURDIR)/toybox-static_$(DEB_VERSION)_$(DEB_ARCH).deb \
	    $(DEB_WORK)/debian-binary $(DEB_WORK)/control.tar.gz $(DEB_WORK)/data.tar.gz; \
	echo "生成 $(CURDIR)/toybox-static_$(DEB_VERSION)_$(DEB_ARCH).deb"

deb-clean:
	rm -rf $(DEB_WORK) \
	    $(CURDIR)/toybox_$(DEB_VERSION)_$(DEB_ARCH).deb \
	    $(CURDIR)/toybox-static_$(DEB_VERSION)_$(DEB_ARCH).deb
