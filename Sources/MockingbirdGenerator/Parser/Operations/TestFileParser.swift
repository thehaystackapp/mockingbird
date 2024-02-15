import Foundation
import SwiftSyntax

class TestFileParser: SyntaxVisitor {
  var mockedTypeNames = Set<String>()
  
  init() {
    super.init(viewMode: .sourceAccurate)
  }

  func parse<SyntaxType: SyntaxProtocol>(_ node: SyntaxType) -> Self {
    walk(node)
    return self
  }
  
  /// Handle function calls, e.g. `mock(SomeType.self)`
  override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
    guard
      node.arguments.count == 1,
      let firstArgument = node.arguments.first, firstArgument.label == nil,
      node.calledExpression.trimmed.description == "mock"
      else { return .visitChildren }

    let expression = firstArgument.expression
    guard expression.lastToken(viewMode: .sourceAccurate)?.trimmed.description == "self" else { return .visitChildren }
    
    // Could be a fully or partially qualified type name.
    let typeName = String(expression.trimmed.description.dropLast(5))
    mockedTypeNames.insert(typeName.removingGenericTyping())
    
    return .skipChildren
  }
}
