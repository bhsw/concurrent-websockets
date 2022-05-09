// SPDX-License-Identifier: MIT
// Copyright 2022 Robert A. Stoerrle

import XCTest
import WebSockets

fileprivate let thirdPartyServerURL = URL(string: "wss://echo.websocket.events")!

class WebSocketTests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  override func tearDownWithError() throws {
  }

  func testPingOnLocalServer() async throws {
    let server = TestServer()
    defer {
      Task {
        await server.stop()
      }
    }
    let url = try await server.start(path: "/test")
    try await randomPingTest(url: url)
  }

  func testPingOnThirdPartyServer() async throws {
    try await randomPingTest(url: thirdPartyServerURL)
  }

  func testRandomDataOnLocalServer() async throws {
    let server = TestServer()
    defer {
      Task {
        await server.stop()
      }
    }
    let sizes = [ 0, 1, 16, 64, 125, 126, 127, 128, 65535, 65536, 65537, 999_999 ]
    let url = try await server.start(path: "/test")
    try await randomDataTest(url: url, sizes: sizes)
  }

  func testRandomDataOnThirdPartyServer() async throws {
    let sizes = [ 0, 1, 16, 64, 125, 126, 127, 128, 65535, 65536, 65537, 999_999 ]
    try await randomDataTest(url: thirdPartyServerURL, sizes: sizes)
  }

  func testSubprotocolOneFromList() async throws {
    let server = TestServer(subprotocol: "second")
    defer {
      Task {
        await server.stop()
      }
    }

    var options = WebSocket.Options()
    options.subprotocols = [ "first", "second", "third" ]
    let socket = WebSocket(url: try await server.start(path: "/test"), options: options)
    await socket.send(text: "Hello")
    await socket.close()
    var closed = false
    for try await event in socket {
      switch event {
        case .open(let result):
          XCTAssertEqual(result.subprotocol, "second")
        case .close(code: _, reason: _, wasClean: let wasClean):
          XCTAssert(wasClean)
          closed = true
        default:
          break;
      }
    }
    XCTAssert(closed)
  }

  func testSubprotocolNoneFromList() async throws {
    let server = TestServer(subprotocol: nil)
    defer {
      Task {
        await server.stop()
      }
    }

    var options = WebSocket.Options()
    options.subprotocols = [ "first", "second", "third" ]
    let socket = WebSocket(url: try await server.start(path: "/test"), options: options)
    await socket.send(text: "Hello")
    await socket.close()
    var closed = false
    for try await event in socket {
      switch event {
        case .open(let result):
          XCTAssertEqual(result.subprotocol, nil)
        case .close(code: _, reason: _, wasClean: let wasClean):
          XCTAssert(wasClean)
          closed = true
        default:
          break;
      }
    }
    XCTAssert(closed)
  }

  func testUnexpectedSubprotocol() async throws {
    let server = TestServer(subprotocol: "nope")
    defer {
      Task {
        await server.stop()
      }
    }

    let socket = WebSocket(url: try await server.start(path: "/test"))
    await socket.send(text: "Hello")
    await socket.close()
    do {
      for try await _ in socket {
      }
      XCTFail("Expected an exception ")
    } catch WebSocketError.subprotocolMismatch {
    }
  }

  func testRedirect() async throws {
    let server = TestServer(subprotocol: nil)
    defer {
      Task {
        await server.stop()
      }
    }

    let socket = WebSocket(url: try await server.start(path: "/redirect"))
    await socket.send(text: "Hello")
    await socket.close()
    for try await _ in socket {
    }
    let path = await socket.url.path
    XCTAssertEqual(path, "/test")
  }

  func testJustClosingNeverOpens() async throws {
    let socket = WebSocket(url: URL(string: "ws://localhost")!)         // The actual URL won't be used in this case
    await socket.close()
    let event = try await socket.makeAsyncIterator().next()
    XCTAssert(event == nil)
  }

  func testOpeningHandshakeTimeout() async throws {
    let server = TestServer(httpResponseDelay: 10)
    defer {
      Task {
        await server.stop()
      }
    }
    var options = WebSocket.Options()
    options.openingHandshakeTimeout = 1
    let socket = WebSocket(url: try await server.start(), options: options)
    await socket.send(text: "Hello")
    await socket.close()
    do {
      for try await _ in socket {
      }
      XCTFail("Expected an exception ")
    } catch WebSocketError.timeout {
    }
  }

  func testUnexpectedHandshakeDisconnect() async throws {
    let server = TestServer(httpRequestTimeout: 0)
    defer {
      Task {
        await server.stop()
      }
    }
    let socket = WebSocket(url: try await server.start())
    await socket.send(text: "Hello")
    await socket.close()
    do {
      for try await _ in socket {
      }
      XCTFail("Expected an exception ")
    } catch WebSocketError.unexpectedDisconnect {
    }
  }

  func testInvalidURL() async throws {
    let socket = WebSocket(url: URL(string: "wss://")!)
    await socket.send(text: "Hello")
    do {
      for try await _ in socket {
      }
      XCTFail("Expected an exception ")
    } catch WebSocketError.invalidURL {
    }
  }

  func testInvalidURLScheme() async throws {
    let socket = WebSocket(url: URL(string: "http://localhost")!)
    await socket.send(text: "Hello")
    do {
      for try await _ in socket {
      }
      XCTFail("Expected an exception ")
    } catch WebSocketError.invalidURLScheme {
    }
  }

  func testHostLookupFailure() async throws {
    let socket = WebSocket(url: URL(string: "ws://nope.ocsoft.com")!)
    await socket.send(text: "Hello")
    do {
      for try await _ in socket {
      }
      XCTFail("Expected an exception ")
    } catch WebSocketError.hostLookupFailed {
    }
  }

  func testConnectionFailure() async throws {
    let socket = WebSocket(url: URL(string: "ws://ocsoft.com:500")!)
    await socket.send(text: "Hello")
    do {
      for try await _ in socket {
      }
      XCTFail("Expected an exception ")
    } catch WebSocketError.connectionFailed {
    }
  }

  func testTLSFailure() async throws {
    let socket = WebSocket(url: URL(string: "wss://ocsoft.com:80")!)
    await socket.send(text: "Hello")
    do {
      for try await _ in socket {
      }
      XCTFail("Expected an exception ")
    } catch WebSocketError.tlsFailed {
    }
  }

  func testUnexpectedHTTPStatus() async throws {
    let server = TestServer()
    defer {
      Task {
        await server.stop()
      }
    }
    let socket = WebSocket(url: try await server.start(path: "/404"))
    await socket.send(text: "Hello")
    do {
      for try await _ in socket {
      }
      XCTFail("Expected an exception ")
    } catch WebSocketError.unexpectedHTTPStatus(let result) {
      XCTAssertEqual(result.status, .notFound)
    }
  }

  func testRedirectLoop() async throws {
    let server = TestServer()
    defer {
      Task {
        await server.stop()
      }
    }
    let socket = WebSocket(url: try await server.start(path: "/redirect-loop"))
    await socket.send(text: "Hello")
    do {
      for try await _ in socket {
      }
      XCTFail("Expected an exception ")
    } catch WebSocketError.maximumRedirectsExceeded {
    }
  }

  func randomDataTest(url: URL, sizes: [Int]) async throws {
    let socket = WebSocket(url: url)
    let expected = sizes.map { randomData(size: $0) }
    var received: [Data] = []
    var receivedClose = false
    for data in expected {
      await socket.send(data: data)
    }
    await socket.close()
    for try await event in socket {
      switch event {
        case .binary(let data):
          received.append(data)
        case .close(code: _, reason: _, wasClean: let wasClean):
          XCTAssert(wasClean)
          receivedClose = true
        default:
          break
      }
    }
    XCTAssert(received == expected)
    XCTAssert(receivedClose)
  }

  func randomPingTest(url: URL) async throws {
    let socket = WebSocket(url: url)
    let expected = [0, 1, 16, 32, 64, 125 ].map { randomData(size: $0) }
    var received: [Data] = []
    var receivedClose = false
    for try await event in socket {
      switch event {
        case .open(_):
          for data in expected {
            await socket.ping(data: data)
          }
          await socket.close()
        case .pong(let data):
          received.append(data)
        case .close(code: _, reason: _, wasClean: let wasClean):
          XCTAssert(wasClean)
          receivedClose = true
        default:
          break
      }
    }
    XCTAssert(received == expected)
    XCTAssert(receivedClose)
  }
}
