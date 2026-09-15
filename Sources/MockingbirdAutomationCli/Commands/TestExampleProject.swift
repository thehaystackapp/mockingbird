import ArgumentParser
import MockingbirdAutomation
import MockingbirdCommon
import PathKit
import Foundation

extension Test {
  struct TestExampleProject: ParsableCommand {
    static var configuration = CommandConfiguration(
      commandName: "example",
      abstract: "Run an end-to-end example project test.",
      subcommands: [
        TestSpmProject.self,
        TestSpmPackage.self,
      ])
    
    enum ExampleProjectType: String, Codable, ExpressibleByArgument {
      case spmProject = "spm-project"
      case spmPackage = "spm-package"
    }
    
    static func applyLocallyBuiltCli(binPath: Path) throws {
      try? binPath.delete()
      try binPath.mkpath()
      let cliPath = try SwiftPackage.build(target: .product(name: "mockingbird"),
                                           configuration: .debug,
                                           package: Path("Package.swift"))
      try cliPath.copy(binPath + "mockingbird")
      let cliLibrariesPath = Path("Sources/MockingbirdCli/Resources/Libraries")
      try cliLibrariesPath.copy(binPath + cliLibrariesPath.lastComponent)
    }
    
    /// Package checkouts are named after the last component of the repository URL, so the local
    /// repository is exposed through a symlink with a stable name that matches the example projects.
    static func localRepositoryURL() throws -> String {
      let linkPath = Path("./.build/mockingbird/intermediates/mockingbird")
      try linkPath.parent().mkpath()
      try? linkPath.delete()
      try linkPath.symlink(Path.current.absolute())
      return "file://" + linkPath.absolute().string
    }
    
    static func backup(_ files: [Path], block: () throws -> Void) throws {
      try files.forEach({ try $0.backup() })
      defer { files.forEach({ try? $0.restore() }) }
      try block()
    }
    
    struct TestSpmProject: ParsableCommand {
      static var configuration = CommandConfiguration(
        commandName: "spm-project",
        abstract: "Test the SwiftPM example project.")
      func run() throws {
        try Simulator.performInSimulator { uuid in
          guard let uuid = uuid else {
            logError("Unable to create simulator")
            return
          }
          
          let srcroot = Path("Examples/SPMProjectExample")
          let projectPath = srcroot + "SPMProjectExample.xcodeproj"
          let pbxprojPath = projectPath + "project.pbxproj"
          let resolvedPath = projectPath + "project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
          try backup([pbxprojPath, resolvedPath]) {
            // Point to the local revision.
            let rev = try Git.getHEAD(repository: Path.current)
            let pbxprojContents = try pbxprojPath.read()
              .replacingOccurrences(of: #"repositoryURL = "[^"]+";"#,
                                    with: "repositoryURL = \(doubleQuoted: try localRepositoryURL());",
                                    options: [.regularExpression])
              .replacingOccurrences(of: #"requirement = \{\s*kind = upToNextMinorVersion;\s*minimumVersion = [\d\.]+;\s*\};"#,
                                    with: "requirement = { kind = revision; revision = \(rev); };",
                                    options: [.regularExpression])
            try pbxprojPath.delete()
            try pbxprojPath.write(pbxprojContents)
            try? resolvedPath.delete()
            
            // Pull and build the framework.
            let derivedDataPath = Path("./.build/mockingbird/intermediates/SPMProjectExample")
            try? derivedDataPath.delete()
            let environment = SwiftPackage.PackageConfiguration.libraries.getEnvironment()
            try XcodeBuild.resolvePackageDependencies(target: .scheme(name: "SPMProjectExample"),
                                                      project: .project(path: projectPath),
                                                      derivedDataPath: derivedDataPath,
                                                      environment: environment)
            
            // Inject the local binary.
            let binPath = derivedDataPath
              + "SourcePackages/checkouts/mockingbird/bin/\(mockingbirdVersion)"
            try applyLocallyBuiltCli(binPath: binPath)
            
            try XcodeBuild.test(target: .scheme(name: "SPMProjectExample"),
                                project: .project(path: projectPath),
                                destination: .iOSSimulator(deviceUUID: uuid),
                                derivedDataPath: derivedDataPath,
                                environment: environment)
          }
        }
      }
    }
    
    struct TestSpmPackage: ParsableCommand {
      static var configuration = CommandConfiguration(
        commandName: "spm-package",
        abstract: "Test the SwiftPM example package.")
      func run() throws {
        let srcroot = Path("Examples/SPMPackageExample")
        let packagePath = srcroot + "Package.swift"
        try backup([packagePath, srcroot + "Package.resolved"]) {
          // Point to the local revision.
          let rev = try Git.getHEAD(repository: Path.current)
          let packageContents = try packagePath.read()
            .replacingOccurrences(of: "https://github.com/thehaystackapp/mockingbird.git",
                                  with: try localRepositoryURL())
            .replacingOccurrences(of: #"\.upToNextMinor\(from: "[\d\.]+"\)"#,
                                  with: ".revision(\(doubleQuoted: rev))",
                                  options: [.regularExpression])
          try packagePath.delete()
          try packagePath.write(packageContents)
          
          // Pull and build the framework.
          try SwiftPackage.update(package: packagePath, packageConfiguration: .libraries)
          
          // Inject the local binary.
          let binPath = srcroot + ".build/checkouts/mockingbird/bin/\(mockingbirdVersion)"
          try applyLocallyBuiltCli(binPath: binPath)
          
          try Subprocess("./gen-mocks.sh", workingDirectory: packagePath.parent()).run()
          try SwiftPackage.test(packageConfiguration: .libraries, package: packagePath)
        }
      }
    }
  }
}
