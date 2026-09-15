import Foundation
import PathKit

public enum Otool {
  /// Runtime search paths recorded in the binary's `LC_RPATH` load commands, in order.
  public static func listRpaths(binary: Path) throws -> [String] {
    let (stdout, _) = try Subprocess("xcrun", [
      "otool", "-l", binary.string,
    ]).runWithStringOutput()
    
    var rpaths: [String] = []
    var isRpathCommand = false
    for line in stdout.split(separator: "\n") {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.hasPrefix("cmd ") {
        isRpathCommand = trimmed == "cmd LC_RPATH"
      } else if isRpathCommand, trimmed.hasPrefix("path ") {
        // Formatted as `path <rpath> (offset <n>)`.
        let path = trimmed.dropFirst("path ".count)
        if let range = path.range(of: " (offset ", options: .backwards) {
          rpaths.append(String(path[..<range.lowerBound]))
        } else {
          rpaths.append(String(path))
        }
      }
    }
    return rpaths
  }
}
