import CoreImage
import UIKit

enum ShareArtwork {
    static let size = CGSize(width: 1080, height: 1350)

    private struct Line {
        let content: NSAttributedString
        let height: CGFloat
        let top: CGFloat
    }

    static func render(card: Card, milestone: Bool, destination: URL, isStore: Bool,
                       bundle: Bundle = L.bundle) -> UIImage? {
        guard let qr = qrImage(destination, side: 180) else { return nil }
        let ink = UIColor(red: 31/255, green: 35/255, blue: 38/255, alpha: 1)
        let accentText = UIColor(red: 36/255, green: 93/255, blue: 143/255, alpha: 1)
        let paper = UIColor(red: 246/255, green: 244/255, blue: 238/255, alpha: 1)
        let tint = UIColor(red: 229/255, green: 239/255, blue: 249/255, alpha: 1)
        let inset: CGFloat = 72
        let width = size.width - 2 * inset
        let footerY: CGFloat = 1040

        func text(_ key: String) -> String { L.t(key, bundle: bundle) }
        let reference = SourceID.allCases.filter { card.sourceRefs.contains($0) }
            .map { text($0.name) }.joined(separator: " · ")
        let title = text(milestone ? "card.checked" : card.title)

        func layout(bodySize: CGFloat) -> [Line] {
            var lines: [Line] = []
            var top: CGFloat = 70

            func add(_ value: String, size: CGFloat, weight: UIFont.Weight, color: UIColor,
                     gap: CGFloat) {
                let style = NSMutableParagraphStyle()
                style.lineBreakMode = .byWordWrapping
                let content = NSAttributedString(string: value, attributes: [
                    .font: UIFont.systemFont(ofSize: size, weight: weight),
                    .foregroundColor: color,
                    .paragraphStyle: style
                ])
                let height = ceil(content.boundingRect(
                    with: CGSize(width: width, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil
                ).height) + 2
                lines.append(Line(content: content, height: height, top: top))
                top += height + gap
            }

            add(text("app.name"), size: 31, weight: .semibold, color: accentText, gap: 19)
            add(card.selection.label(bundle: bundle), size: 35, weight: .semibold, color: accentText, gap: 18)
            add(title, size: 61, weight: .bold, color: ink, gap: 42)
            add(text("card.first"), size: 33, weight: .bold, color: accentText, gap: 12)
            add(card.firstSteps.map(text).joined(separator: "\n"), size: bodySize, weight: .regular,
                color: ink, gap: 28)
            add(text("card.stop"), size: 33, weight: .bold, color: accentText, gap: 12)
            add(card.stops.map(text).joined(separator: "\n"), size: bodySize, weight: .regular,
                color: ink, gap: 26)
            add(reference, size: 29, weight: .medium, color: accentText, gap: 0)
            return lines
        }

        let lines = stride(from: 41, through: 28, by: -1)
            .map { CGFloat($0) }
            .lazy.map { layout(bodySize: $0) }
            .first { ($0.last.map { $0.top + $0.height } ?? 0) <= footerY - 28 }
        guard let lines else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            paper.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            for line in lines {
                line.content.draw(with: CGRect(x: inset, y: line.top, width: width, height: line.height),
                                  options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
            }

            tint.setFill()
            context.fill(CGRect(x: 0, y: footerY, width: size.width, height: size.height - footerY))
            let footerWidth = width - 222
            let caption = text(isStore ? "share.qr.store" : "share.qr.support")
            draw(text("share.hashtags"), at: CGPoint(x: inset, y: 1090), width: footerWidth,
                 size: 35, weight: .bold, color: accentText)
            draw(card.selection.code, at: CGPoint(x: inset, y: 1188), width: footerWidth,
                 size: 35, weight: .semibold, color: ink)
            let qrX = size.width - inset - 180
            qr.draw(in: CGRect(x: qrX, y: 1074, width: 180, height: 180))
            draw(caption, at: CGPoint(x: qrX - 10, y: 1264), width: 200,
                 size: 24, weight: .medium, color: accentText, alignment: .center)
        }
    }

    static func qrImage(_ url: URL, side: Int) -> UIImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(url.absoluteString.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let width = Int(output.extent.width)
        let scale = side / (width + 8)
        guard scale > 0 else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: CGFloat(scale), y: CGFloat(scale)))
        guard let code = CIContext(options: [.useSoftwareRenderer: true])
            .createCGImage(scaled, from: scaled.extent) else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let dimension = CGFloat(side)
        let offset = CGFloat((side - width * scale) / 2)
        return UIGraphicsImageRenderer(size: CGSize(width: dimension, height: dimension),
                                       format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: dimension, height: dimension))
            context.cgContext.interpolationQuality = .none
            UIImage(cgImage: code).draw(in: CGRect(x: offset, y: offset,
                                                  width: CGFloat(code.width), height: CGFloat(code.height)))
        }
    }

    private static func draw(_ value: String, at point: CGPoint, width: CGFloat, size: CGFloat,
                             weight: UIFont.Weight, color: UIColor, alignment: NSTextAlignment = .left) {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        (value as NSString).draw(with: CGRect(x: point.x, y: point.y, width: width, height: 90),
                                 options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [
                                    .font: UIFont.systemFont(ofSize: size, weight: weight),
                                    .foregroundColor: color, .paragraphStyle: style
                                 ], context: nil)
    }
}

enum ShareFile {
    static func write(_ data: Data, name: String, in base: URL = FileManager.default.temporaryDirectory) throws -> URL {
        let directory = base.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            remove(url)
            throw error
        }
    }

    static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}
