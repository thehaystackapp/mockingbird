import Foundation
import ArgumentParser

@main
struct Automation: ParsableCommand {
  static var configuration = CommandConfiguration(
    abstract: "Task runner for Mockingbird.",
    subcommands: [
      Build.self,
      Test.self,
      Configure.self,
    ])
}
