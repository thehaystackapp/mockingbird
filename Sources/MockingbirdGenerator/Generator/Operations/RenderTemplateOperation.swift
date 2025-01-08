import Foundation

class RenderTemplateOperation: BasicOperation, @unchecked Sendable {
  let template: Template
  
  class Result {
    fileprivate(set) var renderedContents = ""
  }
  
  let result = Result()
  
  init(template: Template) {
    self.template = template
  }
  
  override func run() {
    result.renderedContents = template.render()
  }
}
