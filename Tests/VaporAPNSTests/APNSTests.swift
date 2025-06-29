import APNS
import VaporAPNS
import XCTVapor

class APNSTests: XCTestCase {
    struct Payload: Codable {}
    let appleECP8PrivateKey = """
    -----BEGIN PRIVATE KEY-----
    MIGTAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBHkwdwIBAQQg2sD+kukkA8GZUpmm
    jRa4fJ9Xa/JnIG4Hpi7tNO66+OGgCgYIKoZIzj0DAQehRANCAATZp0yt0btpR9kf
    ntp4oUUzTV0+eTELXxJxFvhnqmgwGAm1iVW132XLrdRG/ntlbQ1yzUuJkHtYBNve
    y+77Vzsd
    -----END PRIVATE KEY-----
    """

    func testApplication() throws {
        let app = Application(.testing)
        defer { 
            // Shutdown APNS containers first, then the app
            try! app.eventLoopGroup.next().makeFutureWithTask {
                await app.apns.containers.shutdown()
            }.wait()
            app.shutdown() 
        }
        
        let apnsConfig = APNSClientConfiguration(
            authenticationMethod: .jwt(
                privateKey: try .init(pemRepresentation: appleECP8PrivateKey),
                keyIdentifier: "9UC9ZLQ8YW",
                teamIdentifier: "ABBM6U9RM5"
            ),
            environment: .development
        )

        // Use eventLoopGroup.next().wait() to run async code in sync context
        try app.eventLoopGroup.next().makeFutureWithTask {
            await app.apns.containers.use(
                apnsConfig,
                eventLoopGroupProvider: .shared(MultiThreadedEventLoopGroup.singleton),
                responseDecoder: JSONDecoder(),
                requestEncoder: JSONEncoder(),
                as: .default
            )
        }.wait()

        app.get("test-push") { req -> HTTPStatus in
            try await req.apns.client.sendAlertNotification(
                .init(
                    alert: .init(
                        title: .raw("Hello"),
                        subtitle: .raw("This is a test from vapor/apns")
                    ),
                    expiration: .immediately,
                    priority: .immediately,
                    topic: "MY_TOPC",
                    payload: Payload()
                ),
                deviceToken: "98AAD4A2398DDC58595F02FA307DF9A15C18B6111D1B806949549085A8E6A55D"
            )
            return .ok
        }
        try app.test(.GET, "test-push") { res in
            XCTAssertEqual(res.status, .internalServerError)
        }
    }

    func testContainers() throws {
        let app = Application(.testing)
        defer { 
            // Shutdown APNS containers first, then the app
            try! app.eventLoopGroup.next().makeFutureWithTask {
                await app.apns.containers.shutdown()
            }.wait()
            app.shutdown() 
        }
        
        app.logger.logLevel = .trace
        let authConfig: APNSClientConfiguration.AuthenticationMethod = .jwt(
            privateKey: try .init(pemRepresentation: appleECP8PrivateKey),
            keyIdentifier: "9UC9ZLQ8YW",
            teamIdentifier: "ABBM6U9RM5"
        )

        let apnsConfig = APNSClientConfiguration(
            authenticationMethod: authConfig,
            environment: .development
        )

        try app.eventLoopGroup.next().makeFutureWithTask {
            await app.apns.containers.use(
                apnsConfig,
                eventLoopGroupProvider: .shared(MultiThreadedEventLoopGroup.singleton),
                responseDecoder: JSONDecoder(),
                requestEncoder: JSONEncoder(),
                as: .default
            )
        }.wait()

        let defaultContainer = try app.eventLoopGroup.next().makeFutureWithTask {
            await app.apns.containers.container()
        }.wait()
        
        XCTAssertNotNil(defaultContainer)
        
        let defaultMethodContainer = try app.eventLoopGroup.next().makeFutureWithTask {
            await app.apns.containers.container(for: .default)!
        }.wait()
        
        let defaultComputedContainer = try app.eventLoopGroup.next().makeFutureWithTask {
            await app.apns.containers.container!
        }.wait()
        
        XCTAssert(defaultContainer === defaultMethodContainer)
        XCTAssert(defaultContainer === defaultComputedContainer)

        app.get("test-push") { req -> HTTPStatus in
            let client = await req.apns.client
            XCTAssert(client === defaultContainer?.client)

            return .ok
        }
        try app.test(.GET, "test-push") { res in
            XCTAssertEqual(res.status, .ok)
        }

        let customConfig: APNSClientConfiguration = .init(
            authenticationMethod: authConfig,
            environment: .custom(url: "http://apple.com")
        )

        try app.eventLoopGroup.next().makeFutureWithTask {
            await app.apns.containers.use(
                customConfig,
                eventLoopGroupProvider: .shared(MultiThreadedEventLoopGroup.singleton),
                responseDecoder: JSONDecoder(),
                requestEncoder: JSONEncoder(),
                as: .custom
            )
        }.wait()

        let containerPostCustom = try app.eventLoopGroup.next().makeFutureWithTask {
            await app.apns.containers.container()
        }.wait()
        
        XCTAssertNotNil(containerPostCustom)
        app.get("test-push2") { req -> HTTPStatus in
            let client = await req.apns.client
            XCTAssert(client === containerPostCustom?.client)
            return .ok
        }
        try app.test(.GET, "test-push2") { res in
            XCTAssertEqual(res.status, .ok)
        }
    }

    func testCustomContainers() throws {
        let app = Application(.testing)
        defer { 
            // Shutdown APNS containers first, then the app
            try! app.eventLoopGroup.next().makeFutureWithTask {
                await app.apns.containers.shutdown()
            }.wait()
            app.shutdown() 
        }
        
        let authConfig: APNSClientConfiguration.AuthenticationMethod = .jwt(
            privateKey: try .init(pemRepresentation: appleECP8PrivateKey),
            keyIdentifier: "9UC9ZLQ8YW",
            teamIdentifier: "ABBM6U9RM5"
        )

        let apnsConfig = APNSClientConfiguration(
            authenticationMethod: authConfig,
            environment: .development
        )

        try app.eventLoopGroup.next().makeFutureWithTask {
            await app.apns.containers.use(
                apnsConfig,
                eventLoopGroupProvider: .shared(MultiThreadedEventLoopGroup.singleton),
                responseDecoder: JSONDecoder(),
                requestEncoder: JSONEncoder(),
                as: .default,
                isDefault: true
            )
        }.wait()

        let customConfig: APNSClientConfiguration = .init(
            authenticationMethod: authConfig,
            environment: .custom(url: "http://apple.com")
        )

        try app.eventLoopGroup.next().makeFutureWithTask {
            await app.apns.containers.use(
                customConfig,
                eventLoopGroupProvider: .shared(MultiThreadedEventLoopGroup.singleton),
                responseDecoder: JSONDecoder(),
                requestEncoder: JSONEncoder(),
                as: .custom,
                isDefault: true
            )
        }.wait()

        let containerPostCustom = try app.eventLoopGroup.next().makeFutureWithTask {
            await app.apns.containers.container()
        }.wait()
        
        XCTAssertNotNil(containerPostCustom)
        app.get("test-push2") { req -> HTTPStatus in
            let client = await req.apns.client
            XCTAssert(client === containerPostCustom?.client)
            
            return .ok
        }
        try app.test(.GET, "test-push2") { res in
            XCTAssertEqual(res.status, .ok)
        }
    }

    func testNonDefaultContainers() throws {
        let app = Application(.testing)
        defer { 
            // Shutdown APNS containers first, then the app
            try! app.eventLoopGroup.next().makeFutureWithTask {
                await app.apns.containers.shutdown()
            }.wait()
            app.shutdown() 
        }
        
        let authConfig: APNSClientConfiguration.AuthenticationMethod = .jwt(
            privateKey: try .init(pemRepresentation: appleECP8PrivateKey),
            keyIdentifier: "9UC9ZLQ8YW",
            teamIdentifier: "ABBM6U9RM5"
        )

        let apnsConfig = APNSClientConfiguration(
            authenticationMethod: authConfig,
            environment: .development
        )

        try app.eventLoopGroup.next().makeFutureWithTask {
            await app.apns.containers.use(
                apnsConfig,
                eventLoopGroupProvider: .shared(MultiThreadedEventLoopGroup.singleton),
                responseDecoder: JSONDecoder(),
                requestEncoder: JSONEncoder(),
                as: .default,
                isDefault: true
            )
        }.wait()

        let customConfig: APNSClientConfiguration = .init(
            authenticationMethod: authConfig,
            environment: .custom(url: "http://apple.com")
        )

        try app.eventLoopGroup.next().makeFutureWithTask {
            await app.apns.containers.use(
                customConfig,
                eventLoopGroupProvider: .shared(MultiThreadedEventLoopGroup.singleton),
                responseDecoder: JSONDecoder(),
                requestEncoder: JSONEncoder(),
                as: .custom
            )
        }.wait()

        let containerPostCustom = try app.eventLoopGroup.next().makeFutureWithTask {
            await app.apns.containers.container()
        }.wait()
        
        let containerNonDefaultCustom = try app.eventLoopGroup.next().makeFutureWithTask {
            await app.apns.containers.container(for: .custom)
        }.wait()
        
        let customContainer = try app.eventLoopGroup.next().makeFutureWithTask {
            await app.apns.containers.container(for: .custom)
        }.wait()
        
        XCTAssert(customContainer !== containerPostCustom)
        XCTAssertNotNil(containerPostCustom)
        app.get("test-push2") { req -> HTTPStatus in
            let customClient = await req.apns.client(.custom)
            XCTAssert(customClient !== containerPostCustom?.client)
            XCTAssert(customClient === containerNonDefaultCustom?.client)
            return .ok
        }
        try app.test(.GET, "test-push2") { res in
            XCTAssertEqual(res.status, .ok)
        }
    }
}

fileprivate extension APNSContainers.ID {
    static var custom: APNSContainers.ID {
        return .init(string: "custom")
    }
}
