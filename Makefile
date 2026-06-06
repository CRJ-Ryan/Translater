.PHONY: build clean run app debug

APP_NAME = Translater
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

app: build
	mkdir -p $(APP_NAME).app/Contents/MacOS
	mkdir -p $(APP_NAME).app/Contents/Resources
	cp $(APP_NAME) $(APP_NAME).app/Contents/MacOS/
	cp Resources/Info.plist $(APP_NAME).app/Contents/Info.plist 2>/dev/null || true
	cp Resources/AppIcon.icns $(APP_NAME).app/Contents/Resources/ 2>/dev/null || true
