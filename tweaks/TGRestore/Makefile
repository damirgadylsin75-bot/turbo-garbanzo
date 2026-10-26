TARGET := iphone:clang:latest:15.0
ARCH_DEFAULT := arm64
ARCHS := $(ARCH_DEFAULT)
TARGET_UC := iphone
TARGET_IOS := iOS

# Rootless jailbreak (Dopamine / palera1n) package scheme.
THEOS_PACKAGE_SCHEME ?= rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = TGRestore

TGRestore_FILES = \
    src/TGRestore.m \
    src/TGRestoreStore.m \
    src/TGRestoreOverlay.m \
    src/TGRestoreHooks.m \
    src/TGRestoreViewer.m \
    src/Tweak.xm

TGRestore_CFLAGS = -fobjc-arc -O2 -Wno-partial-implementation -Wno-protocol-method-implementation
TGRestore_FRAMEWORKS = UIKit Foundation
TGRestore_PRIVATE_FRAMEWORKS = UIKit

include $(THEOS_MAKE_PATH)/tweak.mk
