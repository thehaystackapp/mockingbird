import XCTest
import Mockingbird
@testable import MockingbirdTestsHost

#if swift(>=5.5.2)
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
class AsyncEventuallyVerificationTests: XCTestCase {

  var asyncProtocol: AsyncProtocolMock!
  var asyncProtocolInstance: AsyncProtocol { asyncProtocol }
  var child: ChildMock!

  override func setUp() {
    asyncProtocol = mock(AsyncProtocol.self)
    child = mock(Child.self)
  }

  enum Constants {
    static let asyncTestTimeout: TimeInterval = 1.0
  }


  // MARK: - Basic async method verification

  func testAsyncEventually_trivialAsyncVoidMethod() async {
    given(await asyncProtocol.asyncMethodVoid()).willReturn()

    Task {
      await self.asyncProtocolInstance.asyncMethodVoid()
    }

    let expectation = await eventually("asyncMethodVoid() is called") {
      verify(await self.asyncProtocol.asyncMethodVoid()).wasCalled()
    }
    await fulfillment(of: [expectation], timeout: Constants.asyncTestTimeout)
  }

  func testAsyncEventually_asyncMethodReturningValue() async {
    given(await asyncProtocol.asyncMethod()) ~> true

    Task {
      _ = await self.asyncProtocolInstance.asyncMethod()
    }

    let expectation = await eventually("asyncMethod() is called") {
      verify(await self.asyncProtocol.asyncMethod()).wasCalled()
    }
    await fulfillment(of: [expectation], timeout: Constants.asyncTestTimeout)
  }

  func testAsyncEventually_asyncMethodWithAnyParameter() async {
    given(await asyncProtocol.asyncMethod(parameter: any())) ~> 42

    Task {
      _ = await self.asyncProtocolInstance.asyncMethod(parameter: "test")
    }

    let expectation = await eventually("asyncMethod(parameter:) is called with any value") {
      verify(await self.asyncProtocol.asyncMethod(parameter: any())).wasCalled()
    }
    await fulfillment(of: [expectation], timeout: Constants.asyncTestTimeout)
  }

  func testAsyncEventually_asyncMethodWithSpecificParameter() async {
    given(await asyncProtocol.asyncMethod(parameter: any())) ~> 99

    Task {
      _ = await self.asyncProtocolInstance.asyncMethod(parameter: "specific")
    }

    let expectation = await eventually("asyncMethod(parameter:) is called with specific value") {
      verify(await self.asyncProtocol.asyncMethod(parameter: "specific")).wasCalled()
    }
    await fulfillment(of: [expectation], timeout: Constants.asyncTestTimeout)
  }


  // MARK: - Call count verification

  func testAsyncEventually_asyncMethodCalledTwice() async {
    given(await asyncProtocol.asyncMethodVoid()).willReturn()

    Task {
      await self.asyncProtocolInstance.asyncMethodVoid()
      await self.asyncProtocolInstance.asyncMethodVoid()
    }

    let expectation = await eventually("asyncMethodVoid() is called twice") {
      verify(await self.asyncProtocol.asyncMethodVoid()).wasCalled(exactly(2))
    }
    await fulfillment(of: [expectation], timeout: Constants.asyncTestTimeout)
  }


  // MARK: - Multiple verifications in one block

  func testAsyncEventually_multipleVerificationsInBlock() async {
    given(await asyncProtocol.asyncMethodVoid()).willReturn()
    given(await asyncProtocol.asyncMethod()) ~> true

    Task {
      await self.asyncProtocolInstance.asyncMethodVoid()
      _ = await self.asyncProtocolInstance.asyncMethod()
    }

    let expectation = await eventually("multiple async methods are called") {
      verify(await self.asyncProtocol.asyncMethodVoid()).wasCalled()
      verify(await self.asyncProtocol.asyncMethod()).wasCalled()
    }
    await fulfillment(of: [expectation], timeout: Constants.asyncTestTimeout)
  }


  // MARK: - Past invocations

  func testAsyncEventually_handlesPastAsyncInvocations() async {
    given(await asyncProtocol.asyncMethodVoid()).willReturn()
    await asyncProtocolInstance.asyncMethodVoid()

    let expectation = await eventually("asyncMethodVoid() was already called") {
      verify(await self.asyncProtocol.asyncMethodVoid()).wasCalled()
    }
    await fulfillment(of: [expectation], timeout: Constants.asyncTestTimeout)
  }

  func testAsyncEventually_handlesPastAsyncInvocations_exactCount() async {
    given(await asyncProtocol.asyncMethodVoid()).willReturn()
    await asyncProtocolInstance.asyncMethodVoid()
    await asyncProtocolInstance.asyncMethodVoid()
    await asyncProtocolInstance.asyncMethodVoid()

    let expectation = await eventually("asyncMethodVoid() was already called 3 times") {
      verify(await self.asyncProtocol.asyncMethodVoid()).wasCalled(exactly(3))
    }
    await fulfillment(of: [expectation], timeout: Constants.asyncTestTimeout)
  }


  // MARK: - Default description

  func testAsyncEventually_usesDefaultDescription() async {
    given(await asyncProtocol.asyncMethodVoid()).willReturn()

    Task {
      await self.asyncProtocolInstance.asyncMethodVoid()
    }

    let expectation = await eventually {
      verify(await self.asyncProtocol.asyncMethodVoid()).wasCalled()
    }
    await fulfillment(of: [expectation], timeout: Constants.asyncTestTimeout)
  }


  // MARK: - Mixed async and synchronous verifications

  /// The async `eventually` overload is only selected when its block contains an `await`. Once an
  /// async verification has forced that overload, a synchronous verification can ride along in the
  /// same block and is collected into the same expectation group.
  ///
  /// Note: `inOrder` takes a synchronous block, so it cannot host an `await`ed verification and is
  /// covered by the synchronous `eventually` overload in `AsyncVerificationTests`.
  func testAsyncEventually_mixedAsyncAndSyncVerifications() async {
    given(await asyncProtocol.asyncMethodVoid()).willReturn()

    Task {
      await self.asyncProtocolInstance.asyncMethodVoid()
      (self.child as Child).childTrivialInstanceMethod()
    }

    let expectation = await eventually("an async and a sync method are both called") {
      verify(await self.asyncProtocol.asyncMethodVoid()).wasCalled()
      verify(self.child.childTrivialInstanceMethod()).wasCalled()
    }
    await fulfillment(of: [expectation], timeout: Constants.asyncTestTimeout)
  }

}
#endif
