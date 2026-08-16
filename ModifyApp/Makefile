TARGET := iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = ModifyApp
ARCHS = arm64 arm64e
DEBUG = 0
FINALPACKAGE = 1

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = ModifyApp

ModifyApp_FILES = $(wildcard ModifyApp/*.m ModifyApp/*.c)
ModifyApp_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
ModifyApp_LDFLAGS = -lz -lsqlite3
ModifyApp_CODESIGN_FLAGS = -SModifyApp/ent.plist

include $(THEOS_MAKE_PATH)/application.mk

after-stage::
	$(FAKEROOT) chmod 4755 $(THEOS_STAGING_DIR)/Applications/ModifyApp.app/ModifyApp
