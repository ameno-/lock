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
}
