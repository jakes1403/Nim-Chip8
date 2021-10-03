# Package

version       = "0.1.0"
author        = "jakes1403"
description   = "Another chip 8 emulator"
license       = "MIT"
srcDir        = "src"
bin           = @["chip8"]


# Dependencies

requires "nim >= 1.4.8"

requires "nimgl >= 1.0.0"

requires "glm"