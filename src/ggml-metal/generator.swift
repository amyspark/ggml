#!/usr/bin/env swift

//  compress.swift
//  Compress a file with Apple’s Compression framework and serialize
//  the result into a C array, together with its length and the
//  length of the original file.
//
//  Usage:
//      xcrun swift compress.swift <infile> <outfilebasename>
//
//  The script creates two files in the working directory:
//      <outfilebasename>.h   – exports declarations for the C array and the lengths
//      <outfilebasename>.c   – serialized C array
//
//  The current compression algorithm is LZMA. Make sure to update
//  ggml-metal-device.m accordingly if you change it.

import Foundation

func sanitizeForMacro(_ name: String) -> String {
    return name.map{ch in ch.isLetter || ch.isNumber ? ch.uppercased() : "_" }.joined()
}

func sanitizeForIdentifier(_ name: String) -> String {
    var result = name.map{ch in ch.isLetter || ch.isNumber ? String(ch) : "_" }.joined()
    if let first = result.first, first.isNumber {
        result = "_" + result
    }
    return result
}

guard CommandLine.arguments.count == 3 else {
    let exe = (CommandLine.arguments[0] as NSString).lastPathComponent
    fputs("Usage: \(exe) <infile> <outfilebasename>\n", stderr)
    exit(1)
}

let infile  = CommandLine.arguments[1]
let outfile = CommandLine.arguments[2]

let inputURL = URL(fileURLWithPath: infile)
guard let originalData = try? Data(contentsOf: inputURL) else {
    fputs("Error: Cannot read input file '\(infile)'.\n", stderr)
    exit(1)
}

let srcSize = originalData.count
let compressedData: NSData;
do {
    compressedData = try (originalData as NSData).compressed(using: .lzma)
} catch {
    fputs("Error: compression failed: \(error)\n", stderr)
    exit(1)
}
let compressedSize = compressedData.count

let macroName      = sanitizeForMacro(outfile) + "_H"
let identifierBase = sanitizeForIdentifier(outfile)
let headerName     = "\(outfile).h"
let sourceName     = "\(outfile).c"

let headerContent  = """
#ifndef \(macroName)
#define \(macroName)

#include <stddef.h>
#include <stdint.h>

extern const uint8_t \(identifierBase)_data[];
extern const size_t \(identifierBase)_data_len;
extern const size_t \(identifierBase)_orig_len;

#endif // \(macroName)

"""

let byteStrings  = compressedData.map { String(format: "0x%02x", UInt($0)) }
let bytesPerLine = 16
var arrayLines: [String]   = []

for i in stride(from: 0, to: byteStrings.count, by: bytesPerLine) {
    let end = min(i + bytesPerLine, byteStrings.count)
    let line = byteStrings[i..<end].joined(separator: ", ")
    arrayLines.append("    \(line),")
}

let arrayBody = arrayLines.joined(separator: "\n")

let sourceContent = """
#include "\(outfile).h"

const uint8_t \(identifierBase)_data[] = {
\(arrayBody)
};

const size_t \(identifierBase)_data_len = \(compressedSize);
const size_t \(identifierBase)_orig_len = \(srcSize);

"""

let headerURL = URL(fileURLWithPath: headerName)
let sourceURL = URL(fileURLWithPath: sourceName)

do {
    try headerContent.write(to: headerURL, atomically: true, encoding: .utf8)
    try sourceContent.write(to: sourceURL, atomically: true, encoding: .utf8)
    print("Generated \(headerURL.path) and \(sourceURL.path)")
} catch {
    fputs("Error writing output files: \(error)\n", stderr)
    exit(1)
}
