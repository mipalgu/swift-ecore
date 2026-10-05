//
// EcoreValidatorTests.swift
// ECoreTests
//
//  Created by Rene Hexel on 5/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ECore

/// Builds small metamodels and runs the validator over them.
enum ValidationFixtures {
    static var string: any EClassifier { EcorePackage.dataType(.eString)! }
    static var int: any EClassifier { EcorePackage.dataType(.eInt)! }
    static var boolean: any EClassifier { EcorePackage.dataType(.eBoolean)! }

    /// A package with sensible names and a namespace, holding the given classifiers.
    static func package(
        _ classifiers: [any EClassifier], name: String = "lib", nsURI: String = "http://example.org/lib",
        nsPrefix: String = "lib", subpackages: [EPackage] = []
    ) -> EPackage {
        EPackage(
            name: name, nsURI: nsURI, nsPrefix: nsPrefix, eClassifiers: classifiers,
            eSubpackages: subpackages)
    }

    /// Validates a package with default options.
    static func validate(
        _ root: EPackage, options: EcoreValidator.Options = .init()
    ) -> [EcoreDiagnostic] {
        EcoreValidator(options: options).validate(MetamodelIndex(roots: [root]))
    }

    /// The diagnostics of one constraint.
    static func diagnostics(
        _ code: EcoreConstraint, in root: EPackage, options: EcoreValidator.Options = .init()
    ) -> [EcoreDiagnostic] {
        validate(root, options: options).filter { $0.code == code }
    }

    /// A class with a single feature.
    static func owner(_ feature: any EStructuralFeature, name: String = "Owner") -> EClass {
        EClass(name: name, eStructuralFeatures: [feature])
    }
}

@Suite("EcoreValidator: naming and packages")
struct EcoreValidatorNamingTests {
    typealias F = ValidationFixtures

    @Test("a clean metamodel produces no diagnostics")
    func clean() {
        let package = F.package([F.owner(EAttribute(name: "title", eType: F.string))])
        #expect(F.validate(package).isEmpty)
    }

    @Test("well-formed names pass and malformed names fail")
    func wellFormedName() throws {
        let good = F.package([F.owner(EAttribute(name: "_title2", eType: F.string))])
        #expect(F.diagnostics(.wellFormedName, in: good).isEmpty)
        let bad = F.package([EClass(name: "Not Valid"), EClass(name: "1st"), EClass(name: ""), EClass(name: "a$b")])
        let found = F.diagnostics(.wellFormedName, in: bad)
        #expect(found.count == 4)
        #expect(found.allSatisfy { $0.severity == .error && $0.feature == .name })
        #expect(found[0].arguments == ["Not Valid"])
        #expect(found[0].message == "The name 'Not Valid' is not well formed.")
    }

    @Test("identifiers may contain ignorable control characters, digits, and marks")
    func identifierCharacters() {
        let package = F.package([EClass(name: "a\u{1}b"), EClass(name: "caf\u{E9}"), EClass(name: "x\u{301}2")])
        #expect(F.diagnostics(.wellFormedName, in: package).isEmpty)
        #expect(F.diagnostics(.wellFormedName, in: F.package([EClass(name: "a\u{9}b")])).count == 1)
    }

    @Test("names that are not Java identifiers are accepted without strict names")
    func lenientNames() {
        let bad = F.package([EClass(name: "Not Valid")])
        let options = EcoreValidator.Options(strictNames: false)
        #expect(F.diagnostics(.wellFormedName, in: bad, options: options).isEmpty)
    }

    @Test("a namespace URI must be well formed")
    func wellFormedNsURI() {
        #expect(F.diagnostics(.wellFormedNsURI, in: F.package([])).isEmpty)
        #expect(F.diagnostics(.wellFormedNsURI, in: F.package([], nsURI: "http://x/a%20b")).isEmpty)
        for bad in ["", "has space", "bad%zz", "<angle>", "tail%2"] {
            let found = F.diagnostics(.wellFormedNsURI, in: F.package([], nsURI: bad))
            #expect(found.count == 1, "\(bad)")
            #expect(found.first?.feature == .nsURI)
        }
    }

    @Test("a namespace prefix must be an NCName that does not start with xml")
    func wellFormedNsPrefix() {
        for good in ["", "lib", "a.b-c_d", "_x", "a\u{301}b"] {
            #expect(F.diagnostics(.wellFormedNsPrefix, in: F.package([], nsPrefix: good)).isEmpty, "\(good)")
        }
        for bad in ["1a", "a:b", "XmlThing", "xml", "a b"] {
            let found = F.diagnostics(.wellFormedNsPrefix, in: F.package([], nsPrefix: bad))
            #expect(found.count == 1, "\(bad)")
            #expect(found.first?.feature == .nsPrefix)
        }
        let xml = F.package([], nsURI: "http://www.w3.org/XML/1998/namespace", nsPrefix: "xml")
        #expect(F.diagnostics(.wellFormedNsPrefix, in: xml).isEmpty)
    }

    @Test("subpackages must have different names")
    func uniqueSubpackageNames() {
        let a = EPackage(name: "a", nsURI: "http://x/a", nsPrefix: "a")
        let b = EPackage(name: "a", nsURI: "http://x/b", nsPrefix: "b")
        let c = EPackage(name: "c", nsURI: "http://x/c", nsPrefix: "c")
        #expect(F.diagnostics(.uniqueSubpackageNames, in: F.package([], subpackages: [a, c])).isEmpty)
        let root = F.package([], subpackages: [a, b])
        let found = F.diagnostics(.uniqueSubpackageNames, in: root)
        #expect(found.count == 1)
        #expect(found[0].element == root.id)
        #expect(found[0].feature == .eSubpackages)
        #expect(found[0].related == [a.id, b.id])
        #expect(found[0].arguments == ["a"])
    }

    @Test("classifier names must be unique; names that differ only by case or underscores warn")
    func uniqueClassifierNames() {
        let clean = F.package([EClass(name: "A"), EClass(name: "B")])
        #expect(F.diagnostics(.uniqueClassifierNames, in: clean).isEmpty)
        let duplicate = F.package([EClass(name: "A"), EEnum(name: "A")])
        let errors = F.diagnostics(.uniqueClassifierNames, in: duplicate)
        #expect(errors.count == 1)
        #expect(errors[0].severity == .error)
        #expect(errors[0].feature == .eClassifiers)
        #expect(errors[0].element == duplicate.id)
        #expect(errors[0].related.count == 2)
        let similar = F.package([EClass(name: "Foo_Bar"), EClass(name: "fooBar")])
        let warnings = F.diagnostics(.uniqueClassifierNames, in: similar)
        #expect(warnings.count == 1)
        #expect(warnings[0].severity == .warning)
        #expect(warnings[0].arguments == ["Foo_Bar", "fooBar"])
    }

    @Test("namespace URIs must be unique across packages")
    func uniqueNsURIs() {
        let inner = EPackage(name: "inner", nsURI: "http://example.org/lib", nsPrefix: "in")
        let clash = F.package([], subpackages: [inner])
        let found = F.diagnostics(.uniqueNsURIs, in: clash)
        #expect(found.count == 2)
        #expect(found.allSatisfy { $0.feature == .nsURI && $0.arguments == ["http://example.org/lib"] })
        #expect(Set(found.map(\.element)) == [clash.id, inner.id])
        let fine = EPackage(name: "inner", nsURI: "http://example.org/inner", nsPrefix: "in")
        #expect(F.diagnostics(.uniqueNsURIs, in: F.package([], subpackages: [fine])).isEmpty)
    }

    @Test("an annotation source must be a well-formed URI")
    func wellFormedSourceURI() {
        let good = EClass(name: "A", eAnnotations: [EAnnotation(source: "http://www.eclipse.org/emf/2002/GenModel")])
        #expect(F.diagnostics(.wellFormedSourceURI, in: F.package([good])).isEmpty)
        let bad = EClass(name: "A", eAnnotations: [EAnnotation(source: "not a uri")])
        let found = F.diagnostics(.wellFormedSourceURI, in: F.package([bad]))
        #expect(found.count == 1)
        #expect(found[0].feature == .source)
        #expect(found[0].arguments == ["not a uri"])
    }

    @Test("an instance class name must be well formed")
    func wellFormedInstanceTypeName() {
        let names = ["java.lang.String", "int", "java.util.Map$Entry", "java.util.List<java.lang.String>",
            "java.util.Map<?, ? extends java.lang.Number>", "byte[]", "Swift.String"]
        for name in names {
            let package = F.package([EDataType(name: "T", instanceClassName: name)])
            #expect(F.diagnostics(.wellFormedInstanceTypeName, in: package).isEmpty, "\(name)")
        }
        let bad = ["java..lang", ".x", "x.", "a b", "java.util.List<", "java.util.List<>", "x[", "1x", "a,b"]
        for name in bad {
            let package = F.package([EDataType(name: "T", instanceClassName: name)])
            let found = F.diagnostics(.wellFormedInstanceTypeName, in: package)
            #expect(found.count == 1, "\(name)")
            #expect(found.first?.feature == .instanceClassName)
        }
        let eClass = F.package([EClass(name: "C", instanceClassName: "a b")])
        #expect(F.diagnostics(.wellFormedInstanceTypeName, in: eClass).count == 1)
        #expect(F.diagnostics(.wellFormedInstanceTypeName, in: F.package([EDataType(name: "T")])).isEmpty)
    }
}

@Suite("EcoreValidator: classes")
struct EcoreValidatorClassTests {
    typealias F = ValidationFixtures

    @Test("an interface must be abstract")
    func interfaceIsAbstract() {
        let good = F.package([EClass(name: "I", isAbstract: true, isInterface: true), EClass(name: "C")])
        #expect(F.diagnostics(.interfaceIsAbstract, in: good).isEmpty)
        let bad = EClass(name: "I", isInterface: true)
        let found = F.diagnostics(.interfaceIsAbstract, in: F.package([bad]))
        #expect(found.count == 1)
        #expect(found[0].element == bad.id)
        #expect(found[0].feature == .abstract)
    }

    @Test("a class may have at most one ID attribute, including inherited ones")
    func atMostOneID() {
        let a = EAttribute(name: "a", eType: F.string, isID: true)
        let b = EAttribute(name: "b", eType: F.string, isID: true)
        let single = F.package([F.owner(a)])
        #expect(F.diagnostics(.atMostOneID, in: single).isEmpty)
        let base = EClass(name: "Base", eStructuralFeatures: [a])
        let derived = EClass(name: "Derived", eSuperTypes: [base], eStructuralFeatures: [b])
        let found = F.diagnostics(.atMostOneID, in: F.package([base, derived]))
        #expect(found.count == 1)
        #expect(found[0].element == derived.id)
        #expect(found[0].arguments == ["a", "b"])
        #expect(found[0].related == [a.id, b.id])
    }

    @Test("feature names must be unique, including inherited features")
    func uniqueFeatureNames() {
        let clean = F.package([F.owner(EAttribute(name: "a", eType: F.string))])
        #expect(F.diagnostics(.uniqueFeatureNames, in: clean).isEmpty)
        let twice = EClass(
            name: "C",
            eStructuralFeatures: [EAttribute(name: "a", eType: F.string), EAttribute(name: "a", eType: F.int)])
        let errors = F.diagnostics(.uniqueFeatureNames, in: F.package([twice]))
        #expect(errors.count == 1)
        #expect(errors[0].severity == .error)
        #expect(errors[0].feature == .eStructuralFeatures)
        let similar = EClass(
            name: "C",
            eStructuralFeatures: [EAttribute(name: "foo_bar", eType: F.string), EAttribute(name: "fooBar", eType: F.int)])
        let warnings = F.diagnostics(.uniqueFeatureNames, in: F.package([similar]))
        #expect(warnings.count == 1)
        #expect(warnings[0].severity == .warning)
        let base = EClass(name: "Base", eStructuralFeatures: [EAttribute(name: "x", eType: F.string)])
        let derived = EClass(name: "Derived", eSuperTypes: [base], eStructuralFeatures: [EAttribute(name: "x", eType: F.string)])
        let inherited = F.diagnostics(.uniqueFeatureNames, in: F.package([base, derived]))
        #expect(inherited.count == 1)
        #expect(inherited[0].element == derived.id)
        let grand = EClass(name: "Grand", eSuperTypes: [twice])
        let reported = F.diagnostics(.uniqueFeatureNames, in: F.package([twice, grand]))
        #expect(reported.map(\.element) == [twice.id])
    }

    @Test("operations with the same signature clash")
    func uniqueOperationSignatures() {
        let p1 = EOperation(name: "f", eParameters: [EParameter(name: "x", eType: F.int)])
        let p2 = EOperation(name: "f", eParameters: [EParameter(name: "y", eType: F.string)])
        let ok = EClass(name: "C", eOperations: [p1, p2])
        #expect(F.diagnostics(.uniqueOperationSignatures, in: F.package([ok])).isEmpty)
        let p3 = EOperation(name: "f", eParameters: [EParameter(name: "z", eType: F.int)])
        let bad = EClass(name: "C", eOperations: [p1, p3])
        let found = F.diagnostics(.uniqueOperationSignatures, in: F.package([bad]))
        #expect(found.count == 1)
        #expect(found[0].element == bad.id)
        #expect(found[0].feature == .eOperations)
        #expect(found[0].related == [p1.id, p3.id])
        let many = EOperation(name: "f", eParameters: [EParameter(name: "x", eType: F.int, upperBound: -1)])
        #expect(F.diagnostics(.uniqueOperationSignatures, in: F.package([EClass(name: "C", eOperations: [p1, many])])).isEmpty)
    }

    @Test("an operation must not duplicate a feature accessor")
    func disjointFeatureAndOperationSignatures() {
        let feature = EAttribute(name: "title", eType: F.string)
        let ok = EClass(name: "C", eStructuralFeatures: [feature], eOperations: [EOperation(name: "other")])
        #expect(F.diagnostics(.disjointFeatureAndOperationSignatures, in: F.package([ok])).isEmpty)
        let getter = EOperation(name: "getTitle", eType: F.string)
        let bad = EClass(name: "C", eStructuralFeatures: [feature], eOperations: [getter])
        let found = F.diagnostics(.disjointFeatureAndOperationSignatures, in: F.package([bad]))
        #expect(found.count == 1)
        #expect(found[0].related == [getter.id, feature.id])
        let flag = EAttribute(name: "done", eType: F.boolean)
        let isser = EOperation(name: "isDone", eType: F.boolean)
        let setter = EOperation(name: "setDone", eParameters: [EParameter(name: "done", eType: F.boolean)])
        let both = EClass(name: "D", eStructuralFeatures: [flag], eOperations: [isser, setter])
        #expect(F.diagnostics(.disjointFeatureAndOperationSignatures, in: F.package([both])).count == 2)
    }

    @Test("a class must not be its own supertype")
    func noCircularSuperTypes() {
        let a = EClass(name: "A")
        let b = EClass(name: "B", eSuperTypes: [a])
        #expect(F.diagnostics(.noCircularSuperTypes, in: F.package([a, b])).isEmpty)
        var cyclicA = a
        cyclicA.eSuperTypes = [b]
        let found = F.diagnostics(.noCircularSuperTypes, in: F.package([cyclicA, b]))
        #expect(Set(found.map(\.element)) == [a.id, b.id])
        #expect(found.allSatisfy { $0.feature == .eSuperTypes })
        let selfish = EClass(name: "S")
        var loop = selfish
        loop.eSuperTypes = [selfish]
        #expect(F.diagnostics(.noCircularSuperTypes, in: F.package([loop])).count == 1)
    }

    @Test("a map entry class needs key and value features")
    func wellFormedMapEntryClass() {
        let entryName = "java.util.Map$Entry"
        let key = EAttribute(name: "key", eType: F.string)
        let value = EAttribute(name: "value", eType: F.string)
        let good = EClass(name: "Entry", eStructuralFeatures: [key, value], instanceClassName: entryName)
        #expect(F.diagnostics(.wellFormedMapEntryClass, in: F.package([good])).isEmpty)
        let missing = EClass(name: "Entry", eStructuralFeatures: [key], instanceClassName: entryName)
        let found = F.diagnostics(.wellFormedMapEntryClass, in: F.package([missing]))
        #expect(found.count == 1)
        #expect(found[0].arguments == ["value"])
        let none = EClass(name: "Entry", instanceClassName: entryName)
        #expect(F.diagnostics(.wellFormedMapEntryClass, in: F.package([none])).count == 2)
        let sub = EClass(name: "Sub", eSuperTypes: [good])
        let subFound = F.diagnostics(.wellFormedMapEntryClass, in: F.package([good, sub]))
        #expect(subFound.count == 1)
        #expect(subFound[0].element == sub.id)
    }
}

@Suite("EcoreValidator: typed elements and features")
struct EcoreValidatorFeatureTests {
    typealias F = ValidationFixtures

    @Test("lower bounds must not be negative")
    func validLowerBound() {
        #expect(F.diagnostics(.validLowerBound, in: F.package([F.owner(EAttribute(name: "a", eType: F.string))])).isEmpty)
        let bad = F.package([F.owner(EAttribute(name: "a", eType: F.string, lowerBound: -1))])
        let found = F.diagnostics(.validLowerBound, in: bad)
        #expect(found.count == 1)
        #expect(found[0].feature == .lowerBound)
        #expect(found[0].arguments == ["-1"])
    }

    @Test("upper bounds must be positive, -1, or -2")
    func validUpperBound() {
        for good in [1, 5, -1, -2] {
            let package = F.package([F.owner(EAttribute(name: "a", eType: F.string, upperBound: good))])
            #expect(F.diagnostics(.validUpperBound, in: package).isEmpty, "\(good)")
        }
        for bad in [0, -3] {
            let package = F.package([F.owner(EAttribute(name: "a", eType: F.string, upperBound: bad))])
            let found = F.diagnostics(.validUpperBound, in: package)
            #expect(found.count == 1, "\(bad)")
            #expect(found.first?.feature == .upperBound)
        }
    }

    @Test("the lower bound must not exceed a bounded upper bound")
    func consistentBounds() {
        let good = F.package([F.owner(EAttribute(name: "a", eType: F.string, lowerBound: 2, upperBound: -1))])
        #expect(F.diagnostics(.consistentBounds, in: good).isEmpty)
        let bad = F.package([F.owner(EAttribute(name: "a", eType: F.string, lowerBound: 3, upperBound: 2))])
        let found = F.diagnostics(.consistentBounds, in: bad)
        #expect(found.count == 1)
        #expect(found[0].arguments == ["3", "2"])
    }

    @Test("attributes need data types and references need classes")
    func validType() {
        let target = EClass(name: "Target")
        let good = EClass(
            name: "C",
            eStructuralFeatures: [EAttribute(name: "a", eType: F.string), EReference(name: "r", eType: target)])
        #expect(F.diagnostics(.validType, in: F.package([good, target])).isEmpty)
        let badAttribute = EAttribute(name: "a", eType: target)
        let badReference = EReference(name: "r", eType: F.string)
        let bad = EClass(name: "C", eStructuralFeatures: [badAttribute, badReference])
        let found = F.diagnostics(.validType, in: F.package([bad, target]))
        #expect(found.map(\.element) == [badAttribute.id, badReference.id])
        #expect(found.allSatisfy { $0.feature == .eType })
        let untyped = EClass(name: "U", eOperations: [EOperation(name: "f", eParameters: [EParameter(name: "p")])])
        #expect(F.diagnostics(.validType, in: F.package([untyped])).count == 1)
    }

    @Test("a void operation cannot repeat")
    func noRepeatingVoid() {
        let ok = EOperation(name: "f", upperBound: 1)
        let typed = EOperation(name: "g", eType: F.string, upperBound: -1)
        #expect(F.diagnostics(.noRepeatingVoid, in: F.package([EClass(name: "C", eOperations: [ok, typed])])).isEmpty)
        let bad = EOperation(name: "h", upperBound: -1)
        let found = F.diagnostics(.noRepeatingVoid, in: F.package([EClass(name: "C", eOperations: [bad])]))
        #expect(found.count == 1)
        #expect(found[0].element == bad.id)
        #expect(found[0].arguments == ["-1"])
    }

    @Test("parameter names must be unique")
    func uniqueParameterNames() {
        let ok = EOperation(name: "f", eParameters: [EParameter(name: "a", eType: F.int), EParameter(name: "b", eType: F.int)])
        #expect(F.diagnostics(.uniqueParameterNames, in: F.package([EClass(name: "C", eOperations: [ok])])).isEmpty)
        let bad = EOperation(name: "f", eParameters: [EParameter(name: "a", eType: F.int), EParameter(name: "a", eType: F.int)])
        let found = F.diagnostics(.uniqueParameterNames, in: F.package([EClass(name: "C", eOperations: [bad])]))
        #expect(found.count == 1)
        #expect(found[0].element == bad.id)
        #expect(found[0].feature == .eParameters)
    }

    @Test("default value literals must suit the attribute type")
    func validDefaultValueLiteral() {
        let kind = EEnum(name: "Kind", literals: [EEnumLiteral(name: "A", value: 0, literal: "a"), EEnumLiteral(name: "B", value: 1)])
        let valid: [(any EClassifier, String)] = [
            (F.int, "42"), (F.boolean, "true"), (F.string, "anything"), (kind, "a"), (kind, "B"),
            (EDataType(name: "Custom", instanceClassName: "x.Y"), "whatever"),
        ]
        for (type, literal) in valid {
            let package = F.package([F.owner(EAttribute(name: "a", eType: type, defaultValueLiteral: literal)), kind])
            #expect(F.diagnostics(.validDefaultValueLiteral, in: package).isEmpty, "\(literal)")
        }
        let invalid: [(any EClassifier, String)] = [(F.int, "x"), (F.boolean, "maybe"), (kind, "C")]
        for (type, literal) in invalid {
            let package = F.package([F.owner(EAttribute(name: "a", eType: type, defaultValueLiteral: literal)), kind])
            let found = F.diagnostics(.validDefaultValueLiteral, in: package)
            #expect(found.count == 1, "\(literal)")
            #expect(found.first?.feature == .defaultValueLiteral)
            #expect(found.first?.arguments == [literal])
            #expect(found.first?.severity == (type is EEnum ? .warning : .error))
        }
        let plain = F.package([F.owner(EReference(name: "r", eType: EClass(name: "T")))])
        #expect(F.diagnostics(.validDefaultValueLiteral, in: plain).isEmpty)
    }

    @Test("a reference cannot have a default value literal, and neither can a class-typed attribute")
    func defaultValueOnReference() {
        var reference = EReference(name: "r", eType: EClass(name: "T"))
        reference.defaultValueLiteral = "x"
        let found = F.diagnostics(.validDefaultValueLiteral, in: F.package([F.owner(reference)]))
        #expect(found.count == 1)
        #expect(found[0].element == reference.id)
        let classTyped = EAttribute(name: "a", eType: EClass(name: "T"), defaultValueLiteral: "x")
        #expect(F.diagnostics(.validDefaultValueLiteral, in: F.package([F.owner(classTyped)])).count == 1)
    }

    @Test("date default literals must be dates")
    func dateDefaultLiteral() throws {
        let date = try #require(EcorePackage.dataType(.eDate))
        let good = F.package([F.owner(EAttribute(name: "d", eType: date, defaultValueLiteral: "2026-10-05T10:00:00Z"))])
        #expect(F.diagnostics(.validDefaultValueLiteral, in: good).isEmpty)
        let bad = F.package([F.owner(EAttribute(name: "d", eType: date, defaultValueLiteral: "yesterday"))])
        #expect(F.diagnostics(.validDefaultValueLiteral, in: bad).count == 1)
    }

    @Test("a non-transient attribute needs a serialisable type")
    func consistentTransient() {
        let opaque = EDataType(name: "Opaque", serialisable: false)
        let transient = F.package([F.owner(EAttribute(name: "a", eType: opaque, transient: true)), opaque])
        #expect(F.diagnostics(.consistentTransient, in: transient).isEmpty)
        let serial = F.package([F.owner(EAttribute(name: "a", eType: F.string))])
        #expect(F.diagnostics(.consistentTransient, in: serial).isEmpty)
        let bad = F.package([F.owner(EAttribute(name: "a", eType: opaque)), opaque])
        let found = F.diagnostics(.consistentTransient, in: bad)
        #expect(found.count == 1)
        #expect(found[0].feature == .transient)
        #expect(found[0].arguments == ["Owner.a"])
    }
}

@Suite("EcoreValidator: references")
struct EcoreValidatorReferenceTests {
    typealias F = ValidationFixtures

    /// A pair of classes joined by opposite references, which a test may then adjust.
    struct Pair {
        var a: EClass
        var b: EClass
        var ab: EReference
        var ba: EReference

        init(adjust: (inout EReference, inout EReference) -> Void = { _, _ in }) {
            var a = EClass(name: "A")
            var b = EClass(name: "B")
            var ab = EReference(name: "ab", eType: b)
            var ba = EReference(name: "ba", eType: a)
            ab.opposite = ba.id
            ba.opposite = ab.id
            adjust(&ab, &ba)
            a.eStructuralFeatures = [ab]
            b.eStructuralFeatures = [ba]
            self.a = a
            self.b = b
            self.ab = ab
            self.ba = ba
        }

        var package: EPackage { F.package([a, b]) }
    }

    @Test("a matching pair of opposites is consistent")
    func oppositeConsistent() {
        #expect(F.diagnostics(.consistentOpposite, in: Pair().package).isEmpty)
    }

    @Test("the opposite of the opposite must be the reference itself")
    func oppositeNotMatching() {
        let idA = EUUID()
        let idB = EUUID()
        var one = EReference(name: "one", eType: EClass(id: idB, name: "B"))
        var two = EReference(name: "two", eType: EClass(id: idA, name: "A"))
        let other = EReference(name: "other", eType: EClass(id: idA, name: "A"))
        one.opposite = two.id
        two.opposite = other.id
        let classA = EClass(id: idA, name: "A", eStructuralFeatures: [one, other])
        let classB = EClass(id: idB, name: "B", eStructuralFeatures: [two])
        let found = F.diagnostics(.consistentOpposite, in: F.package([classA, classB]))
        #expect(found.contains { $0.template == .oppositeNotMatching && $0.element == one.id })
    }

    @Test("the opposite must be a feature of the reference's type")
    func oppositeNotFromType() {
        let idA = EUUID()
        let idB = EUUID()
        var ab = EReference(name: "ab", eType: EClass(id: idB, name: "B"))
        var stray = EReference(name: "stray", eType: EClass(id: idA, name: "A"))
        ab.opposite = stray.id
        stray.opposite = ab.id
        let a = EClass(id: idA, name: "A", eStructuralFeatures: [ab])
        let b = EClass(id: idB, name: "B")
        let c = EClass(name: "C", eStructuralFeatures: [stray])
        let found = F.diagnostics(.consistentOpposite, in: F.package([a, b, c]))
        #expect(found.contains { $0.template == .oppositeNotFromType && $0.element == ab.id })
    }

    @Test("a reference must not be its own opposite")
    func selfOpposite() {
        let idA = EUUID()
        var self1 = EReference(name: "me", eType: EClass(id: idA, name: "A"))
        self1.opposite = self1.id
        let a = EClass(id: idA, name: "A", eStructuralFeatures: [self1])
        let found = F.diagnostics(.consistentOpposite, in: F.package([a]))
        #expect(found.contains { $0.template == .selfOpposite })
    }

    @Test("the opposite of a transient reference must be transient")
    func oppositeTransient() {
        let bad = Pair { ab, _ in ab.transient = true }
        let found = F.diagnostics(.consistentOpposite, in: bad.package)
        #expect(found.count == 1)
        #expect(found[0].template == .oppositeNotTransient)
        #expect(found[0].element == bad.ab.id)
        let fine = Pair { ab, ba in
            ab.transient = true
            ba.transient = true
        }
        #expect(F.diagnostics(.consistentOpposite, in: fine.package).isEmpty)
    }

    @Test("opposites must not both be containments")
    func oppositeBothContainment() {
        let bad = Pair { ab, ba in
            ab.containment = true
            ba.containment = true
        }
        let found = F.diagnostics(.consistentOpposite, in: bad.package)
        #expect(found.count == 2)
        #expect(found.allSatisfy { $0.template == .oppositeBothContainment })
    }

    @Test("a container reference must be single-valued")
    func singleContainer() {
        let ok = F.package([F.owner(EReference(name: "parent", eType: EClass(name: "P"), container: true))])
        #expect(F.diagnostics(.singleContainer, in: ok).isEmpty)
        let bad = F.package([F.owner(EReference(name: "parent", eType: EClass(name: "P"), upperBound: -1, container: true))])
        let found = F.diagnostics(.singleContainer, in: bad)
        #expect(found.count == 1)
        #expect(found[0].feature == .upperBound)
        #expect(found[0].arguments == ["-1"])
    }

    @Test("a containment's type must not require another container")
    func consistentContainer() {
        var child = EClass(name: "Child")
        let parentRef = EReference(name: "parent", eType: EClass(name: "Parent"), lowerBound: 1, container: true)
        child.eStructuralFeatures = [parentRef]
        let contains = EReference(name: "children", eType: child, upperBound: -1, containment: true)
        let parent = EClass(name: "Parent", eStructuralFeatures: [contains])
        let found = F.diagnostics(.consistentContainer, in: F.package([parent, child]))
        #expect(found.count == 1)
        #expect(found[0].element == contains.id)
        #expect(found[0].arguments == ["parent"])
        var oppositeContains = contains
        var oppositeParent = parentRef
        oppositeContains.opposite = oppositeParent.id
        oppositeParent.opposite = oppositeContains.id
        let childOK = EClass(id: child.id, name: "Child", eStructuralFeatures: [oppositeParent])
        let parentOK = EClass(id: parent.id, name: "Parent", eStructuralFeatures: [oppositeContains])
        #expect(F.diagnostics(.consistentContainer, in: F.package([parentOK, childOK])).isEmpty)
    }

    @Test("many-valued containments and bidirectionals must be unique")
    func consistentUnique() {
        let ok = F.package([F.owner(EReference(name: "r", eType: EClass(name: "T"), upperBound: -1, containment: true))])
        #expect(F.diagnostics(.consistentUnique, in: ok).isEmpty)
        let plain = F.package([F.owner(EReference(name: "r", eType: EClass(name: "T"), upperBound: -1, unique: false))])
        #expect(F.diagnostics(.consistentUnique, in: plain).isEmpty)
        let bad = F.package([F.owner(EReference(name: "r", eType: EClass(name: "T"), upperBound: -1, containment: true, unique: false))])
        let found = F.diagnostics(.consistentUnique, in: bad)
        #expect(found.count == 1)
        #expect(found[0].feature == .unique)
    }
}

@Suite("EcoreValidator: enumerations")
struct EcoreValidatorEnumTests {
    typealias F = ValidationFixtures

    @Test("enumerator names must be unique; similar names warn")
    func uniqueEnumeratorNames() {
        let ok = EEnum(name: "E", literals: [EEnumLiteral(name: "A", value: 0), EEnumLiteral(name: "B", value: 1)])
        #expect(F.diagnostics(.uniqueEnumeratorNames, in: F.package([ok])).isEmpty)
        let twice = EEnum(name: "E", literals: [EEnumLiteral(name: "A", value: 0), EEnumLiteral(name: "A", value: 1)])
        let errors = F.diagnostics(.uniqueEnumeratorNames, in: F.package([twice]))
        #expect(errors.count == 1)
        #expect(errors[0].severity == .error)
        #expect(errors[0].feature == .eLiterals)
        let similar = EEnum(name: "E", literals: [EEnumLiteral(name: "A_B", value: 0), EEnumLiteral(name: "AB", value: 1)])
        let warnings = F.diagnostics(.uniqueEnumeratorNames, in: F.package([similar]))
        #expect(warnings.count == 1)
        #expect(warnings[0].severity == .warning)
    }

    @Test("enumerator literals must be unique")
    func uniqueEnumeratorLiterals() {
        let ok = EEnum(name: "E", literals: [EEnumLiteral(name: "A", value: 0), EEnumLiteral(name: "B", value: 1, literal: "b")])
        #expect(F.diagnostics(.uniqueEnumeratorLiterals, in: F.package([ok])).isEmpty)
        let bad = EEnum(name: "E", literals: [EEnumLiteral(name: "A", value: 0), EEnumLiteral(name: "B", value: 1, literal: "A")])
        let found = F.diagnostics(.uniqueEnumeratorLiterals, in: F.package([bad]))
        #expect(found.count == 1)
        #expect(found[0].arguments == ["A"])
        #expect(found[0].related.count == 2)
    }
}

@Suite("EcoreValidator: infrastructure")
struct EcoreValidatorInfrastructureTests {
    typealias F = ValidationFixtures

    /// A metamodel with several kinds of problem, in a known order.
    static func troubled() -> EPackage {
        let broken = EClass(
            name: "Broken Name", isInterface: true,
            eStructuralFeatures: [EAttribute(name: "a", eType: ValidationFixtures.string, lowerBound: -1)])
        let twin = EClass(name: "Twin")
        let twin2 = EClass(name: "Twin")
        return ValidationFixtures.package([broken, twin, twin2])
    }

    @Test("diagnostics come in document order and are deterministic")
    func ordering() {
        let package = Self.troubled()
        let first = F.validate(package)
        let second = F.validate(package)
        #expect(first == second)
        #expect(first.map(\.id) == second.map(\.id))
        let index = MetamodelIndex(roots: [package])
        let order = Dictionary(uniqueKeysWithValues: index.allElements.enumerated().map { ($1.id, $0) })
        let positions = first.map { order[$0.element]! }
        #expect(positions == positions.sorted())
        #expect(Set(first.map(\.id)).count == first.count)
        #expect(Set(first.map(\.code)).isSuperset(of: [.wellFormedName, .interfaceIsAbstract, .validLowerBound, .uniqueClassifierNames]))
    }

    @Test("scoped validation reports only the requested elements")
    func scoped() throws {
        let package = Self.troubled()
        let index = MetamodelIndex(roots: [package])
        let broken = try #require(package.getEClass("Broken Name"))
        let validator = EcoreValidator()
        let scoped = validator.validate([broken.id], in: index)
        #expect(!scoped.isEmpty)
        #expect(scoped.allSatisfy { $0.element == broken.id })
        let all = validator.validate(index)
        #expect(scoped == all.filter { $0.element == broken.id })
        let feature = try #require(broken.eStructuralFeatures.first)
        let both = validator.validate([feature.id, broken.id, EUUID()], in: index)
        #expect(Set(both.map(\.element)) == [broken.id, feature.id])
        #expect(validator.validate([], in: index).isEmpty)
        let reversed = validator.validate([feature.id, broken.id], in: index)
        #expect(reversed == validator.validate([broken.id, feature.id], in: index))
    }

    @Test("disabled constraints produce nothing")
    func disabled() {
        let package = Self.troubled()
        let options = EcoreValidator.Options(disabledConstraints: [.interfaceIsAbstract, .uniqueClassifierNames])
        let found = F.validate(package, options: options)
        #expect(!found.contains { $0.code == .interfaceIsAbstract || $0.code == .uniqueClassifierNames })
        #expect(found.contains { $0.code == .wellFormedName })
        #expect(EcoreValidator.Options().disabledConstraints.isEmpty)
        #expect(EcoreValidator.Options().strictNames)
    }

    @Test("disabling every constraint silences the validator")
    func allDisabled() {
        let options = EcoreValidator.Options(disabledConstraints: Set(EcoreConstraint.allCases))
        #expect(F.validate(Self.troubled(), options: options).isEmpty)
    }

    @Test("an opposite that the index does not know is not diagnosed")
    func unresolvedOpposite() {
        var reference = EReference(name: "r", eType: EClass(name: "T"))
        reference.opposite = EUUID()
        #expect(F.diagnostics(.consistentOpposite, in: F.package([F.owner(reference)])).isEmpty)
    }

    @Test("external elements are not validated")
    func externalsSkipped() {
        let external = EPackage(name: "bad name", nsURI: "http://example.org/ext", nsPrefix: "ext")
        let index = MetamodelIndex(roots: [F.package([])], externals: [external])
        #expect(EcoreValidator().validate(index).isEmpty)
        #expect(EcoreValidator().validate([external.id], in: index).isEmpty)
    }

    @Test("checks follow the index, not stale snapshots")
    func resolvesThroughIndex() {
        let base = EClass(name: "Base")
        var staleBase = base
        staleBase.isInterface = true
        let derived = EClass(name: "Derived", eSuperTypes: [staleBase], eStructuralFeatures: [EReference(name: "r", eType: staleBase)])
        let found = F.validate(F.package([base, derived]))
        #expect(found.isEmpty)
        var canonical = base
        canonical.eStructuralFeatures = [EAttribute(name: "x", eType: F.string)]
        let clash = EClass(name: "Derived", eSuperTypes: [base], eStructuralFeatures: [EAttribute(name: "x", eType: F.string)])
        let clashing = F.diagnostics(.uniqueFeatureNames, in: F.package([canonical, clash]))
        #expect(clashing.count == 1)
    }

    @Test("generic and proxy constraints are implemented")
    func pendingConstraints() {
        let pending: [EcoreConstraint] = [
            .consistentKeys, .consistentSuperTypes, .uniqueTypeParameterNames, .consistentType,
            .consistentGenericBounds, .consistentArguments, .everyProxyResolves,
        ]
        for constraint in pending {
            #expect(constraint.isImplemented, "\(constraint)")
        }
        #expect(EcoreConstraint.allCases.allSatisfy { $0.isImplemented })
        let found = F.validate(Self.troubled())
        #expect(found.allSatisfy { !pending.contains($0.code) })
    }

    @Test("constraint raw values follow the Eclipse names")
    func rawValues() {
        #expect(EcoreConstraint.wellFormedName.rawValue == "WellFormedName")
        #expect(EcoreConstraint.disjointFeatureAndOperationSignatures.rawValue == "DisjointFeatureAndOperationSignatures")
        #expect(Set(EcoreConstraint.allCases.map(\.rawValue)).count == EcoreConstraint.allCases.count)
    }

    @Test("every message template has the placeholders its arguments need")
    func messageCatalogue() {
        for message in EcoreValidationMessage.allCases {
            let template = EcoreValidationMessages.template(for: message)
            #expect(!template.isEmpty, "\(message)")
            #expect(!template.contains("\u{2014}"))
        }
        #expect(EcoreValidationMessages.message(.nameNotWellFormed, arguments: ["x y"]) == "The name 'x y' is not well formed.")
        #expect(EcoreValidationMessages.message(.nameNotWellFormed, arguments: []) == "The name '{0}' is not well formed.")
    }

    @Test("diagnostics are value types with stable identifiers")
    func diagnosticIdentity() {
        let element = EUUID()
        let one = EcoreDiagnostic(
            severity: .error, code: .wellFormedName, template: .nameNotWellFormed, element: element,
            feature: .name, arguments: ["x"], related: [])
        let same = EcoreDiagnostic(
            severity: .error, code: .wellFormedName, template: .nameNotWellFormed, element: element,
            feature: .name, arguments: ["x"], related: [])
        let other = EcoreDiagnostic(
            severity: .error, code: .wellFormedName, template: .nameNotWellFormed, element: element,
            feature: .name, arguments: ["y"], related: [])
        #expect(one == same)
        #expect(one.id == same.id)
        #expect(one.id != other.id)
        #expect(Set([one, same, other]).count == 2)
        #expect(one.message == "The name 'x' is not well formed.")
    }
}

@Suite("EcoreValidator: delegates and severities")
struct EcoreValidatorAdapterTests {
    @Test("delegate validation errors convert to diagnostics")
    func adapter() {
        let object = EUUID()
        let cases: [(ECoreValidationError.Severity, DiagnosticSeverity)] = [
            (.error, .error), (.warning, .warning), (.info, .information),
        ]
        for (source, expected) in cases {
            let error = ECoreValidationError(message: "Custom", objectId: object, feature: "name", severity: source)
            let diagnostic = EcoreDiagnostic(error)
            #expect(diagnostic.severity == expected)
            #expect(diagnostic.element == object)
            #expect(diagnostic.feature == .name)
            #expect(diagnostic.code == .delegate)
            #expect(diagnostic.message == "Custom")
            #expect(diagnostic.arguments == ["Custom"])
        }
        let unknown = EcoreDiagnostic(ECoreValidationError(message: "m", objectId: object, feature: "custom"))
        #expect(unknown.feature == nil)
    }

    @Test("delegate diagnostics merge into a validation result")
    func merging() {
        let package = EcoreValidatorInfrastructureTests.troubled()
        let own = EcoreValidator().validate(MetamodelIndex(roots: [package]))
        let errors = [ECoreValidationError(message: "extra", objectId: package.id)]
        let merged = own.merging(delegateErrors: errors)
        #expect(merged.count == own.count + 1)
        #expect(merged.last?.code == .delegate)
    }

    @Test("model diagnostics share the library severity")
    func severityUnified() {
        let diagnostic = ModelDiagnostic(severity: .warning, code: .lowerBound, objectID: EUUID())
        let severity: DiagnosticSeverity = diagnostic.severity
        #expect(severity == .warning)
        #expect(DiagnosticSeverity.info == .information)
    }
}

@Suite("EcoreValidator: fixtures")
struct EcoreValidatorFixtureTests {
    /// The messages that a fixture legitimately provokes.
    ///
    /// `library-full.ecore` exists to exercise round-tripping of unusual metamodel features: its
    /// `Book.location` attribute has the non-serialisable data type `Path` and is not transient,
    /// which Eclipse's validator also reports as a violation of ConsistentTransient.
    static let expectedMessages: [String: [String]] = [
        "library-full.ecore": [
            "ConsistentTransient: The attribute 'Book.location' must be transient because its type is not serialisable."
        ]
    ]

    @Test("every fixture validates cleanly, apart from the documented exceptions")
    func fixtures() async throws {
        let packages = try await MetamodelFixtures.fixturePackages()
        #expect(!packages.isEmpty)
        var checked = 0
        for (name, package) in packages {
            let found = EcoreValidator().validate(MetamodelIndex(roots: [package]))
            let messages = found.map { "\($0.code.rawValue): \($0.message)" }
            #expect(messages == Self.expectedMessages[name, default: []], "\(name)")
            checked += 1
        }
        #expect(checked == packages.count)
        #expect(Self.expectedMessages.keys.allSatisfy { name in packages.contains { $0.name == name } })
    }
}
