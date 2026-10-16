import CryptoKit
import Foundation
import ImageIO

enum VerificationError: Error { case failure(String) }

func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

func imagePixels(_ url: URL, width: Int, height: Int, depth: Int = 8) throws -> Data {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
          let provider = image.dataProvider, let providerBytes = provider.data else {
        throw VerificationError.failure("ImageIO could not decode \(url.path)")
    }
    guard image.width == width && image.height == height,
          image.bitsPerPixel == depth * 4 && image.bitsPerComponent == depth,
          (depth == 8 ? image.bitmapInfo.rawValue < 8 : image.bitmapInfo.rawValue == 4099) else {
        throw VerificationError.failure("Unexpected native image layout: \(url.path)")
    }
    let bytes = providerBytes as Data
    var packed = Data()
    for row in 0..<height {
        let start = row * image.bytesPerRow
        packed.append(bytes[start..<(start + width * 4 * (depth / 8))])
    }
    if depth == 16 {
        for index in stride(from: 0, to: packed.count, by: 2) {
            packed.swapAt(index, index + 1)
        }
    }
    return packed
}

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1
               ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
let reconstruction = root.appendingPathComponent("reconstruction")
let manifestBytes = try Data(contentsOf: reconstruction.appendingPathComponent("assets/manifest.json"))
let manifest = try JSONSerialization.jsonObject(with: manifestBytes) as! [String: Any]
var count = 0
for asset in manifest["assets"] as! [[String: Any]] {
    guard let image = asset["image"] as? [String: Any] else { continue }
    let width = image["width"] as! Int
    let height = image["height"] as! Int
    let sourceURL = root.appendingPathComponent(asset["source"] as! String)
    let outputURL = reconstruction.appendingPathComponent(asset["output"] as! String)
    let sourcePixels = try imagePixels(sourceURL, width: width, height: height, depth: image["source_depth_bits"] as! Int)
    let outputPixels = try imagePixels(outputURL, width: width, height: height)
    guard sha256(sourcePixels) == (image["source_premultiplied_rgba_sha256"] ?? image["source_straight_rgba_sha256"]) as! String,
          sha256(outputPixels) == image["output_straight_rgba_sha256"] as! String else {
        throw VerificationError.failure("Native pixels disagree with manifest for \(sourceURL.lastPathComponent)")
    }
    count += 1
}
guard count == 85 else { throw VerificationError.failure("Expected 85 images") }
print("ImageIO independently decoded 84 original CgBI RGBA8 images, one original standard RGBA16 image, and all 85 converted PNGs; pixel hashes and dimensions match.")
