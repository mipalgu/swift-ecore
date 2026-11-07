//
// KM3WriterTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Testing

@Suite("Writing KM3")
struct KM3WriterTests {
    /// The library fixture after one round of reading and writing.
    static let normalisedLibrary = """
        -- @nsURI http://example.org/library
        -- @nsPrefix lib
        package Library {

        \tabstract class NamedElement {
        \t\tattribute name : String;
        \t}

        \tclass Library extends NamedElement {
        \t\treference books[*] ordered container : Book oppositeOf library;
        \t\treference members[*] container : Member;
        \t\treference address container : Address;
        \t}

        \tclass Book extends NamedElement, Lendable {
        \t\tattribute isbn[0-1] : String;
        \t\tattribute pages : Integer;
        \t\tattribute keywords[*] ordered unique : String;
        \t\tattribute genre : Genre;
        \t\tattribute price[0-1] : Money;
        \t\treference library : Library oppositeOf books;
        \t\treference authors[1-*] ordered : Person;
        \t\treference "class"[0-1] : Category;
        \t\toperation lend(borrower : Member, days : Integer) : Boolean;
        \t\toperation reset();
        \t}

        \tabstract class Lendable {
        \t\tattribute available : Boolean;
        \t\tattribute rating[2-5] : Double;
        \t}

        \tclass Category extends NamedElement {
        \t}

        \tclass Address {
        \t\tattribute street : String;
        \t}

        \tenumeration Genre {
        \t\tliteral fiction;
        \t\tliteral science;
        \t\tliteral "package";
        \t}

        \tdatatype Money;
        }

        -- @nsURI http://example.org/people
        -- @nsPrefix people
        package People {

        \tclass Person {
        \t\tattribute name : String;
        \t}

        \tclass Member extends Person {
        \t\treference loans[*] : Book;
        \t}
        }

        package PrimitiveTypes {
        \tdatatype Boolean;
        \tdatatype Double;
        \tdatatype Integer;
        \tdatatype String;
        }

        """

    @Test("Writing read packages gives the normalised text without warnings")
    func writesLibrary() {
        let packages = KM3Reader.parse(KM3Fixtures.library).packages
        let written = KM3Writer.write(packages)
        #expect(written.diagnostics.isEmpty, "\(written.diagnostics)")
        #expect(written.text == Self.normalisedLibrary)
    }

    @Test("Writing is deterministic")
    func deterministic() {
        let packages = KM3Reader.parse(KM3Fixtures.library).packages
        let first = KM3Writer.write(packages).text
        for _ in 0..<5 { #expect(KM3Writer.write(packages).text == first) }
        let again = KM3Writer.write(KM3Reader.parse(KM3Fixtures.library).packages).text
        #expect(again == first)
    }

    @Test("Nested packages are written inside their parent with indented directives")
    func nested() {
        let written = KM3Writer.write(KM3Reader.parse(KM3Fixtures.nested).packages)
        #expect(written.diagnostics.isEmpty)
        #expect(written.text == KM3Fixtures.nested)
    }

    @Test("The declared mapping round-trips the primitive types package without warnings")
    func declaredPrimitives() {
        let packages = KM3Reader.parse(KM3Fixtures.library, sourceName: nil, options: .declaredDataTypes).packages
        let written = KM3Writer.write(packages)
        #expect(written.diagnostics.isEmpty, "\(written.diagnostics)")
        #expect(written.text == Self.normalisedLibrary)
    }

    @Test("Data types with the conventional Java instance class of their name are written without warnings")
    func conventionalInstanceClasses() {
        let types = KM3PrimitiveTypes.all.map { EDataType(name: $0.name, instanceClassName: $0.instanceClassName) }
        let written = KM3Writer.write([EPackage(name: "PrimitiveTypes", eClassifiers: types)])
        #expect(written.diagnostics.isEmpty, "\(written.diagnostics)")
    }

    @Test("Built-in Ecore data types are declared in an existing PrimitiveTypes package")
    func existingPrimitivePackage() {
        let primitives = EPackage(name: "PrimitiveTypes", eClassifiers: [EDataType(name: "Boolean")])
        let eClass = EClass(
            name: "C",
            eStructuralFeatures: [
                EAttribute(name: "a", eType: EcorePackage.dataType(.eString)!, lowerBound: 1),
                EAttribute(name: "b", eType: EcorePackage.dataType(.eBigInteger)!, lowerBound: 1),
                EAttribute(name: "c", eType: EcorePackage.dataType(.eIntegerObject)!, lowerBound: 1),
            ])
        let written = KM3Writer.write([primitives, EPackage(name: "P", eClassifiers: [eClass])])
        #expect(written.diagnostics.isEmpty, "\(written.diagnostics)")
        #expect(
            written.text == """
                package PrimitiveTypes {
                \tdatatype Boolean;
                \tdatatype BigInteger;
                \tdatatype EIntegerObject;
                \tdatatype String;
                }

                package P {

                \tclass C {
                \t\tattribute a ordered unique : String;
                \t\tattribute b ordered unique : BigInteger;
                \t\tattribute c ordered unique : EIntegerObject;
                \t}
                }

                """)
    }

    @Test("Names that cannot be written plainly are quoted and escaped")
    func quoting() {
        let names = ["class", "true", "", "2nd", "a b", "q\"t\\n\nl", "plain_1", "ünïcode"]
        let package = EPackage(name: "P", eClassifiers: names.map { EClass(name: $0) })
        let text = KM3Writer.write([package]).text
        let parsed = KM3Reader.parse(text)
        #expect(parsed.diagnostics.isEmpty, "\(parsed.diagnostics)")
        #expect(parsed.packages.first?.eClassifiers.map(\.name) == names)
        #expect(text.contains("class \"class\" {"))
        #expect(text.contains("class \"true\" {"))
        #expect(text.contains("class plain_1 {"))
        #expect(text.contains("class ünïcode {"))
        #expect(text.contains(#"class "q\"t\\n\nl" {"#))
    }

    @Test("Every property that KM3 cannot express is reported")
    func warnings() throws {
        let annotation = EAnnotation(source: "http://example.org/note", details: ["k": "v"])
        let string = try #require(EcorePackage.dataType(.eString))
        var dataType = EDataType(name: "Money", instanceClassName: "java.math.BigDecimal", defaultValueLiteral: "0")
        dataType.serialisable = false
        dataType.instanceTypeName = "Money<T>"
        dataType.eAnnotations = [annotation]
        var eEnum = EEnum(
            name: "Colour",
            literals: [EEnumLiteral(name: "red", value: 5, literal: "RED"), EEnumLiteral(name: "blue", value: 2)])
        eEnum.instanceClassName = "Colour"
        let target = EClass(name: "Target")
        let attribute = EAttribute(
            name: "a", eType: string, changeable: false, volatile: true, transient: true, defaultValueLiteral: "x",
            isID: true, eAnnotations: [annotation], unsettable: true, derived: true)
        let reference = EReference(
            name: "r", eType: target, resolveProxies: false, unique: false)
        let external = EReference(name: "e", eType: EClass(name: "Elsewhere"), opposite: EUUID())
        let parameter = EParameter(name: "p", eType: nil, lowerBound: 1, upperBound: -1, ordered: false, unique: false)
        let operation = EOperation(
            name: "op", eType: string, lowerBound: 1, upperBound: 2, ordered: false, unique: false,
            eParameters: [parameter], eExceptions: [target],
            eAnnotations: [EAnnotation(source: "http://www.eclipse.org/emf/2002/GenModel", details: ["body": "x"])])
        let eClass = EClass(
            name: "Holder", isInterface: true, eStructuralFeatures: [attribute, reference, external],
            eOperations: [operation], eAnnotations: [annotation], instanceClassName: "Holder")
        let package = EPackage(
            name: "P", nsURI: "http://example.org/p\nsecond", eClassifiers: [eClass, target, dataType, eEnum],
            eAnnotations: [annotation])
        let written = KM3Writer.write([package])
        let messages = written.diagnostics.map(\.message)
        #expect(written.diagnostics.allSatisfy { $0.severity == .warning && $0.range == nil })
        let expectedFragments = [
            "annotation http://example.org/note of 'P'", "nsURI that spans several lines",
            "interface flag of 'P::Holder'", "instance class name 'Holder' of 'P::Holder'",
            "default value 'x' of 'P::Holder.a'", "derived flag", "transient flag", "volatile flag",
            "unchangeable flag", "unsettable flag", "identifier flag", "non-unique flag (KM3 references are unique)",
            "flag that turns off proxy resolution", "opposite that is not part of the written packages",
            "result multiplicity [1..2]", "unordered result flag", "non-unique result flag", "the exceptions",
            "annotation http://www.eclipse.org/emf/2002/GenModel of 'P::Holder.op'",
            "parameter multiplicity [1..-1]", "unordered parameter flag", "absence of a type",
            "instance class name 'java.math.BigDecimal' of 'P::Money'", "instance type name 'Money<T>'",
            "serialisable flag", "default value '0' of 'P::Money'", "the value 5 (it becomes 1)",
            "literal text 'RED'", "instance class name 'Colour' of 'P::Colour'",
        ]
        for fragment in expectedFragments {
            #expect(messages.contains { $0.contains(fragment) }, "missing: \(fragment)")
        }
        let external_ = written.diagnostics.filter { $0.code == KM3DiagnosticCode.externalType.rawValue }
        #expect(external_.count == 1)
        #expect(external_.first?.message.contains("Elsewhere") == true)
        #expect(written.text.contains("operation op(p : EJavaObject) : String;"))
        #expect(written.text.contains("-- @nsURI http://example.org/p\n"))
        #expect(written.text.contains("datatype EJavaObject;"))
        let reread = KM3Reader.parse(written.text)
        #expect(reread.diagnostics.map(\.code) == [KM3DiagnosticCode.unresolvedType.rawValue])
    }

    @Test("Generic types, type parameters and unspecified bounds are reported")
    func generics() throws {
        let string = try #require(EcorePackage.dataType(.eString))
        var attribute = EAttribute(name: "a", eType: string, upperBound: -2)
        attribute.eGenericType = EGenericType(eClassifier: string)
        var eClass = EClass(name: "C", eStructuralFeatures: [attribute])
        eClass.eTypeParameters = [ETypeParameter(name: "T")]
        eClass.instanceTypeName = "C<T>"
        let written = KM3Writer.write([EPackage(name: "P", eClassifiers: [eClass])])
        let messages = written.diagnostics.map(\.message)
        for fragment in ["type parameters of 'P::C'", "instance type name 'C<T>'", "generic type", "upper bound -2"] {
            #expect(messages.contains { $0.contains(fragment) }, "missing: \(fragment)")
        }
        #expect(written.text.contains("attribute a[0-*] ordered unique : String;") == false)
        #expect(written.text.contains("attribute a[*] ordered unique : String;"))
    }

    @Test("Classifier names that several packages share are reported")
    func ambiguousNames() {
        let first = EPackage(name: "A", eClassifiers: [EClass(name: "Same")])
        let second = EPackage(name: "B", eClassifiers: [EClass(name: "Same"), EDataType(name: "String")])
        let user = EClass(
            name: "User", eStructuralFeatures: [EAttribute(name: "s", eType: EcorePackage.dataType(.eString)!)])
        let written = KM3Writer.write([first, second, EPackage(name: "C", eClassifiers: [user])])
        let ambiguous = written.diagnostics.filter { $0.code == KM3DiagnosticCode.ambiguousName.rawValue }
        #expect(ambiguous.count == 2)
        #expect(ambiguous.first?.message.contains("'Same'") == true)
        #expect(ambiguous.last?.message.contains("EString") == true)
    }

    @Test("Multiplicities are written in KM3 notation")
    func multiplicityNotation() throws {
        let string = try #require(EcorePackage.dataType(.eString))
        let bounds: [(Int, Int, String)] = [
            (1, 1, "a"), (0, 1, "a[0-1]"), (0, -1, "a[*]"), (1, -1, "a[1-*]"), (2, 5, "a[2-5]"), (0, 0, "a[0-0]"),
        ]
        for (lower, upper, expected) in bounds {
            let eClass = EClass(
                name: "C",
                eStructuralFeatures: [
                    EAttribute(name: "a", eType: string, lowerBound: lower, upperBound: upper, ordered: false, unique: false)
                ])
            let text = KM3Writer.write([EPackage(name: "P", eClassifiers: [eClass])]).text
            #expect(text.contains("attribute \(expected) : String;"), "\(lower)..\(upper)")
        }
    }

    @Test("Classifiers of an unknown kind are reported and left out")
    func unknownClassifier() {
        struct Foreign: EClassifier {
            let id = EUUID()
            let name = "Foreign"
        }
        let written = KM3Writer.write([EPackage(name: "P", eClassifiers: [Foreign(), EClass(name: "C")])])
        #expect(written.diagnostics.count == 1)
        #expect(written.diagnostics.first?.message.contains("'P::Foreign'") == true)
        #expect(!written.text.contains("Foreign"))
    }

    @Test("Writing nothing gives empty text")
    func empty() {
        let written = KM3Writer.write([])
        #expect(written.text.isEmpty)
        #expect(written.diagnostics.isEmpty)
    }

    @Test("Ecore classes outside the packages are reported as external types")
    func ecoreClasses() {
        let eClass = EClass(
            name: "C",
            eStructuralFeatures: [EReference(name: "any", eType: EcorePackage.metaClass(.eObject))],
            eOperations: [EOperation(name: "f", eType: EcorePackage.metaClass(.eClass))])
        let written = KM3Writer.write([EPackage(name: "P", eClassifiers: [eClass])])
        #expect(written.diagnostics.filter { $0.code == KM3DiagnosticCode.externalType.rawValue }.count == 2)
        #expect(written.text.contains("reference any[0-1] ordered : EObject;"))
        #expect(written.text.contains("package PrimitiveTypes") == false)
    }
}
