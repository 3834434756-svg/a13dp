.PHONY: all clean build_clean

all: Dopamine.ipa

Dopamine.ipa: build/Build/Products/Debug-iphoneos/Dopamine.app BlackApple/build/Build/Products/Debug-iphoneos/BlackApple.app
	@echo Ad-Hoc signing Dopamine
	xattr -rc build/Build/Products/Debug-iphoneos/Dopamine.app
	ldid -SDopamine/Dopamine.entitlements build/Build/Products/Debug-iphoneos/Dopamine.app/Dopamine
	ldid -s build/Build/Products/Debug-iphoneos/Dopamine.app
	@echo Ad-Hoc signing BlackApple
	xattr -rc BlackApple/build/Build/Products/Debug-iphoneos/BlackApple.app
	ldid -SBlackApple/BlackApple/BlackApple.entitlements BlackApple/build/Build/Products/Debug-iphoneos/BlackApple.app/BlackApple
	ldid -s BlackApple/build/Build/Products/Debug-iphoneos/BlackApple.app
	rm -rf Payload Dopamine.ipa
	mkdir Payload
	cp -r build/Build/Products/Debug-iphoneos/Dopamine.app Payload/Dopamine.app
	cp -r BlackApple/build/Build/Products/Debug-iphoneos/BlackApple.app Payload/BlackApple.app
	zip -Ar Dopamine.ipa Payload
	rm -rf Payload
	rm -rf Dopamine.tipa
	cp Dopamine.ipa Dopamine.tipa

ifeq ($(NIGHTLY), 1)
build/Build/Products/Debug-iphoneos/Dopamine.app: FORCE
	xcodebuild -scheme Dopamine -derivedDataPath build -destination 'generic/platform=iOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO GCC_PREPROCESSOR_DEFINITIONS='NIGHTLY=1 COMMIT_HASH=\"$(COMMIT_HASH)\"'
else
build/Build/Products/Debug-iphoneos/Dopamine.app: FORCE
	xcodebuild -scheme Dopamine -derivedDataPath build -destination 'generic/platform=iOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO
endif

BlackApple/build/Build/Products/Debug-iphoneos/BlackApple.app: FORCE
	xcodebuild -project BlackApple/BlackApple.xcodeproj -scheme BlackApple -derivedDataPath BlackApple/build -destination 'generic/platform=iOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO

clean:
	rm -rf build Payload Dopamine.ipa Dopamine.tipa
	rm -rf BlackApple/build

build_clean:
	rm -rf Payload build
	rm -rf BlackApple/build

FORCE: ;