import CoreImage
import ImageIO
import UIKit
import XCTest

final class ShareArtworkTests: XCTestCase {
    func testThreeLanguagePNGsAtFullSizeAndWithoutPrivateMetadata() throws {
        let scenes: [(Care, Stain, Bool)] = [
            (.water, .coffee, false), (.either, .juice, false), (.water, .food, false),
            (.unknown, .food, false), (.solvent, .ink, false), (.vacuum, .other, false),
            (.vinyl, .juice, false), (.leather, .pet, false), (.unknown, .problem, false),
            (.water, .coffee, true)
        ]
        for language in ["en", "zh-Hans", "zh-Hant"] {
            let bundle = try localizedBundle(language)
            for (care, stain, milestone) in scenes {
                let selection = Selection(care: care, stain: stain)
                let card = CareRules.card(for: selection)
                let output = try XCTUnwrap(ShareArtwork.render(
                    card: card, milestone: milestone, destination: StoreLink.supportURL,
                    isStore: false, bundle: bundle), "\(language) \(selection.code)")
                let png = try XCTUnwrap(output.pngData())
                let source = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
                let metadata = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
                XCTAssertEqual(metadata[kCGImagePropertyPixelWidth as String] as? Int, 1080)
                XCTAssertEqual(metadata[kCGImagePropertyPixelHeight as String] as? Int, 1350)
                XCTAssertNil(metadata[kCGImagePropertyGPSDictionary as String])
                XCTAssertNil(metadata[kCGImagePropertyIPTCDictionary as String])
                let exif = metadata[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
                XCTAssertNil(exif[kCGImagePropertyExifDateTimeOriginal as String])
                XCTAssertNil(exif[kCGImagePropertyExifLensModel as String])
                let tiff = metadata[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
                XCTAssertNil(tiff[kCGImagePropertyTIFFMake as String])
                XCTAssertNil(tiff[kCGImagePropertyTIFFModel as String])
            }
        }
    }

    func testExportedQRCodeDecodesToSupportOrAppStore() throws {
        XCTAssertNil(StoreLink.appURL(id: ""))
        XCTAssertNil(StoreLink.appURL(id: "$(_UNRESOLVED_ID)"))
        XCTAssertNil(StoreLink.appURL(id: "12/test"))
        let appURL = try XCTUnwrap(StoreLink.appURL(id: "1234567890"))
        XCTAssertEqual(appURL.absoluteString, "https://apps.apple.com/app/id1234567890")
        let card = CareRules.card(for: Selection(care: .water, stain: .coffee))
        let detector = try XCTUnwrap(CIDetector(ofType: CIDetectorTypeQRCode,
                                              context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
        for url in [StoreLink.supportURL, appURL] {
            let output = try XCTUnwrap(ShareArtwork.render(card: card, milestone: true, destination: url,
                                                          isStore: url == appURL))
            let png = try XCTUnwrap(output.pngData())
            let image = try XCTUnwrap(CIImage(data: png))
            let messages = detector.features(in: image).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
            XCTAssertEqual(messages, [url.absoluteString])
        }
    }
}
