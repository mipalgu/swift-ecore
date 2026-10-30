//
// ModellingSemanticsTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import Foundation
import Testing

@testable import ECore

@Suite("Modelling semantics")
struct ModellingSemanticsTests {
    /// The name of the environment variable, as documented.
    private let variable = "SWIFT_MODELLING_SEMANTICS"

    @Test("the semantics are spelt as on the command line")
    func spellings() {
        #expect(ModellingSemantics.allCases == [.standard, .legacy])
        #expect(ModellingSemantics.standard.rawValue == "standard")
        #expect(ModellingSemantics.legacy.rawValue == "legacy")
        #expect(ModellingSemantics.environmentVariable == variable)
    }

    @Test("each semantics selects a container lookup scope")
    func containerLookupScopes() {
        #expect(ContainerLookupScope(semantics: .standard) == .standard)
        #expect(ContainerLookupScope(semantics: .legacy) == .legacy)
    }

    @Test("the environment selects the semantics", arguments: ModellingSemantics.allCases)
    func environmentValue(semantics: ModellingSemantics) throws {
        #expect(try ModellingSemantics.fromEnvironment([variable: semantics.rawValue]) == semantics)
    }

    @Test("an unset or empty variable selects nothing")
    func unsetVariable() throws {
        #expect(try ModellingSemantics.fromEnvironment([:]) == nil)
        #expect(try ModellingSemantics.fromEnvironment(["OTHER": "legacy"]) == nil)
        #expect(try ModellingSemantics.fromEnvironment([variable: ""]) == nil)
    }

    @Test("an invalid value names the variable, the value and the accepted values")
    func invalidValue() {
        for value in ["Legacy", "eclipse", " standard"] {
            #expect(throws: ModellingSemanticsError.invalidValue(value, variable: variable)) {
                try ModellingSemantics.fromEnvironment([variable: value])
            }
            let message = ModellingSemanticsError.invalidValue(value, variable: variable).description
            #expect(message.contains(variable))
            #expect(message.contains("'\(value)'"))
            #expect(message.contains("standard"))
            #expect(message.contains("legacy"))
        }
    }

    @Test("the process environment is read by default")
    func processEnvironment() throws {
        let expected = try ModellingSemantics.fromEnvironment(ProcessInfo.processInfo.environment)
        #expect(try ModellingSemantics.fromEnvironment() == expected)
    }
}
