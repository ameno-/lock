import XCTest
@testable import AgentCockpit

final class ACSessionTransportGenUINegotiationTests: XCTestCase {
    func testAdvertisedMethodsExtractorFindsNestedMethodArrays() {
        let result = AnyCodable([
            "capabilities": AnyCodable([
                "genui": AnyCodable([
                    "supportedMethods": AnyCodable([
                        AnyCodable("genui/action"),
                        AnyCodable("item/genui/action")
                    ])
                ])
            ]),
            "methods": AnyCodable([
                AnyCodable(["name": AnyCodable("thread/list")]),
                AnyCodable("turn/start")
            ])
        ])

        let methods = ACSessionTransport.advertisedMethods(fromInitializeResult: result)

        XCTAssertTrue(methods.contains("genui/action"))
        XCTAssertTrue(methods.contains("item/genui/action"))
        XCTAssertTrue(methods.contains("thread/list"))
        XCTAssertTrue(methods.contains("turn/start"))
    }

    func testNegotiatesACPGenUIActionMethodFromCapabilities() {
        let advertised: Set<String> = [
            "thread/list",
            "session/genui/action",
            "session/load"
        ]

        let method = ACSessionTransport.negotiateGenUIActionMethod(
            for: .acp,
            advertisedMethods: advertised
        )

        XCTAssertEqual(method, "session/genui/action")
    }

    func testNegotiatesCodexGenUIActionMethodFromCapabilities() {
        let advertised: Set<String> = [
            "thread/list",
            "item/gen_ui/action",
            "turn/start"
        ]

        let method = ACSessionTransport.negotiateGenUIActionMethod(
            for: .codex,
            advertisedMethods: advertised
        )

        XCTAssertEqual(method, "item/gen_ui/action")
    }

    func testCodexNegotiationReturnsNilWhenCapabilitiesAreNotAdvertised() {
        let method = ACSessionTransport.negotiateGenUIActionMethod(
            for: .codex,
            advertisedMethods: []
        )

        XCTAssertNil(method)
    }

    func testACPNegotiationFallsBackToPrimaryMethodWhenNoCapabilitiesProvided() {
        let method = ACSessionTransport.negotiateGenUIActionMethod(
            for: .acp,
            advertisedMethods: []
        )

        XCTAssertEqual(method, "genui/action")
    }

    func testResolveMethodReturnsPrimaryACPFallbackWhenServerDidNotAdvertiseMethods() {
        let method = ACSessionTransport.resolveGenUIActionMethod(
            for: .acp,
            advertisedMethods: []
        )

        XCTAssertEqual(method, "genui/action")
    }

    func testResolveMethodReturnsNilForCodexWhenMethodNotAdvertised() {
        let method = ACSessionTransport.resolveGenUIActionMethod(
            for: .codex,
            advertisedMethods: []
        )

        XCTAssertNil(method)
    }

    func testResolveMethodPrefersAdvertisedMatchWhenPresent() {
        let method = ACSessionTransport.resolveGenUIActionMethod(
            for: .codex,
            advertisedMethods: ["item/genui/action", "turn/start"]
        )

        XCTAssertEqual(method, "item/genui/action")
    }

    func testProbeOrderPrefersCachedMethodAndDeduplicatesCandidatesCaseInsensitive() {
        let methods = ACSessionTransport.genUIActionMethodProbeOrder(
            for: .codex,
            preferredMethod: "ITEM/GEN_UI/ACTION"
        )

        XCTAssertEqual(methods.first, "ITEM/GEN_UI/ACTION")
        XCTAssertEqual(Set(methods.map { $0.lowercased() }).count, methods.count)
    }

    @MainActor
    func testSubmitGenUIActionFallsBackWhenCodexDoesNotAdvertiseMethodAndCachesSuccess() async throws {
        let settings = ACSettingsStore()
        settings.serverProtocol = .codex

        let connection = ACGatewayConnection(settings: settings)
        var requestedMethods: [String] = []
        let transport = ACSessionTransport(
            connection: connection,
            settings: settings,
            jsonRequestHandler: { method, _, _ in
                requestedMethods.append(method)
                switch method {
                case "initialize", "thread/resume", "gen_ui/action":
                    return AnyCodable([String: AnyCodable]())
                case "genui/action", "genui/submitAction":
                    throw ACTransportError.serverError(-32601, "Method not found")
                default:
                    XCTFail("Unexpected method call: \(method)")
                    throw ACTransportError.serverError(-32601, "Unexpected method")
                }
            }
        )
        let event = GenUIEvent(
            title: "Action",
            body: "Execute action",
            actionPayload: ["actionId": AnyCodable("approve")]
        )

        XCTAssertEqual(transport.activeGenUIActionCallbackDiagnostic, .notAdvertised)
        XCTAssertEqual(requestedMethods, [])

        try await transport.submitGenUIAction(sessionKey: "thread-1", event: event)
        XCTAssertEqual(transport.activeGenUIActionCallbackDiagnostic, .method("gen_ui/action"))
        XCTAssertEqual(
            requestedMethods,
            ["initialize", "thread/resume", "genui/action", "genui/submitAction", "gen_ui/action"]
        )

        requestedMethods.removeAll()
        try await transport.submitGenUIAction(sessionKey: "thread-1", event: event)
        XCTAssertEqual(requestedMethods, ["gen_ui/action"])
    }
}
