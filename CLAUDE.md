# Mockingbird — Claude Notes

## What this project is
A Swift mocking framework for XCTest. Lets tests mock, stub, and verify Swift and Objective-C types without boilerplate.

## Project structure
- `Sources/MockingbirdFramework/` — core runtime (mocking, stubbing, verification)
- `Sources/MockingbirdCli/` — CLI tool for generating mocks
- `Sources/MockingbirdGenerator/` — mock generation logic
- `Sources/MockingbirdTestsHost/` — protocols/classes used as test subjects
- `Tests/MockingbirdTests/Framework/` — unit tests for the framework
- `Tests/MockingbirdTests/Mocks/` — pre-generated mocks for test host types
- `Tests/MockingbirdTests/E2E/` — generated-mock compatibility tests

## Build system
- Primary: **Xcode project** (`Mockingbird.xcodeproj`) — required for tests (no SPM test target)
- SPM `Package.swift` exists for the framework library product only; set `MKB_BUILD_EXECUTABLES=1` to also build CLI targets
- Swift 5.10+ / macOS 12 / iOS 14 minimum for the library
- CI: macOS 15 / Xcode 16.2.0 (see `.github/workflows/ci.yml`)

## Adding new test files
Test files must be **explicitly added to the Xcode project** — there is no `fileSystemSynchronizedGroups`. In `project.pbxproj`, add:
1. A `PBXFileReference` entry in the file references section
2. A `PBXBuildFile` entry in the build files section
3. The file reference UUID to the `Framework` group children list (~line 1739)
4. The build file UUID to the `Sources` build phase list (~line 2556)

## Async verification
- Sync form: `eventually { verify(...).wasCalled() }` + `wait(for:timeout:)` or `waitForExpectations(timeout:)`
- **Async form (new)**: `await eventually { verify(await mock.asyncMethod()).wasCalled() }` + `await fulfillment(of:timeout:)` — requires `@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)`
- Context propagation uses `@TaskLocal` (`ExpectationGroup.$localGroup`), replacing the old `DispatchQueue.setSpecific()` approach
- `TestExpectation` is `MKBTestExpectation` (Obj-C class `NS_SWIFT_NAME`d), a subclass of `XCTestExpectation`

## Key mocks available in tests
- `ChildMock` (from `mock(Child.self)`) — sync class with `childTrivialInstanceMethod()`, `parentTrivialInstanceMethod()`, `grandparentTrivialInstanceMethod()`
- `AsyncProtocolMock` (from `mock(AsyncProtocol.self)`) — async protocol with `asyncMethodVoid()`, `asyncMethod() -> Bool`, `asyncMethod(parameter: String) -> Int`, `asyncThrowingMethod() throws -> Int`, `asyncClosureMethod`, `asyncClosureThrowingMethod`

## Test patterns
```swift
// Synchronous eventually
let exp = eventually { verify(mock.method()).wasCalled() }
wait(for: [exp], timeout: 1.0)

// Async eventually (for async mocks)
let exp = await eventually {
    verify(await mock.asyncMethod()).wasCalled()
}
await fulfillment(of: [exp], timeout: 1.0)
```
