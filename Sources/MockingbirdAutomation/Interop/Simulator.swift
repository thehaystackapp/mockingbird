import Foundation
import MockingbirdCommon

public enum Simulator {
  public enum Platform: String {
    case iOS = "iOS"
    case tvOS = "tvOS"
    case watchOS = "watchOS"
  }
  
  public struct Runtime: Codable {
    public let bundlePath: String
    public let buildversion: String
    public let runtimeRoot: String
    public let identifier: String
    public let version: String
    public let isAvailable: Bool
    public let supportedDeviceTypes: [DeviceType]
    
    public struct DeviceType: Codable {
      public let bundlePath: String
      public let name: String
      public let identifier: String
      public let productFamily: ProductFamily
      
      public enum ProductFamily: String, Codable {
        case iPhone = "iPhone"
        case iPad = "iPad"
      }
    }
  }
  
  public static func listRuntimes(platform: Platform) throws -> [Runtime] {
    struct Response: Codable {
      let runtimes: [Runtime]
    }
    let (runtimes, _) = try Subprocess("xcrun", [
      "simctl", "list", "runtimes", "-j", platform.rawValue,
    ]).runWithDataOutput()
    let response = try JSONDecoder().decode(Response.self, from: runtimes)
    return response.runtimes
  }
  
  /// The iOS SDK version of the selected Xcode, which bounds the simulator runtimes it can use.
  public static func getSDKVersion(platform: Platform) throws -> Version {
    let sdk: String = {
      switch platform {
      case .iOS: return "iphonesimulator"
      case .tvOS: return "appletvsimulator"
      case .watchOS: return "watchsimulator"
      }
    }()
    let (stdout, _) = try Subprocess("xcrun", [
      "--sdk", sdk, "--show-sdk-version",
    ]).runWithStringOutput()
    return Version(shortString: stdout.trimmingCharacters(in: .whitespacesAndNewlines))
  }
  
  public static func createSimulator(name: String,
                                     runtime: Runtime,
                                     deviceType: Runtime.DeviceType) throws -> UUID? {
    let (stdout, _) = try Subprocess("xcrun", [
      "simctl", "create", name, deviceType.identifier, runtime.identifier,
    ]).runWithStringOutput()
    return UUID(uuidString: stdout.trimmingCharacters(in: .whitespacesAndNewlines))
  }
  
  public static func deleteSimulator(uuid: UUID) throws {
    try Subprocess("xcrun", [
      "simctl", "delete", uuid.uuidString,
    ]).run()
  }
  
  public static func performInSimulator(platform: Platform = .iOS,
                                        productFamily: Runtime.DeviceType.ProductFamily = .iPhone,
                                        block: (_ deviceUUID: UUID?) throws -> Void) throws {
    // Runtimes newer than the selected Xcode's SDK are listed but cannot be used as destinations.
    let sdkVersion = try getSDKVersion(platform: platform)
    let availableRuntimes = try listRuntimes(platform: platform)
      .filter({ $0.isAvailable && Version(shortString: $0.version) <= sdkVersion })
      .sorted(by: { Version(shortString: $0.version) > Version(shortString: $1.version) })
    guard let runtime = availableRuntimes.first,
          let deviceType = runtime.supportedDeviceTypes
            .first(where: { $0.productFamily == productFamily }),
          let uuid = try createSimulator(name: "Mockingbird \(productFamily.rawValue) Simulator",
                                         runtime: runtime,
                                         deviceType: deviceType)
    else {
      return try block(nil)
    }
    defer {
      try? deleteSimulator(uuid: uuid)
    }
    try block(uuid)
  }
}
