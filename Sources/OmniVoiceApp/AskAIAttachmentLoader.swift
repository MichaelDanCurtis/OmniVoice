import Foundation
import PDFKit
import UniformTypeIdentifiers
import OmniVoiceCore

enum AskAIAttachmentLoader {
    static func attachment(for url: URL) -> AskAIContextAttachment {
        let title = url.lastPathComponent
        let type = UTType(filenameExtension: url.pathExtension)
        let mimeType = type?.preferredMIMEType ?? fallbackMIMEType(for: url)

        if type?.conforms(to: .image) == true || mimeType.hasPrefix("image/") {
            return imageAttachment(url: url, title: title, mimeType: mimeType)
        }

        if type?.conforms(to: .audio) == true || mimeType.hasPrefix("audio/") {
            return audioAttachment(url: url, title: title, mimeType: mimeType)
        }

        let text = extractedText(from: url, type: type)
        return AskAIContextAttachment(
            kind: .file,
            title: title,
            text: text,
            filePath: url.path,
            mimeType: mimeType
        )
    }

    private static func imageAttachment(url: URL, title: String, mimeType: String) -> AskAIContextAttachment {
        let dataURL: String?
        do {
            let data = try Data(contentsOf: url)
            dataURL = "data:\(mimeType);base64,\(data.base64EncodedString())"
        } catch {
            dataURL = nil
        }

        return AskAIContextAttachment(
            kind: .image,
            title: title,
            text: "Image attached: \(title)",
            filePath: url.path,
            mimeType: mimeType,
            dataURL: dataURL
        )
    }

    private static func audioAttachment(url: URL, title: String, mimeType: String) -> AskAIContextAttachment {
        let dataURL: String?
        do {
            let data = try Data(contentsOf: url)
            dataURL = "data:\(mimeType);base64,\(data.base64EncodedString())"
        } catch {
            dataURL = nil
        }

        return AskAIContextAttachment(
            kind: .audio,
            title: title,
            text: "Audio attached: \(title). This build can display and play the audio, but it does not transcribe audio attachments automatically.",
            filePath: url.path,
            mimeType: mimeType,
            dataURL: dataURL
        )
    }

    private static func extractedText(from url: URL, type: UTType?) -> String {
        if type?.conforms(to: .pdf) == true || url.pathExtension.caseInsensitiveCompare("pdf") == .orderedSame {
            return extractPDFText(from: url)
        }

        if url.pathExtension.caseInsensitiveCompare("docx") == .orderedSame {
            return extractDOCXText(from: url)
        }

        if let text = try? String(contentsOf: url, encoding: .utf8) {
            return text
        }

        if let data = try? Data(contentsOf: url),
           let text = String(data: data, encoding: .utf8) {
            return text
        }

        return "No readable text could be extracted from \(url.lastPathComponent)."
    }

    private static func extractPDFText(from url: URL) -> String {
        guard let document = PDFDocument(url: url) else {
            return "No readable text could be extracted from \(url.lastPathComponent)."
        }

        var pages: [String] = []
        for pageIndex in 0..<document.pageCount {
            guard let text = document.page(at: pageIndex)?.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else {
                continue
            }
            pages.append(text)
        }
        return pages.isEmpty ? "No readable text could be extracted from \(url.lastPathComponent)." : pages.joined(separator: "\n\n")
    }

    private static func extractDOCXText(from url: URL) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", url.path, "word/document.xml"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                return "No readable text could be extracted from \(url.lastPathComponent)."
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let xml = String(data: data, encoding: .utf8), !xml.isEmpty else {
                return "No readable text could be extracted from \(url.lastPathComponent)."
            }
            return stripXML(xml)
        } catch {
            return "No readable text could be extracted from \(url.lastPathComponent)."
        }
    }

    private static func stripXML(_ xml: String) -> String {
        var text = ""
        var inTag = false
        for character in xml {
            switch character {
            case "<":
                inTag = true
            case ">":
                inTag = false
                text.append(" ")
            default:
                if !inTag {
                    text.append(character)
                }
            }
        }
        return text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func fallbackMIMEType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "pdf":
            "application/pdf"
        case "md":
            "text/markdown"
        case "json":
            "application/json"
        case "csv":
            "text/csv"
        case "jpg", "jpeg":
            "image/jpeg"
        case "png":
            "image/png"
        case "gif":
            "image/gif"
        case "webp":
            "image/webp"
        case "wav":
            "audio/wav"
        case "mp3":
            "audio/mpeg"
        case "m4a":
            "audio/mp4"
        case "aac":
            "audio/aac"
        case "aiff", "aif":
            "audio/aiff"
        case "docx":
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        default:
            "application/octet-stream"
        }
    }
}
