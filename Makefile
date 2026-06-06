.PHONY: build clean run app debug install

APP_NAME = Translater
BUNDLE = $(APP_NAME).app
SOURCES = Sources/Translater/*.swift
FRAMEWORKS = -framework AppKit -framework CoreGraphics -framework ApplicationServices -framework Translation
SWIFTC = swiftc
FLAGS = -O

build:
	$(SWIFTC) $(FLAGS) -o $(APP_NAME) $(SOURCES) $(FRAMEWORKS)

debug:
	$(SWIFTC) -o $(APP_NAME) $(SOURCES) $(FRAMEWORKS)

run: build
	pkill -f $(APP_NAME) 2>/dev/null || true
	./$(APP_NAME) &

clean:
	rm -f $(APP_NAME)
	rm -rf $(BUNDLE)

# Build .app bundle with ad-hoc signing
app: build
	rm -rf $(BUNDLE)
	mkdir -p $(BUNDLE)/Contents/MacOS
	mkdir -p $(BUNDLE)/Contents/Resources
	cp $(APP_NAME) $(BUNDLE)/Contents/MacOS/
	cp Resources/Info.plist $(BUNDLE)/Contents/Info.plist
	cp Resources/AppIcon.icns $(BUNDLE)/Contents/Resources/
	# Ad-hoc code signing
	codesign --force --deep --sign - $(BUNDLE) 2>/dev/null || true
	@echo ""
	@echo "✅ $(BUNDLE) 已生成"
	@echo "   拖入 /Applications 即可安装"
	@echo "   双击运行或执行:  open $(BUNDLE)"

# Install to /Applications
install: app
	cp -R $(BUNDLE) /Applications/
	@echo "✅ 已安装到 /Applications/$(BUNDLE)"
