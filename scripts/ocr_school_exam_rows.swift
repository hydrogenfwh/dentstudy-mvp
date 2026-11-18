// Recover small examination-year annotations using local horizontal-strip OCR.
// No image, source text, identity, or filesystem path is printed.
// swift script.swift input.pdf hires-json-dir private-row-output-dir pagesCSV
import Foundation
import AppKit
import PDFKit
import Vision

let args = CommandLine.arguments
guard args.count == 5,
      let pdf = PDFDocument(url: URL(fileURLWithPath: args[1])) else {
    fatalError("input.pdf hires-json-dir private-row-output-dir pagesCSV required")
}
let output = URL(fileURLWithPath: args[3], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true,
                                       attributes: [.posixPermissions: 0o700])
for number in args[4].split(separator: ",").compactMap({ Int($0) }) {
    try autoreleasepool {
        let target = output.appendingPathComponent(String(format: "rows-%03d.json", number))
        if FileManager.default.fileExists(atPath: target.path) { return }
        let rawURL = URL(fileURLWithPath: args[2]).appendingPathComponent(String(format: "ocr-%03d.json", number))
        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: rawURL)) as! [String: Any]
        let lines = raw["lines"] as! [[String: Any]]
        let thumbnail = pdf.page(at: number - 1)!.thumbnail(of: NSSize(width: 3400, height: 4828), for: .mediaBox)
        let image = thumbnail.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        var groups: [[String: Any]] = []
        for line in lines.sorted(by: { ($0["y"] as! Double) > ($1["y"] as! Double) }) {
            let text = line["text"] as! String
            let y = line["y"] as! Double
            let h = line["h"] as! Double
            let x = line["x"] as! Double
            let w = line["w"] as! Double
            // Only question lines, not headers, personal commentary or footers.
            guard y > 0.10, text.contains("【") || text.contains("［"),
                  !text.contains("2026】"), !text.contains("总结") else { continue }
            if groups.contains(where: { abs(($0["y"] as! Double) - y) < 0.006 }) { continue }
            let top = min(1.0, y + h + 0.002)
            let bottom = max(0.0, y - 0.002)
            // Strip to the right of the recognized subject tag: this prevents
            // answer content or another row's year being used as evidence.
            let left = max(0.10, min(0.30, x))
            let rectangle = CGRect(x: Double(image.width) * left,
                                   y: Double(image.height) * (1 - top),
                                   width: Double(image.width) * (0.92 - left),
                                   height: Double(image.height) * (top - bottom)).integral
            guard let crop = image.cropping(to: rectangle) else { continue }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["zh-Hans", "en-US"]
            request.usesLanguageCorrection = false
            try VNImageRequestHandler(cgImage: crop, options: [:]).perform([request])
            let recovered = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
            groups.append(["y": y, "h": h, "x": x, "w": w,
                           "original": text, "text": recovered])
        }
        let data = try JSONSerialization.data(withJSONObject: ["page": number, "rows": groups], options: [.prettyPrinted, .sortedKeys])
        try data.write(to: target, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
        print("Year strip review complete: page \(number), \(groups.count) rows")
        fflush(stdout)
    }
}
