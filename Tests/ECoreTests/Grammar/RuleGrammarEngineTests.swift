//
// RuleGrammarEngineTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Testing

@testable import ECore

/// A dialect for engine tests, with Langium's lexical rules.
private let dialect = RuleGrammarDialect(
    codePrefix: "test", hasRegexLiterals: true, keywords: ["terminal"], crossReferenceSeparators: [":", "|"])

/// Parses a rule body.
///
/// - Parameter text: The body text.
/// - Returns: The element and the diagnostics.
private func body(_ text: String) -> (RuleElement?, [SourceDiagnostic]) {
    var collector = DiagnosticCollector(document: nil)
    let scanned = RuleGrammarLexer.scan(text, dialect: dialect, collector: &collector)
    var state = RuleParserState(dialect: dialect, tokens: scanned.tokens, endRange: scanned.end, collector: collector)
    let element = state.parseAlternatives()
    return (element, state.collector.diagnostics)
}

/// Runs the inference on rules in one package `p`.
///
/// - Parameters:
///   - rules: The rules.
///   - configuration: The inference settings.
/// - Returns: The filled package and the diagnostics.
private func infer(
    _ rules: [GrammarRule], configuration: RuleInferenceConfiguration = .xtext
) -> (GrammarDraftPackage, [SourceDiagnostic]) {
    var inference = RuleInference(
        configuration: configuration, dialect: dialect,
        packages: [GrammarDraftPackage(name: "p", nsURI: "urn:p", nsPrefix: "p")],
        collector: DiagnosticCollector(document: nil),
        resolver: { reference, _ in
            switch reference.name {
            case "string": .ecore(.eString)
            case "int": .ecore(.eInt)
            default: .generated(package: "p", name: reference.name)
            }
        },
        externalRule: { _ in nil })
    let drafts = inference.run(rules, inheritedRules: [GrammarRule(kind: .terminal, name: "ID")])
    return (drafts[0], inference.collector.diagnostics)
}

/// A parser rule with a parsed body.
///
/// - Parameters:
///   - name: The rule name.
///   - text: The body text.
///   - returnType: The declared return type.
/// - Returns: The rule.
private func rule(_ name: String, _ text: String, returns returnType: String? = nil) -> GrammarRule {
    GrammarRule(
        kind: .parser, name: name, returnType: returnType.map { RuleTypeReference(name: $0) }, body: body(text).0)
}

/// The draft class of a package with a name.
///
/// - Parameters:
///   - name: The class name.
///   - package: The package.
/// - Returns: The class, or `nil`.
private func draftClass(_ name: String, in package: GrammarDraftPackage) -> GrammarDraftClass? {
    if case .eClass(let value)? = package.classifier(named: name) { return value }
    return nil
}

/// Tests of the rule grammar engine.
@Suite("Rule grammar engine")
struct RuleGrammarEngineTests {
    /// Checks that the lexer reads regular expressions with classes and escapes, and reports unterminated ones.
    @Test("The lexer reads regular expressions with classes and escapes, and reports unterminated ones")
    func regexLiterals() {
        var collector = DiagnosticCollector(document: nil)
        let scanned = RuleGrammarLexer.scan(#"/[/]\/x/gi /open"#, dialect: dialect, collector: &collector)
        #expect(scanned.tokens.map(\.text) == [#"/[/]\/x/gi"#, "/open"])
        #expect(scanned.tokens.map(\.kind) == [.regex, .regex])
        #expect(collector.diagnostics.map(\.code) == ["test.unterminatedRegex"])
    }

    /// Checks that bodies parse into groups, alternatives, unordered groups, assignments and actions.
    @Test("Bodies parse into groups, alternatives, unordered groups, assignments and actions")
    func bodies() throws {
        let (element, diagnostics) = body(
            "<isX> 'a' (x=ID | y+=[T:ID])* & {infer T.left=current} f?=('k' | 'l')? => Call<true>+")
        #expect(diagnostics.isEmpty, "\(diagnostics)")
        guard case .unorderedGroup(let groups)? = element?.kind else {
            Issue.record("Expected an unordered group, got \(String(describing: element))")
            return
        }
        #expect(groups.count == 2)
        guard case .group(let first) = groups[0].kind, case .group(let second) = groups[1].kind else {
            Issue.record("Expected two groups")
            return
        }
        #expect(first[1].cardinality == .zeroOrMore)
        guard case .action(let type, "left", .assign) = second[0].kind else {
            Issue.record("Expected an assigned action")
            return
        }
        #expect(type.isInferred && type.name == "T")
        guard case .assignment("f", .flag, let terminal) = second[1].kind else {
            Issue.record("Expected a flag assignment")
            return
        }
        #expect(second[1].cardinality == .optional)
        if case .alternatives(let choices) = terminal.kind { #expect(choices.count == 2) } else {
            Issue.record("Expected keyword alternatives")
        }
        #expect(second[2].kind == .ruleCall("Call") && second[2].cardinality == .oneOrMore)
    }

    /// Checks that a missing element is reported where it is missing.
    @Test("A missing element is reported where it is missing")
    func missingElement() {
        let (element, diagnostics) = body("'a' x= ")
        #expect(element == nil)
        #expect(diagnostics.map(\.code) == ["test.unexpectedToken"])
        #expect(diagnostics.first?.range?.start.column == 8)
    }

    /// Checks that features lift over several levels and duplicates of inherited features disappear.
    @Test("Features lift over several levels and duplicates of inherited features disappear")
    func multiLevelLifting() throws {
        let (package, diagnostics) = infer([
            rule("Root", "A | B"),
            rule("A", "C | D"),
            rule("C", "'c' name=ID"),
            rule("D", "'d' name=ID"),
            rule("B", "'b' name=ID"),
        ])
        #expect(diagnostics.isEmpty, "\(diagnostics)")
        #expect(draftClass("Root", in: package)?.features.map(\.name) == ["name"])
        for name in ["A", "B", "C", "D"] { #expect(draftClass(name, in: package)?.features.isEmpty == true, "\(name)") }
    }

    /// Checks that without lifting, union rules become abstract and features stay where assigned.
    @Test("Without lifting, union rules become abstract and features stay where assigned")
    func langiumConfiguration() throws {
        let (package, _) = infer(
            [rule("Root", "A | B"), rule("A", "'a' name=ID"), rule("B", "'b' name=ID"), rule("Opt", "A?")],
            configuration: .langium)
        let root = try #require(draftClass("Root", in: package))
        #expect(root.isAbstract && root.features.isEmpty)
        #expect(draftClass("A", in: package)?.features.map(\.name) == ["name"])
        #expect(draftClass("Opt", in: package)?.isAbstract == false)
    }

    /// Checks that strings and other data types without a common type are incompatible.
    @Test("Strings and other data types without a common type are incompatible")
    func incompatibleDataTypes() {
        let (_, diagnostics) = infer([
            rule("M", "x=ID x=Num"),
            GrammarRule(kind: .terminal, name: "Num", returnType: RuleTypeReference(name: "int")),
        ])
        #expect(diagnostics.map(\.code) == ["test.incompatibleTypes"])
    }

    /// Checks that inherited rules are replaced by grammar rules of the same name and duplicates are reported.
    @Test("Inherited rules are replaced by grammar rules of the same name and duplicates are reported")
    func duplicateRules() {
        let (package, diagnostics) = infer([rule("M", "name=ID"), rule("M", "'m' other=ID")])
        #expect(diagnostics.map(\.code) == ["test.duplicateRule"])
        #expect(draftClass("M", in: package)?.features.map(\.name) == ["other"])
    }
}
