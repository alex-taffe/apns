import APNS
import VaporAPNS
import XCTVapor
import NIOCore
import NIOPosix

class MockAPNSServerTests: XCTestCase {
    struct Payload: Codable {
        let message: String
    }
    
    let appleECP8PrivateKey = """
    -----BEGIN PRIVATE KEY-----
    MIGTAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBHkwdwIBAQQg2sD+kukkA8GZUpmm
    jRa4fJ9Xa/JnIG4Hpi7tNO66+OGgCgYIKoZIzj0DAQehRANCAATZp0yt0btpR9kf
    ntp4oUUzTV0+eTELXxJxFvhnqmgwGAm1iVW132XLrdRG/ntlbQ1yzUuJkHtYBNve
    y+77Vzsd
    -----END PRIVATE KEY-----
    """
    
    var mockServer: Application!
    var client: Application!
    var mockServerPort: Int = 8081
    
    override func setUp() async throws {
        try await super.setUp()
        setupMockAPNSServer()
        try await setupClient()
    }
    
    override func tearDown() async throws {
        // Shutdown clients first, then servers
        if client != nil {
            // ✨ Modern async/await for container shutdown
            await client.apns.containers.shutdown()
            client.shutdown()
        }
        
        if mockServer != nil {
            mockServer.shutdown()
        }
        
        try await super.tearDown()
    }
    
    func setupMockAPNSServer() {
        mockServer = Application(.testing)
        
        // Set log level to trace to see all requests
        mockServer.logger.logLevel = .trace
        
        // Mock successful push notification endpoint
        mockServer.post("3", "device", ":deviceToken") { req -> Response in
            let deviceToken = req.parameters.get("deviceToken")!
            
            req.logger.info("Mock APNS: Received request")
            req.logger.info("Mock APNS: Method: \(req.method)")
            req.logger.info("Mock APNS: URL: \(req.url)")
            req.logger.info("Mock APNS: Headers: \(req.headers)")
            req.logger.info("Mock APNS: Device Token: \(deviceToken)")
            
            // Verify authorization header exists
            guard let authorization = req.headers.first(name: "authorization") else {
                req.logger.error("Missing authorization header")
                return Response(status: .unauthorized)
            }
            
            // Simple check for bearer token format
            guard authorization.hasPrefix("bearer ") else {
                req.logger.error("Invalid authorization format: \(authorization)")
                return Response(status: .forbidden)
            }
            
            // Mock response with APNS-ID
            let response = Response(status: .ok)
            response.headers.add(name: "apns-id", value: UUID().uuidString)
            
            // Log the successful response
            req.logger.info("Mock APNS: Successfully received push for device \(deviceToken)")
            
            return response
        }
        
        // Add a catch-all endpoint to see what requests we're getting
        mockServer.on(.POST, "**") { req -> Response in
            req.logger.warning("Mock APNS: Unmatched POST request to: \(req.url)")
            req.logger.warning("Mock APNS: Headers: \(req.headers)")
            return Response(status: .notFound)
        }
        
        // Add a simple health check endpoint for debugging
        mockServer.get("health") { req -> Response in
            req.logger.info("Mock APNS: Health check received")
            return Response(status: .ok, body: .init(string: "OK"))
        }
        
        // Start the mock server on a specific port
        mockServer.http.server.configuration.port = mockServerPort
        
        // Start the server using the working pattern
        let promise = mockServer.eventLoopGroup.next().makePromise(of: Void.self)
        promise.completeWithTask { [mockServer] in
            try await mockServer!.startup()
        }
        try! promise.futureResult.wait()
        
        // Give the server a moment to start
        usleep(200_000) // 200ms
        
        print("Mock APNS server started on http://localhost:\(mockServerPort)")
    }
    
    func setupClient() async throws {
        client = Application(.testing)
        
        // Set log level to trace to see all APNS client activity
        client.logger.logLevel = .trace
        
        let apnsConfig = APNSClientConfiguration(
            authenticationMethod: .jwt(
                privateKey: try .init(pemRepresentation: appleECP8PrivateKey),
                keyIdentifier: "9UC9ZLQ8YW",
                teamIdentifier: "ABBM6U9RM5"
            ),
            environment: .custom(url: "http://127.0.0.1:\(mockServerPort)")
        )
        
        print("APNS Client configured with URL: http://127.0.0.1:\(mockServerPort)")
        
        // ✨ Modern async/await for APNS container setup
        await client.apns.containers.use(
            apnsConfig,
            eventLoopGroupProvider: .shared(MultiThreadedEventLoopGroup.singleton),
            responseDecoder: JSONDecoder(),
            requestEncoder: JSONEncoder(),
            as: .default
        )
    }
    
    func testMockServerHealthCheck() throws {
        // First, let's verify our mock server is accessible
        try mockServer.test(.GET, "health") { res in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(res.body.string, "OK")
        }
    }
    
    func testDirectHTTPConnection() throws {
        // Test that we can connect directly to our mock server using HTTP/1.1
        try mockServer.test(.POST, "3/device/test-token", headers: HTTPHeaders([
            ("authorization", "bearer test-token")
        ])) { res in
            print("Direct test status: \(res.status)")
            print("Direct test body: \(res.body.string)")
            XCTAssertEqual(res.status, .ok)
        }
    }
    
    func testAPNSConfigurationURL() throws {
        // Test that we can retrieve the APNS client and examine its configuration
        client.get("test-config") { req async -> HTTPStatus in
            let container = await req.application.apns.containers.container()
            XCTAssertNotNil(container)
            
            // Try to get more info about the configuration
            if let container = container {
                req.logger.info("APNS Container configuration: \(container.configuration)")
                req.logger.info("APNS Environment: \(container.configuration.environment)")
            }
            
            return .ok
        }
        
        try client.test(.GET, "test-config") { res in
            XCTAssertEqual(res.status, .ok)
        }
    }
    
    func testSuccessfulPushNotification() throws {
        let deviceToken = "98AAD4A2398DDC58595F02FA307DF9A15C18B6111D1B806949549085A8E6A55D"
        
        client.get("test-push") { req -> HTTPStatus in
            do {
                req.logger.info("About to send APNS notification...")
                
                try await req.apns.client.sendAlertNotification(
                    .init(
                        alert: .init(
                            title: .raw("Hello"),
                            subtitle: .raw("This is a test notification")
                        ),
                        expiration: .immediately,
                        priority: .immediately,
                        topic: "com.example.MyApp",
                        payload: Payload(message: "Hello World!")
                    ),
                    deviceToken: deviceToken
                )
                
                req.logger.info("APNS notification sent successfully!")
                return .ok
            } catch {
                req.logger.error("APNS Error: \(error)")
                return .internalServerError
            }
        }
        
        try client.test(.GET, "test-push") { res in
            if res.status != .ok {
                print("Test failed with status: \(res.status)")
                print("Response body: \(res.body.string)")
            }
            XCTAssertEqual(res.status, .ok)
        }
    }
    
    func testBasicContainerSetup() throws {
        // Test that we can access the APNS container
        client.get("test-container") { req async -> HTTPStatus in
            let container = await req.application.apns.containers.container()
            XCTAssertNotNil(container)
            return .ok
        }
        
        try client.test(.GET, "test-container") { res in
            XCTAssertEqual(res.status, .ok)
        }
    }
} 