// Crops and scales one screenshot for scripts/screenshots-to-log.sh (KEY-68, KEY-9).
// macOS only: ImageIO and Core Graphics, which ship with macOS; the workflow
// compiles it with the Xcode toolchain the job has selected.
//
//   screenshot-image <in> <out> <png|jpeg> <divisor>
//   screenshot-image rows <in> <out> <first row> <row count>
//
// The first form keeps the bottom 2/5 of the image (the keyboard region of a
// portrait iPhone screenshot), full width, then divides its width and height
// by <divisor> (1 keeps full resolution), and writes it as PNG, or as JPEG at
// quality 0.7. The second keeps <row count> rows from <first row> (0 is the
// top), full width, at full resolution, as PNG: half of a crop that is too big
// for one printing job (KEY-9).
//
// It prints one line: the crop's rows, the output's size and the source's
// colour space, as "rows <first> to <last> of <width>x<height>, <out width>x<out
// height>, colour space <name>". A full-resolution PNG is read back and its
// pixels compared with the crop's, as 8-bit RGBA in the source's colour space,
// so "lossless" is checked, not assumed. It fails, with a message, if it cannot
// read, crop, scale or write the image, if the image it wrote is not the size
// it meant, or if a full-resolution PNG's pixels differ from the crop's.
//
// Why not sips: on the runner's macOS 27.0.1 (KEY-68, run 44215231118),
// `sips --cropToHeightWidth h w --cropOffset y 0` exited 0 and left the image
// at its full size.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("screenshot-image: FAIL: \(message)\n".utf8))
    exit(1)
}

func image(at path: String) -> CGImage {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { fail("cannot read an image from \(path)") }
    return image
}

/// The image's pixels as 8-bit premultiplied RGBA in `space`, drawn without scaling.
func pixels(_ image: CGImage, in space: CGColorSpace) -> [UInt8] {
    let bytesPerRow = image.width * 4
    var buffer = [UInt8](repeating: 0, count: bytesPerRow * image.height)
    let drawn = buffer.withUnsafeMutableBytes { raw -> Bool in
        guard
            let context = CGContext(
                data: raw.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: bytesPerRow, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return false }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return true
    }
    guard drawn else { fail("cannot make a \(image.width)x\(image.height) bitmap to compare pixels") }
    return buffer
}

/// What the arguments ask for.
struct Request {
    var input: String
    var output: String
    var format: String
    var divisor: Int
    /// The rows to keep, or nil for the bottom 2/5.
    var rows: (first: Int, count: Int)?
}

func request(_ arguments: [String]) -> Request {
    if arguments.count == 6, arguments[1] == "rows" {
        guard let first = Int(arguments[4]), let count = Int(arguments[5]), first >= 0, count >= 1 else {
            fail("usage: screenshot-image rows <in> <out> <first row> <row count>")
        }
        return Request(input: arguments[2], output: arguments[3], format: "png", divisor: 1, rows: (first, count))
    }
    guard arguments.count == 5, let divisor = Int(arguments[4]), divisor >= 1 else {
        fail("usage: screenshot-image <in> <out> <png|jpeg> <divisor> | rows <in> <out> <first row> <row count>")
    }
    return Request(input: arguments[1], output: arguments[2], format: arguments[3], divisor: divisor, rows: nil)
}

let asked = request(CommandLine.arguments)
let (input, output, format, divisor, rows) = (asked.input, asked.output, asked.format, asked.divisor, asked.rows)
let type: UTType = {
    switch format {
    case "png": return .png
    case "jpeg": return .jpeg
    default: fail("the format must be png or jpeg, not \(format)")
    }
}()

let whole = image(at: input)
let cropHeight = rows?.count ?? whole.height * 2 / 5
let top = rows?.first ?? whole.height - cropHeight
guard top + cropHeight <= whole.height else {
    fail("rows \(top) to \(top + cropHeight - 1) are not all in \(input), which has \(whole.height)")
}
// CGImage.cropping(to:) takes the rectangle in the image's pixels, with the origin at the top left.
guard let cropped = whole.cropping(to: CGRect(x: 0, y: top, width: whole.width, height: cropHeight)),
    cropped.width == whole.width, cropped.height == cropHeight
else { fail("cannot crop rows \(top) to \(top + cropHeight - 1) of \(input)") }

var result = cropped
if divisor > 1 {
    let width = cropped.width / divisor
    let height = cropped.height / divisor
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { fail("cannot make a \(width)x\(height) bitmap") }
    context.interpolationQuality = .high
    context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))
    guard let scaled = context.makeImage() else { fail("cannot scale \(input)") }
    result = scaled
}

guard
    let destination = CGImageDestinationCreateWithURL(
        URL(fileURLWithPath: output) as CFURL, type.identifier as CFString, 1, nil)
else { fail("cannot write \(output)") }
let properties: [CFString: Any] = format == "jpeg" ? [kCGImageDestinationLossyCompressionQuality: 0.7] : [:]
CGImageDestinationAddImage(destination, result, properties as CFDictionary)
guard CGImageDestinationFinalize(destination) else { fail("cannot write \(output)") }

let written = image(at: output)
guard written.width == result.width, written.height == result.height else {
    fail("\(output) is \(written.width)x\(written.height), not \(result.width)x\(result.height)")
}
let spaceName = (whole.colorSpace?.name as String?) ?? "unnamed"
if format == "png", divisor == 1 {
    guard let space = whole.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) else {
        fail("no colour space to compare pixels in")
    }
    guard pixels(written, in: space) == pixels(cropped, in: space) else {
        fail("\(output) does not have the crop's pixels: it is not lossless")
    }
}
print(
    "rows \(top) to \(top + cropHeight - 1) of \(whole.width)x\(whole.height), \(written.width)x\(written.height),"
        + " colour space \(spaceName)")
