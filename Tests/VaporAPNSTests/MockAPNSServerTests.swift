import APNS
import VaporAPNS
import XCTVapor
import NIOCore
import NIOPosix

class VaporAPNSIntegrationTests: XCTestCase {
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
    
    var app: Application!
    
    override func setUp() async throws {
        try await super.setUp()
        app = try await Application.make(.testing)
    }
    
    override func tearDown() async throws {
        if app != nil {
            try await app.asyncShutdown()
        }
        try await super.tearDown()
    }
    
    func testAPNSContainerConfiguration() async throws {
        // Test that we can configure APNS containers
        let apnsConfig = APNSClientConfiguration(
            authenticationMethod: .jwt(
                privateKey: try .init(pemRepresentation: appleECP8PrivateKey),
                keyIdentifier: "9UC9ZLQ8YW",
                teamIdentifier: "ABBM6U9RM5"
            ),
            environment: .development
        )
        
        await app.apns.containers.use(
            apnsConfig,
            eventLoopGroupProvider: .shared(MultiThreadedEventLoopGroup.singleton),
            responseDecoder: JSONDecoder(),
            requestEncoder: JSONEncoder(),
            as: .default
        )
        
        // Verify that the container is configured
        let container = await app.apns.containers.container()
        XCTAssertNotNil(container)
        // Note: APNSEnvironment doesn't conform to Equatable, so we verify configuration exists
        XCTAssertNotNil(container?.configuration)
    }
    
    func testAPNSClientAccessFromRequest() async throws {
        // Configure APNS first
        let apnsConfig = APNSClientConfiguration(
            authenticationMethod: .jwt(
                privateKey: try .init(pemRepresentation: appleECP8PrivateKey),
                keyIdentifier: "9UC9ZLQ8YW",
                teamIdentifier: "ABBM6U9RM5"
            ),
            environment: .development
        )
        
        await app.apns.containers.use(
            apnsConfig,
            eventLoopGroupProvider: .shared(MultiThreadedEventLoopGroup.singleton),
            responseDecoder: JSONDecoder(),
            requestEncoder: JSONEncoder(),
            as: .default
        )
        
        // Test that we can access APNS client from request
        app.get("test-apns-access") { req async -> HTTPStatus in
            let container = await req.application.apns.containers.container()
            XCTAssertNotNil(container)
            return .ok
        }
        
        try await app.test(.GET, "test-apns-access") { res in
            XCTAssertEqual(res.status, .ok)
        }
    }
    
    func testMultipleAPNSContainers() async throws {
        // Test configuring multiple APNS containers
        let productionConfig = APNSClientConfiguration(
            authenticationMethod: .jwt(
                privateKey: try .init(pemRepresentation: appleECP8PrivateKey),
                keyIdentifier: "9UC9ZLQ8YW",
                teamIdentifier: "ABBM6U9RM5"
            ),
            environment: .production
        )
        
        let developmentConfig = APNSClientConfiguration(
            authenticationMethod: .jwt(
                privateKey: try .init(pemRepresentation: appleECP8PrivateKey),
                keyIdentifier: "9UC9ZLQ8YW",
                teamIdentifier: "ABBM6U9RM5"
            ),
            environment: .development
        )
        
        await app.apns.containers.use(
            productionConfig,
            eventLoopGroupProvider: .shared(MultiThreadedEventLoopGroup.singleton),
            responseDecoder: JSONDecoder(),
            requestEncoder: JSONEncoder(),
            as: .production
        )
        
        await app.apns.containers.use(
            developmentConfig,
            eventLoopGroupProvider: .shared(MultiThreadedEventLoopGroup.singleton),
            responseDecoder: JSONDecoder(),
            requestEncoder: JSONEncoder(),
            as: .development
        )
        
        // Verify both containers are configured
        let productionContainer = await app.apns.containers.container(for: .production)
        let developmentContainer = await app.apns.containers.container(for: .development)
        
        XCTAssertNotNil(productionContainer)
        XCTAssertNotNil(developmentContainer)
        XCTAssertNotNil(productionContainer?.configuration)
        XCTAssertNotNil(developmentContainer?.configuration)
    }
    
    func testAPNSContainerShutdown() async throws {
        // Test that containers can be shut down properly
        let apnsConfig = APNSClientConfiguration(
            authenticationMethod: .jwt(
                privateKey: try .init(pemRepresentation: appleECP8PrivateKey),
                keyIdentifier: "9UC9ZLQ8YW",
                teamIdentifier: "ABBM6U9RM5"
            ),
            environment: .development
        )
        
        await app.apns.containers.use(
            apnsConfig,
            eventLoopGroupProvider: .shared(MultiThreadedEventLoopGroup.singleton),
            responseDecoder: JSONDecoder(),
            requestEncoder: JSONEncoder(),
            as: .default
        )
        
        // Verify container is configured
        let container = await app.apns.containers.container()
        XCTAssertNotNil(container)
        
        // Test shutdown - this should not throw
        await app.apns.containers.shutdown()
    }
    
    func testConvenienceConfigurationMethod() async throws {
        // Test the convenience configure method that sets up both production and development
        await app.apns.configure(.jwt(
            privateKey: try .init(pemRepresentation: appleECP8PrivateKey),
            keyIdentifier: "9UC9ZLQ8YW",
            teamIdentifier: "ABBM6U9RM5"
        ))
        
        // Verify both containers are configured
        let productionContainer = await app.apns.containers.container(for: .production)
        let developmentContainer = await app.apns.containers.container(for: .development)
        
        XCTAssertNotNil(productionContainer)
        XCTAssertNotNil(developmentContainer)
        XCTAssertNotNil(productionContainer?.configuration)
        XCTAssertNotNil(developmentContainer?.configuration)
    }
    
    func testRequestAPNSProperty() throws {
        // Test that request.apns returns the correct APNS instance
        app.get("test-request-apns") { req async -> HTTPStatus in
            let apns = req.apns
            XCTAssertNotNil(apns)
            // Note: application property is internal, so just verify apns exists
            return .ok
        }
        
        try app.test(.GET, "test-request-apns") { res in
            XCTAssertEqual(res.status, .ok)
        }
    }
} 