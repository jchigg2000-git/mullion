APP = Mullion

.PHONY: update
update:
	git pull
	xcodegen generate
	xcodebuild -project $(APP).xcodeproj -scheme $(APP) -configuration Release -derivedDataPath build -destination 'platform=macOS' build
	-pkill -x $(APP)
	rm -rf /Applications/$(APP).app
	cp -R build/Build/Products/Release/$(APP).app /Applications/
	open /Applications/$(APP).app
