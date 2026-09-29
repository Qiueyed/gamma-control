#!/usr/bin/env swift

import CoreGraphics
import Foundation

let display = CGMainDisplayID()
var current: Float = 0.45

func restore() { CGDisplayRestoreColorSyncSettings() }
signal(SIGINT) { _ in restore(); exit(0) }
signal(SIGTERM) { _ in restore(); exit(0) }

func apply(_ g: Float) {
    current = g
    CGSetDisplayTransferByFormula(display, 0, 1, g, 0, 1, g, 0, 1, g)
}

apply(0.45)
print("Gamma \(current). Type a number (0-1), d=default(0.45), q=quit")

while true {
    print("> ", terminator: "")
    fflush(stdout)
    guard let line = readLine()?.lowercased() else { continue }
    if line == "q" { break }
    if line == "d" || line == "default" { apply(0.45); print("0.45"); continue }
    if let val = Float(line), val >= 0 { apply(val); print(String(format: "%.2f", val)); continue }
    print("?")
}

restore()
print("Restored")
