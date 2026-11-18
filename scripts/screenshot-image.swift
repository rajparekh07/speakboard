// Crops and scales one screenshot for scripts/screenshots-to-log.sh (KEY-68).
// macOS only: ImageIO and Core Graphics, which ship with macOS; the workflow
// compiles it with the Xcode toolchain the job has selected.
//
//   screenshot-image <in> <out> <png|jpeg> <divisor>
//
// It keeps the bottom 2/5 of the image (the keyboard region of a portrait
// iPhone screenshot), full width, then divides its width and height by
// <divisor> (1 keeps full resolution), and writes it as PNG, or as JPEG at
// quality 0.7. It prints one line: the crop's rows and the output's size, as
// "rows <first> to <last> of <width>x<height>, <out width>x<out height>". It
// fails, with a message, if it cannot read, crop, scale or write the image, or
// if the image it wrote is not the size it meant.
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

let arguments = CommandLine.arguments
guard arguments.count == 5, let divisor = Int(arguments[4]), divisor >= 1 else {
    fail("usage: screenshot-image <in> <out> <png|jpeg> <divisor>")
}
let (input, output, format) = (arguments[1], arguments[2], arguments[3])
let type: UTType = {
    switch format {
    case "png": return .png
    case "jpeg": return .jpeg
    default: fail("the format must be png or jpeg, not \(format)")
    }
}()

let whole = image(at: input)
let cropHeight = whole.height * 2 / 5
let top = whole.height - cropHeight
// CGImage.cropping(to:) takes the rectangle in the image's pixels, with the origin at the top left.
guard let cropped = whole.cropping(to: CGRect(x: 0, y: top, width: whole.width, height: cropHeight)),
    cropped.width == whole.width, cropped.height == cropHeight
else { fail("cannot crop rows \(top) to \(whole.height - 1) of \(input)") }

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
print("rows \(top) to \(whole.height - 1) of \(whole.width)x\(whole.height), \(written.width)x\(written.height)")
