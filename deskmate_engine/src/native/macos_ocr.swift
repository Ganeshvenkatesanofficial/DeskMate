// macos_ocr — Apple Vision text recognition for DeskMate's Folder Agent.
//
// Usage: macos_ocr <image-path>
// Prints the recognised text lines as a JSON array of strings ("[]" when the
// image can't be read or holds no text). Used by knowledge/ocr.py
// to make screenshots, scans and photos of documents searchable on-device.
//
// Build: swiftc -O native/macos_ocr.swift -o bin/macos_ocr

import AppKit
import Foundation
import Vision

func emit(_ lines: [String]) {
    let data = (try? JSONSerialization.data(withJSONObject: lines)) ?? Data("[]".utf8)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
}

guard CommandLine.arguments.count > 1 else {
    emit([])
    exit(0)
}

let url = URL(fileURLWithPath: CommandLine.arguments[1])
guard let image = NSImage(contentsOf: url),
      let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    emit([])
    exit(0)
}

let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.usesLanguageCorrection = true

let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
do {
    try handler.perform([request])
} catch {
    emit([])
    exit(0)
}

let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
emit(lines)
