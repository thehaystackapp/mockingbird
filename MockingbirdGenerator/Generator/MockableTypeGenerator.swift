//
//  MockGenerator.swift
//  MockingbirdCli
//
//  Created by Andrew Chang on 8/6/19.
//  Copyright © 2019 Bird Rides, Inc. All rights reserved.
//

// swiftlint:disable leading_whitespace

import Foundation

private enum Constants {
  /// A heuristic set of class prefixes used by system frameworks requiring NSObjectProtocol
  /// conformance. In the future, we want to mock Obj-C classes and system frameworks instead.
  static let objectProtocolPrefixes = Set(["NS", "CB", "UI"])
  static let mockProtocolName = "Mockingbird.Mock"
}

extension GenericType {
  var flattenedDeclaration: String {
    guard !inheritedTypes.isEmpty else { return name }
    let flattenedInheritedTypes = Array(inheritedTypes).joined(separator: " & ")
    return "\(name): \(flattenedInheritedTypes)"
  }
}

extension MockableType {
  func generate(moduleName: String) -> String {
    return """
    // MARK: - Mocked \(name)
    
    public final class \(name)Mock\(allSpecializedGenericTypes): \(allInheritedTypes)\(allGenericConstraints) {
    \(staticMockingContext)
      public let mockingContext = Mockingbird.MockingContext()
      public let stubbingContext = Mockingbird.StubbingContext()
      public let mockMetadata = Mockingbird.MockMetadata(["generator_version": "\(mockingbirdVersion.shortString)", "module_name": "\(moduleName)"])
      public var sourceLocation: Mockingbird.SourceLocation? {
        get { return stubbingContext.sourceLocation }
        set {
          stubbingContext.sourceLocation = newValue
          \(name)Mock.staticMock.stubbingContext.sourceLocation = newValue
        }
      }
    
    \(generateBody())
    }
    """
  }
  
  func generateInitializer(containingTypeNames: [String]) -> String {
    let initializers = [createInitializer(with: containingTypeNames)] + containedTypes.map({
      $0.generateInitializer(containingTypeNames: containingTypeNames + [name])
    })
    return initializers.joined(separator: "\n\n")
  }
  
  /// The static mocking context allows static (or class) declared methods to be mocked.
  var staticMockingContext: String {
    guard !genericTypes.isEmpty else { return "  static let staticMock = Mockingbird.StaticMock()" }
    // Since class-level generic types don't support static variables, we instead use a global
    // variable `genericTypesStaticMocks` that maps a runtime generated `staticMockIdentifier` to a
    // `StaticMock` instance.
    return """
      static var staticMock: Mockingbird.StaticMock {
        let runtimeGenericTypeNames = \(runtimeGenericTypeNames)
        let staticMockIdentifier = "\(name)Mock\(allSpecializedGenericTypes)," + runtimeGenericTypeNames
        if let staticMock = genericTypesStaticMocks.value[staticMockIdentifier] {
          return staticMock
        }
        let staticMock = Mockingbird.StaticMock()
        genericTypesStaticMocks.update { $0[staticMockIdentifier] = staticMock }
        return staticMock
      }
    """
  }
  
  var runtimeGenericTypeNames: String {
    let genericTypeSelfNames = genericTypes.map({ "\"\\(\($0.name).self)\"" }).joined(separator: ", ")
    return "[\(genericTypeSelfNames)].joined(separator: \",\")"
  }
  
  var allSpecializedGenericTypesList: [String] {
    return genericTypes.map({ $0.flattenedDeclaration })
  }
  
  var allSpecializedGenericTypes: String {
    guard !genericTypes.isEmpty else { return "" }
    return "<" + allSpecializedGenericTypesList.joined(separator: ", ") + ">"
  }
  
  var allGenericTypes: String {
    guard !genericTypes.isEmpty else { return "" }
    return "<" + genericTypes.map({ $0.name }).joined(separator: ", ") + ">"
  }
  
  var allGenericConstraints: String {
    guard !genericConstraints.isEmpty else { return "" }
    return " where " + genericConstraints.joined(separator: ", ")
  }
  
  var allInheritedTypes: String {
    return [subclass,
            inheritedProtocol,
            Constants.mockProtocolName]
      .compactMap({ $0 })
      .joined(separator: ", ")
  }
  
  /// For scoped types referenced within their containing type.
  var fullyQualifiedName: String {
    guard kind == .class else { return "\(moduleName).\(name)" }
    guard !isContainedType else { return "\(name)\(allGenericTypes)" }
    return "\(moduleName).\(name)\(allGenericTypes)"
  }
  
  /// For scoped types referenced at the top level but in the same module.
  func createScopedName(with containingTypeNames: [String], suffix: String = "") -> String {
    guard kind == .class else { // Protocols can't be nested
      return name + suffix + (!suffix.isEmpty ? allGenericTypes : "")
    }
    guard isContainedType else {
      return "\(name)\(suffix)\(allGenericTypes)"
    }
    let containingTypeNames = containingTypeNames.map({ $0 + suffix }).joined(separator: ".")
      + (containingTypeNames.isEmpty ? "" : ".")
    return "\(containingTypeNames)\(name)\(suffix)\(allGenericTypes)"
  }
  
  var stubbedMockName: String {
    return "\(name)Mock\(allGenericTypes)"
  }
  
  var subclass: String? {
    guard kind != .class else { return fullyQualifiedName }
    let prefix = String(name.prefix(2))
    if Constants.objectProtocolPrefixes.contains(prefix) {
      return "NSObject"
    } else {
      return nil
    }
  }
  
  var inheritedProtocol: String? {
    guard kind == .protocol else { return nil }
    return fullyQualifiedName
  }
  
  func generateBody() -> String {
    return [generateClassInitializerProxy(),
            generateVariables(),
            equatableConformance,
            codeableInitializer,
            defaultInitializer,
            generateMethods(),
            generateContainedTypes()]
      .filter({ !$0.isEmpty })
      .joined(separator: "\n\n")
  }
  
  func generateContainedTypes() -> String {
    guard !containedTypes.isEmpty else { return "" }
    return containedTypes
      .map({ $0.generate(moduleName: moduleName).indent(by: 1) })
      .joined(separator: "\n\n")
  }
  
  var equatableConformance: String {
    return """
      public static func ==(lhs: \(name)Mock, rhs: \(name)Mock) -> Bool {
        return true
      }
    """
  }
  
  var codeableInitializer: String {
    guard inheritedTypes.contains(where: { $0.name == "Codable" || $0.name == "Decodable" }) else {
      return ""
    }
    guard !methods.contains(where: { $0.name == "init(from:)" }) else { return "" }
    return """
      public required init(from decoder: Decoder) throws {
        fatalError("init(from:) has not been implemented")
      }
    """
  }
  
  /// Store the source location of where the mock was initialized. This allows XCTest errors from
  /// unstubbed method invocations to show up in the testing code.
  var defaultInitializer: String {
    guard kind == .protocol || !methods.contains(where: { $0.isInitializer }) else { return "" }
    let superInit = (kind == .class ? "super.init()\n    " : "")
    return """
      fileprivate init(sourceLocation: Mockingbird.SourceLocation) {
        \(superInit)Mockingbird.checkVersion(for: self)
        self.sourceLocation = sourceLocation
      }
    """
  }
  
  func createInitializer(with containingTypeNames: [String]) -> String {
    let allGenericTypes = self.allGenericTypes
    let scopedName = createScopedName(with: containingTypeNames)
    let fullyQualifiedScopedName = "\(moduleName).\(scopedName)"
    let genericMethodAttribute: String
    let metatype: String
    if allGenericTypes.count > 0 {
      let specializedGenericTypes =
        (["MockType: \(fullyQualifiedScopedName)"] + allSpecializedGenericTypesList)
          .joined(separator: ", ")
      genericMethodAttribute = "<" + specializedGenericTypes + ">"
      metatype = "MockType.Type"
    } else {
      genericMethodAttribute = ""
      let metatypeKeyword = (kind == .class ? "Type" : "Protocol")
      metatype = "\(fullyQualifiedScopedName).\(metatypeKeyword)"
    }
    
    let returnType: String
    let returnObject: String
    let returnTypeDescription: String
    let mockedScopedName = createScopedName(with: containingTypeNames, suffix: "Mock")
    if kind == .class && methods.contains(where: { $0.isInitializer }) {
      // Requires an initializer proxy to create the partial class mock.
      returnType = "\(mockedScopedName).InitializerProxy.Type"
      returnObject = "\(mockedScopedName).InitializerProxy.self"
      returnTypeDescription = "class mock metatype"
    } else if kind == .class { // Does not require an initializer proxy.
      returnType = "\(mockedScopedName)"
      returnObject = "\(mockedScopedName)(sourceLocation: SourceLocation(file, line))"
      returnTypeDescription = "concrete class mock instance"
    } else {
      returnType = "\(mockedScopedName)"
      returnObject = "\(mockedScopedName)(sourceLocation: SourceLocation(file, line))"
      returnTypeDescription = "concrete protocol mock instance"
    }
    
    return """
    /// Create a source-attributed `\(fullyQualifiedName)\(allGenericTypes)` \(returnTypeDescription).
    public func mock\(genericMethodAttribute)(file: StaticString = #file, line: UInt = #line, _ type: \(metatype)) -> \(returnType) {
      return \(returnObject)
    }
    """
  }

  func generateClassInitializerProxy() -> String {
    guard kind == .class, methods.contains(where: { $0.isInitializer }) else { return "" }
    let initializers = methods.sorted().map({
      MethodGenerator(method: $0, context: self).generateClassInitializerProxy()
    }).filter({ !$0.isEmpty }).joined(separator: "\n\n")
    return """
      public enum InitializerProxy {
    \(initializers)
      }
    """
  }
  
  func generateVariables() -> String {
    return variables.sorted(by: <).map({
      let generated = $0.createGenerator(in: self).generate()
      return generated
    }).joined(separator: "\n\n")
  }
  
  func generateMethods() -> String {
    return methods
      .sorted(by: <)
      .filter({ method -> Bool in
        // Not possible to override overloaded methods where uniqueness is from generic constraints.
        // https://forums.swift.org/t/cannot-override-more-than-one-superclass-declaration/22213
        guard self.kind == .class else { return true }
        guard !method.genericConstraints.isEmpty else { return true }
        return methodsCount[Method.Reduced(from: method)] == 1
      })
      .map({
        let generated = $0.createGenerator(in: self).generate()
        return generated
      })
      .filter({ !$0.isEmpty })
      .joined(separator: "\n\n")
  }
  
  @inlinable func specializeTypeName(_ typeName: String) -> String {
    guard typeName.contains(SerializationRequest.Constants.selfTokenIndicator) else {
      return typeName // Checking prior to running `replacingOccurrences` is 4x faster.
    }
    return typeName
      .replacingOccurrences(of: SerializationRequest.Constants.selfToken, with: name + "Mock")
  }
}
