# Chip 8 emulator by jakes1403

import streams
import strutils
import bitops
import endians

import nimgl/[glfw, opengl]

import glm

type address = uint16
type instruction = uint16

var memory: array[4096, byte]

var display: array[(64 * 32) div 8, GLubyte]

var PC: address

var I: address

var stack: array[16, address]
var stackPointer = 0

var registers: array[16, uint8]

const font = [
    byte 0xF0, 0x90, 0x90, 0x90, 0xF0, # 0
    byte 0x20, 0x60, 0x20, 0x20, 0x70, # 1
    byte 0xF0, 0x10, 0xF0, 0x80, 0xF0, # 2
    byte 0xF0, 0x10, 0xF0, 0x10, 0xF0, # 3
    byte 0x90, 0x90, 0xF0, 0x10, 0x10, # 4
    byte 0xF0, 0x80, 0xF0, 0x10, 0xF0, # 5
    byte 0xF0, 0x80, 0xF0, 0x90, 0xF0, # 6
    byte 0xF0, 0x10, 0x20, 0x40, 0x40, # 7
    byte 0xF0, 0x90, 0xF0, 0x90, 0xF0, # 8
    byte 0xF0, 0x90, 0xF0, 0x10, 0xF0, # 9
    byte 0xF0, 0x90, 0xF0, 0x90, 0x90, # A
    byte 0xE0, 0x90, 0xE0, 0x90, 0xE0, # B
    byte 0xF0, 0x80, 0x80, 0x80, 0xF0, # C
    byte 0xE0, 0x90, 0x90, 0x90, 0xE0, # D
    byte 0xF0, 0x80, 0xF0, 0x80, 0xF0, # E
    byte 0xF0, 0x80, 0xF0, 0x80, 0x80  # F
]

proc copyFontToMemory(startAddress: address) =
    var a: address = 0
    while a < font.len:
        memory[startAddress + a] = font[a]
        a += 1

proc copyProgToMemory(path: string, startAddress: address) =
    var p = newFileStream(path, mode = fmRead)
    var a: address = 0
    while not p.atEnd():
        let character = p.readChar()
        memory[startAddress + a] = byte(character)
        a += 1
    defer: p.close()

proc printMemory(fromAddr: address, toAddr: address, notZero: bool = true) =
    echo "Memory printout:"
    for a in countup(fromAddr, toAddr):
        if memory[a] != 0 or not notZero:
            echo "\t$1: $2" % [toHex(a), toHex(memory[a])]

proc keyProc(window: GLFWWindow, key: int32, scancode: int32,
             action: int32, mods: int32): void {.cdecl.} =
  if key == GLFWKey.ESCAPE and action == GLFWPress:
    window.setWindowShouldClose(true)

assert glfwInit()

glfwWindowHint(GLFWContextVersionMajor, 3)
glfwWindowHint(GLFWContextVersionMinor, 3)
glfwWindowHint(GLFWOpenglForwardCompat, GLFW_TRUE) # Used for Mac
glfwWindowHint(GLFWOpenglProfile, GLFW_OPENGL_CORE_PROFILE)
glfwWindowHint(GLFWResizable, GLFW_FALSE)

let w: GLFWWindow = glfwCreateWindow(1200, 600, "NimGL")

if w == nil:
    quit(-1)

discard w.setKeyCallback(keyProc)
w.makeContextCurrent()

assert glInit()

copyFontToMemory(0x50)

copyProgToMemory("prog/IBM Logo.ch8", 0x200)

printMemory(0, 4095)

PC = 0x200

var vertices = @[
    -1.0f, 1.0f,
    1.0f, 1.0f,
    -1.0f, -1.0f,
    1.0f, -1.0f
]

var indices = @[
    uint32 0, uint32 1, uint32 2,
    uint32 2, uint32 3, uint32 1
]

var vbo: uint32
var ebo: uint32
var vao: uint32

glGenBuffers(1, vbo.addr)
glGenBuffers(1, ebo.addr)
glGenVertexArrays(1, vao.addr)

glBindVertexArray(vao)
glBindBuffer(GL_ARRAY_BUFFER, vbo)
glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ebo)

glBufferData(GL_ARRAY_BUFFER, cint(cfloat.sizeof * vertices.len), vertices[0].addr, GL_STATIC_DRAW)
glBufferData(GL_ELEMENT_ARRAY_BUFFER, cint(cuint.sizeof * indices.len), indices[0].addr, GL_STATIC_DRAW)

glEnableVertexAttribArray(0)
glVertexAttribPointer(0'u32, 2, EGL_FLOAT, false, cfloat.sizeof * 2, nil)

glEnableVertexAttribArray(1)
glVertexAttribPointer(1'u32, 2, EGL_FLOAT, false, cfloat.sizeof * 2, nil)

var vertexShader = glCreateShader(GL_VERTEX_SHADER)
var vertexSource: cstring = """
#version 330 core
layout (location = 0) in vec2 aPos;
layout (location = 1) in vec2 tPos;
out vec2 texCord;
uniform mat4 matrix;
uniform mat4 sMatrix;
void main() {
  gl_Position = vec4(aPos, 0.0, 1.0) * matrix * sMatrix;
  texCord = tPos;
}
"""

glShaderSource(vertexShader, 1'i32,  vertexSource.addr, nil)
glCompileShader(vertexShader)

var fragmentShader = glCreateShader(GL_FRAGMENT_SHADER)
var fragmentSource: cstring = """
#version 330 core
out vec4 FragColor;
in vec2 texCord;
uniform sampler2D tex;
void main() {
  FragColor = vec4(0.5, 0.6, 0.3, 1.0f);
}
"""
glShaderSource(fragmentShader, 1, fragmentSource.addr, nil)
glCompileShader(fragmentShader)

var shaderProgram = glCreateProgram()
glAttachShader(shaderProgram, vertexShader)
glAttachShader(shaderProgram, fragmentShader)
glLinkProgram(shaderProgram)

var
    log_length: int32
    message = newSeq[char](1024)
    pLinked: int32
glGetProgramiv(shaderProgram, GL_LINK_STATUS, pLinked.addr);
if pLinked != GL_TRUE.ord:
    glGetProgramInfoLog(shaderProgram, 1024, log_length.addr, message[0].addr);
    echo message

var matrix = ortho(0f, 64f, 32f, 0f, -1f, 1f)
var sMatrix = mat4(1.0f)

let matLoc = glGetUniformLocation(shaderProgram, "matrix")
let sMatLoc = glGetUniformLocation(shaderProgram, "sMatrix")

let texLoc = glGetUniformLocation(shaderProgram, "tex")
glUniform1i(texLoc, 0)

while not w.windowShouldClose() and PC < 4096:
    glfwPollEvents()
    var ins: instruction = 0x7FFF
    bigEndian16(addr ins, addr memory[PC])
    PC += 2
    #echo toHex(ins.bitsliced(12 .. 15))
    case ins.bitsliced(12 .. 15):
        of 0x0:
            if ins.bitsliced(0 .. 11) == 0x0E0:
                echo "CLS"
                glClearColor(0f, 0f, 0f, 1f)
                glClear(GL_COLOR_BUFFER_BIT)
        of 0x1: # done
            #echo "JMP " & toHex(ins.bitsliced(0 .. 11))
            let jmpTo = ins.bitsliced(0 .. 11)
            PC = jmpTo
        of 0x6: # done
            echo "SET REGISTER " & toHex(ins.bitsliced(8 .. 11)) & " TO " & toHex(ins.bitsliced(0 .. 7))
            let register = ins.bitsliced(8 .. 11)
            let val = ins.bitsliced(0 .. 7)
            registers[register] = uint8(val)
        of 0x7: # done
            echo "ADD REGISTER " & toHex(ins.bitsliced(8 .. 11)) & " WITH " & toHex(ins.bitsliced(0 .. 7))
            let register = ins.bitsliced(8 .. 11)
            let val = ins.bitsliced(0 .. 7)
            registers[register] += uint8(val)
        of 0xA: # done
            echo "SET I TO " & toHex(ins.bitsliced(0 .. 11))
            I = ins.bitsliced(0 .. 11)
        of 0xD:
            glUseProgram(shaderProgram)
            glUniformMatrix4fv(matLoc, 1, false, matrix.caddr)
            let x = registers[ins.bitsliced(8 .. 11)] mod 64
            let y = registers[ins.bitsliced(4 .. 7)] mod 32
            let n = ins.bitsliced(0 .. 3)
            echo "DRAW AT X:" & toHex(x) & " Y: " & toHex(y) & " AT LOCATION: " & toHex(I) & " AND " & toHex(n) & " TALL"
            for b in countup(I, (I + n) - 1):
                for c in countup(0, 7):
                    if memory[b].testbit(c):
                        sMatrix = mat4(1.0f)
                        sMatrix = translate(sMatrix, float(x), float(y), 0f)
                        glUniformMatrix4fv(sMatLoc, 1, false, sMatrix.caddr)
                        glBindVertexArray(vao)
                        glDrawElements(GL_TRIANGLES, indices.len.cint, GL_UNSIGNED_INT, nil)
                    else:
                        stdout.write(" ")
                stdout.write("\n")

            w.swapBuffers()
        else:
            echo "Unhandled instruction!"

w.destroyWindow()
glfwTerminate()