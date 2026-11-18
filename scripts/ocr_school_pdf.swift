// Local-only PDF OCR. Raw results must stay outside public/release assets.
// Usage: swift ocr_school_pdf.swift input.pdf private-output-dir [workers] [start] [end] [width] [pagesCSV]
import Foundation
import AppKit
import PDFKit
import Vision

let args = CommandLine.arguments
guard args.count >= 3 else { fatalError("input.pdf private-output-dir required") }
guard let document = PDFDocument(url: URL(fileURLWithPath: args[1])) else {
    fatalError("Cannot open PDF")
}
let output = URL(fileURLWithPath: args[2], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true,
                                       attributes: [.posixPermissions: 0o700])
try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: output.path)
let workers = min(4, max(1, args.count > 3 ? Int(args[3]) ?? 2 : 2))
let first = max(1, args.count > 4 ? Int(args[4]) ?? 1 : 1)
let last = min(document.pageCount, args.count > 5 ? Int(args[5]) ?? document.pageCount : document.pageCount)
let width = min(4500, max(1200, args.count > 6 ? Int(args[6]) ?? 1800 : 1800))
let selected: Set<Int>? = args.count > 7 ? Set(args[7].split(separator: ",").compactMap { Int($0) }) : nil
let renderLock = NSLock()
let counterLock = NSLock()
var completed = 0
let queue = OperationQueue()
queue.maxConcurrentOperationCount = workers
print("Local OCR: \(document.pageCount) pages, range \(first)-\(last), workers \(workers)")
fflush(stdout)
for number in first...last {
    if let selected = selected, !selected.contains(number) { continue }
    let target = output.appendingPathComponent(String(format: "ocr-%03d.json", number))
    if FileManager.default.fileExists(atPath: target.path) { continue }
    queue.addOperation {
        autoreleasepool {
            do {
                renderLock.lock()
                let image: CGImage?
                if let page = document.page(at: number - 1) {
                    let thumbnail = page.thumbnail(of: NSSize(width: width, height: width * 142 / 100), for: .mediaBox)
                    image = thumbnail.cgImage(forProposedRect: nil, context: nil, hints: nil)
                } else { image = nil }
                renderLock.unlock()
                guard let image = image else { throw NSError(domain: "render", code: number) }
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.recognitionLanguages = ["zh-Hans", "en-US"]
                request.usesLanguageCorrection = true
                request.customWords = ["温州医科大学", "温州医学院", "口腔", "牙髓", "釉质", "牙本质", "颌面", "根尖周", "牙合"]
                try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
                let lines: [[String: Any]] = (request.results ?? []).compactMap { observation in
                    guard let candidate = observation.topCandidates(1).first else { return nil }
                    let b = observation.boundingBox
                    return ["text": candidate.string, "confidence": Double(candidate.confidence),
                            "x": Double(b.minX), "y": Double(b.minY),
                            "w": Double(b.width), "h": Double(b.height)]
                }
                let record: [String: Any] = ["page": number, "lines": lines,
                                             "text": lines.compactMap { $0["text"] as? String }.joined(separator: "\n")]
                let data = try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys])
                try data.write(to: target, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
                counterLock.lock()
                completed += 1
                let count = completed
                counterLock.unlock()
                if count % 10 == 0 || number == last {
                    print("Completed \(count) new pages; last page \(number)")
                    fflush(stdout)
                }
            } catch {
                // Do not print document text, identities, or image data.
                print("OCR failed on page \(number): \(type(of: error))")
                fflush(stdout)
            }
        }
    }
}
queue.waitUntilAllOperationsAreFinished()
print("OCR batch complete")
