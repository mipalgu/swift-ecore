//
// OCLExpressionParserTests.swift
// OCLTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Testing

@testable import OCL


/// Writes the structure of an expression with explicit grouping, for comparing trees.
func structure(_ expression: OCLExpression) -> String {
    switch expression.kind {
    case .integerLiteral(let text), .realLiteral(let text): return text
    case .stringLiteral(let value, _): return "'\(value)'"
    case .booleanLiteral(let value): return "\(value)"
    case .nullLiteral: return "null"
    case .invalidLiteral: return "invalid"
    case .unlimitedLiteral: return "*"
    case .unspecifiedValue: return "?"
    case .selfReference: return "self"
    case .name(let path, let isPre): return path.joined(separator: "::") + (isPre ? "@pre" : "")
    case .call(let call):
        var text = call.source.map { structure($0) + (call.navigation ?? "") } ?? ""
        text += (call.qualifier + [call.name]).joined(separator: "::")
        if let arguments = call.arguments {
            var header = arguments.iterators.map { $0.name + ($0.type.map { ":" + $0.text } ?? "") }.joined(separator: ",")
            if !arguments.accumulators.isEmpty {
                header += ";" + arguments.accumulators.map { $0.name + "=" + structure($0.initialiser!) }.joined(separator: ",")
            }
            text += "(" + (arguments.hasBody ? header + "|" : "") + arguments.arguments.map(structure).joined(separator: ",") + ")"
        }
        return text + (call.isPre ? "@pre" : "")
    case .prefix(let op, let operand): return "(\(op) \(structure(operand)))"
    case .infix(let op, let left, let right): return "(\(structure(left)) \(op) \(structure(right)))"
    case .conditional(let branches, let otherwise):
        return "if " + branches.map { structure($0.condition) + "?" + structure($0.value) }.joined(separator: ";") + " else " + structure(otherwise)
    case .letExpression(let variables, let body):
        return "let " + variables.map { $0.name + "=" + structure($0.initialiser!) }.joined(separator: ",") + " in " + structure(body)
    case .collectionLiteral(let type, let parts):
        return type.text + "{" + parts.map { part in
            switch part {
            case .element(let element): return structure(element)
            case .range(let first, let last): return structure(first) + ".." + structure(last)
            }
        }.joined(separator: ",") + "}"
    case .tupleLiteral(let parts): return "Tuple{" + parts.map { $0.name + "=" + structure($0.initialiser!) }.joined(separator: ",") + "}"
    case .mapLiteral(let type, let parts): return type.text + "{" + parts.map { structure($0.key) + "->" + structure($0.value) }.joined(separator: ",") + "}"
    case .typeLiteral(let type): return "type " + type.textWithMultiplicity
    case .parenthesised(let inner): return "[" + structure(inner) + "]"
    case .indexed(let source, let terms): return structure(source) + "[" + terms.map(structure).joined(separator: ",") + "]"
    case .shadow(let type, let parts): return type.joined(separator: "::") + "{" + parts.map { $0.name + "=" + structure($0.initialiser!) }.joined(separator: ",") + "}"
    case .lambda(let body): return "Lambda{" + structure(body) + "}"
    case .message(let target, let op, let name, let arguments):
        return structure(target) + op + name + "(" + arguments.map(structure).joined(separator: ",") + ")"
    }
}

@Suite("OCL expression parser")
struct OCLExpressionParserTests {
    /// Parses text that must be a valid expression and returns its structure.
    static func parsed(_ text: String, messages: Bool = false) throws -> String {
        let result = OCLExpressionParser(allowsMessages: messages).parse(text)
        #expect(result.diagnostics.isEmpty, "\(result.diagnostics.map(\.message))")
        return structure(try #require(result.expression))
    }

    @Test("Operators follow the OCL precedence", arguments: [
        ("a or b and c", "(a or (b and c))"),
        ("a implies b or c xor d", "(a implies ((b or c) xor d))"),
        ("a = b and c <> d", "((a = b) and (c <> d))"),
        ("a < b = c", "((a < b) = c)"),
        ("a + b * c - d", "((a + (b * c)) - d)"),
        ("not a = b", "((not a) = b)"),
        ("-x.abs()", "(- x.abs())"),
        ("a - - b", "(a - (- b))"),
        ("a implies b implies c", "((a implies b) implies c)"),
        ("x > 0 and let y = x in y < 9", "((x > 0) and let y=x in (y < 9))"),
        ("a and not let b = 1 in b", "(a and (not let b=1 in b))"),
    ])
    func precedence(_ text: String, _ expected: String) throws {
        #expect(try Self.parsed(text) == expected)
    }

    @Test("Navigation, calls and iterators", arguments: [
        ("self.books->select(b | b.copies > 1)->size()", "self.books->select(b|(b.copies > 1))->size()"),
        ("books->forAll(b1, b2 | b1 <> b2 implies b1.title <> b2.title)",
         "books->forAll(b1,b2|((b1 <> b2) implies (b1.title <> b2.title)))"),
        ("books->forAll(b : Book | true)", "books->forAll(b:Book|true)"),
        ("books->iterate(b; n : Integer = 0 | n + b.copies)", "books->iterate(b;n=0|(n + b.copies))"),
        ("books->select(copies > 1)", "books->select((copies > 1))"),
        ("isAvailable()", "isAvailable()"),
        ("a?.b?->c()", "a?.b?->c()"),
        ("x.max(3)", "x.max(3)"),
        ("Kind::red", "Kind::red"),
        ("lib::Genre::fiction", "lib::Genre::fiction"),
        ("x.oclAsType(lib::Book).title", "x.oclAsType(lib::Book).title"),
        ("x.oclIsKindOf(Set(String))", "x.oclIsKindOf(type Set(String))"),
        ("count@pre + 1", "(count@pre + 1)"),
        ("self.total()@pre", "self.total()@pre"),
        ("a[1]", "a[1]"),
        ("Point{x = 1, y = 2}", "Point{x=1,y=2}"),
    ])
    func navigation(_ text: String, _ expected: String) throws {
        #expect(try Self.parsed(text) == expected)
    }

    @Test("Literals", arguments: [
        ("Set{1, 2..5}", "Set{1,2..5}"),
        ("Sequence(Integer){}", "Sequence(Integer){}"),
        ("Tuple{a = 1, b : String = 'x'}", "Tuple{a=1,b='x'}"),
        ("Map{1 with 'one'}", "Map{1->'one'}"),
        ("Map(String, Integer){}", "Map(String, Integer){}"),
        ("'con' 'cat'", "'concat'"),
        ("*", "*"),
        ("invalid", "invalid"),
        ("null", "null"),
        ("Integer", "type Integer"),
        ("Set(Book)", "type Set(Book)"),
        ("Tuple(a : Integer)", "type Tuple(a : Integer)"),
        ("Lambda{1}", "Lambda{1}"),
        ("(1 + 2) * 3", "([(1 + 2)] * 3)"),
        ("_'odd name'", "odd name"),
    ])
    func literals(_ text: String, _ expected: String) throws {
        #expect(try Self.parsed(text) == expected)
    }

    @Test("Conditionals and let expressions", arguments: [
        ("if a then 1 elseif b then 2 else 3 endif", "if a?1;b?2 else 3"),
        ("let a : Integer = 1, b = a in a + b", "let a=1,b=a in (a + b)"),
    ])
    func controlFlow(_ text: String, _ expected: String) throws {
        #expect(try Self.parsed(text) == expected)
    }

    @Test("Message expressions are read only for Complete OCL")
    func messages() throws {
        #expect(try Self.parsed("observer^update(1, ?)", messages: true) == "observer^update(1,?)")
        #expect(try Self.parsed("observer^^update()", messages: true) == "observer^^update()")
        #expect(OCLExpressionParser().parse("observer^update()").expression == nil)
    }

    @Test("Types carry multiplicities")
    func types() throws {
        var cursor = OCLTokenCursor(tokens: OCLLexer.tokenise("Set(ecore::EString[*|1])[1..*]").significantTokens, source: "")
        let type = try OCLExpressionParser().parseType(&cursor)
        #expect(type.textWithMultiplicity == "Set(ecore::EString[*|1])[+]")
        #expect(type.arguments[0].multiplicity == OCLMultiplicity(lower: 0, upper: -1, isNullFree: true))
    }

    @Test("Multiplicities have a shortest form", arguments: [
        ("[?]", "[?]"), ("[*]", "[*]"), ("[+]", "[+]"), ("[1]", "[1]"), ("[0..1]", "[?]"), ("[2..*]", "[2..*]"),
        ("[2..5|?]", "[2..5|?]"), ("[1..1]", "[1]"),
    ])
    func multiplicities(_ text: String, _ expected: String) throws {
        var cursor = OCLTokenCursor(tokens: OCLLexer.tokenise(text).significantTokens, source: text)
        #expect(try OCLExpressionParser.parseMultiplicity(&cursor).text == expected)
    }

    @Test("Errors carry the position of the offending token", arguments: [
        ("a and", 1, 6, OCLDiagnosticCode.unexpectedEnd),
        ("a +\n  ) b", 2, 3, OCLDiagnosticCode.unexpectedToken),
        ("if a then b endif", 1, 13, OCLDiagnosticCode.unexpectedToken),
        ("a b", 1, 3, OCLDiagnosticCode.unexpectedToken),
        ("x->forAll(", 1, 11, OCLDiagnosticCode.unexpectedEnd),
    ])
    func errors(_ text: String, _ line: Int, _ column: Int, _ code: String) throws {
        let result = OCLExpressionParser().parse(text)
        #expect(result.expression == nil)
        let diagnostic = try #require(result.diagnostics.first)
        #expect(diagnostic.code == code)
        #expect(diagnostic.range?.start.line == line)
        #expect(diagnostic.range?.start.column == column)
    }

    @Test("Ranges cover the source text of each expression")
    func ranges() throws {
        let text = "  self.books->size() > 0  "
        let result = OCLExpressionParser().parse(text)
        let expression = try #require(result.expression)
        #expect(expression.range.start.utf8Offset == 2)
        #expect(expression.range.end.utf8Offset == 24)
        guard case .infix(_, let left, _) = expression.kind else { Issue.record("not infix"); return }
        #expect(left.range.end.utf8Offset == 20)
    }

    @Test("An expression ends where the next token cannot continue it")
    func embedded() throws {
        let text = "a > 0 inv next: b"
        var cursor = OCLTokenCursor(tokens: OCLLexer.tokenise(text).significantTokens, source: text)
        let expression = try OCLExpressionParser().parseExpression(&cursor)
        #expect(structure(expression) == "(a > 0)")
        #expect(cursor.current.isWord("inv"))
        #expect(cursor.text(of: expression.range) == "a > 0")
    }
}
