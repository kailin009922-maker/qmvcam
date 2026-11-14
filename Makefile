export TARGET = iphone:clang:16.5:16.0
export ARCHS = arm64 arm64e
export ADDITIONAL_OBJCFLAGS = -fobjc-arc
INSTALL_TARGET_PROCESSES = SpringBoard mediaserverd

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = qmvcam
qmvcam_FILES = $(wildcard src/*.m)
qmvcam_CFLAGS = -I src -I src/shim -Wno-unused-variable -Wno-deprecated-declarations \
                -Wno-nullability-completeness -Wno-objc-method-access
qmvcam_FRAMEWORKS = Foundation UIKit AVFoundation CoreMedia CoreVideo VideoToolbox \
                    CoreImage Metal QuartzCore IOSurface Security IOKit Vision \
                    Accelerate PhotosUI ImageIO CoreGraphics
qmvcam_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk
