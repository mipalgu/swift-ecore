//
// OCLinEcoreReaderTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import OCL
import Testing

@testable import ECore


@Suite("OCLinEcore reader")
struct OCLinEcoreReaderTests {
    static func school() throws -> (result: OCLinEcoreParseResult, package: EPackage) {
        let result = OCLinEcoreReader.parse(OCLinEcoreFixtures.school, sourceName: "school.oclinecore")
        #expect(result.diagnostics.filter { $0.severity == .error }.isEmpty, "\(result.diagnostics.map(\.message))")
        return (result, try #require(result.packages.first))
    }

    static func eClass(_ name: String, in package: EPackage) throws -> EClass {
        try #require(package.getEClass(name))
    }

    @Test("Packages carry their namespace and subpackages")
    func packages() throws {
        let (result, package) = try Self.school()
        #expect(result.packages.count == 1)
        #expect(package.name == "school" && package.nsPrefix == "sch" && package.nsURI == "http://example.org/school")
        #expect(package.eSubpackages.map(\.name) == ["records"])
        #expect(package.eSubpackages[0].getEClass("Transcript") != nil)
        #expect(result.imports == [OCLinEcoreImport(alias: "ecore", target: "http://www.eclipse.org/emf/2002/Ecore#/", range: result.imports.first?.range)])
    }

    @Test("Classes, supertypes and abstractness")
    func classes() throws {
        let (_, package) = try Self.school()
        #expect(try Self.eClass("Named", in: package).isAbstract)
        let course = try Self.eClass("Course", in: package)
        #expect(!course.isAbstract)
        #expect(course.eSuperTypes.map(\.name) == ["Named"])
        #expect(course.eAllAttributes.map(\.name).contains("name"))
    }

    @Test("Primitive types map to the Ecore types that Eclipse OCL uses", arguments: [
        ("Named", "name", "EString", 1, 1), ("Named", "nickname", "EString", 0, 1), ("Course", "capacity", "EBigInteger", 1, 1),
        ("Course", "credit", "EDouble", 0, 1), ("Course", "topics", "EString", 0, -1), ("Enrolment", "active", "EBooleanObject", 0, 1),
        ("Enrolment", "since", "EDate", 0, 1), ("Course", "level", "Level", 1, 1),
    ])
    func attributeTypes(_ owner: String, _ name: String, _ type: String, _ lower: Int, _ upper: Int) throws {
        let (_, package) = try Self.school()
        let attribute = try #require(try Self.eClass(owner, in: package).getEAttribute(name: name))
        #expect(attribute.eType.name == type)
        #expect(attribute.lowerBound == lower && attribute.upperBound == upper)
    }

    @Test("Qualifiers default to UML and can be negated")
    func qualifiers() throws {
        let (_, package) = try Self.school()
        let course = try Self.eClass("Course", in: package)
        let topics = try #require(course.getEAttribute(name: "topics"))
        #expect(topics.ordered && !topics.unique)
        let capacity = try #require(course.getEAttribute(name: "capacity"))
        #expect(!capacity.ordered && capacity.unique && capacity.defaultValueLiteral == "30")
        let enrolments = try #require(course.getEReference(name: "enrolments"))
        #expect(enrolments.derived && !enrolments.changeable && enrolments.transient && enrolments.volatile)
        let student = try #require(try Self.eClass("Enrolment", in: package).getEReference(name: "student"))
        #expect(!student.resolveProxies)
        let course2 = try #require(try Self.eClass("Enrolment", in: package).getEReference(name: "course"))
        #expect(course2.resolveProxies && !course2.containment)
    }

    @Test("Opposites, containment and keys are linked")
    func references() throws {
        let (_, package) = try Self.school()
        let school = try Self.eClass("School", in: package)
        let course = try Self.eClass("Course", in: package)
        let courses = try #require(school.getEReference(name: "courses"))
        let back = try #require(course.getEReference(name: "school"))
        #expect(courses.containment && courses.ordered && courses.upperBound == -1)
        #expect(courses.opposite == back.id && back.opposite == courses.id)
        #expect(courses.eType.name == "Course")
        let students = try #require(school.getEReference(name: "students"))
        let named = try Self.eClass("Named", in: package)
        #expect(students.eKeys == [try #require(named.getEAttribute(name: "name")).id])
    }

    @Test("Invariants are stored as Eclipse OCL annotations")
    func invariants() throws {
        let (_, package) = try Self.school()
        let course = try Self.eClass("Course", in: package)
        #expect(course.getEAnnotationDetail(source: AnnotationSource.ecore, key: "constraints") == "HasCapacity NotOverfull")
        #expect(course.getEAnnotationDetail(source: OCLAnnotation.pivotSource, key: "HasCapacity") == "capacity > 0")
        #expect(course.getEAnnotationDetail(source: OCLAnnotation.pivotSource, key: "NotOverfull")
            == "Tuple {\n\tmessage : String = 'Too many enrolments for ' + name,\n\tstatus : Boolean = enrolments->size() <= capacity\n}.status")
        #expect(course.eAnnotations.map(\.source) == [AnnotationSource.ecore, OCLAnnotation.pivotSource])
        let student = try Self.eClass("Student", in: package)
        #expect(student.getEAnnotationDetail(source: AnnotationSource.ecore, key: "constraints") == "null")
        #expect(student.getEAnnotationDetail(source: OCLAnnotation.pivotSource, key: "null") == "enrolments->isUnique(course)")
        let code = try #require(package.getEDataType("Code"))
        #expect(code.getEAnnotationDetail(source: OCLAnnotation.pivotSource, key: "WellFormed") == "self.size() = 6")
        #expect(code.serialisable && code.instanceClassName == "java.lang.String")
    }

    @Test("Operation bodies and conditions use the Eclipse OCL keys")
    func operations() throws {
        let (_, package) = try Self.school()
        let course = try Self.eClass("Course", in: package)
        let isFull = try #require(course.eOperations.first { $0.name == "isFull" })
        #expect(isFull.eType?.name == "EBoolean" && isFull.lowerBound == 1)
        #expect(isFull.getEAnnotationDetail(source: OCLAnnotation.pivotSource, key: "body") == "enrolments->size() >= capacity")
        let enrol = try #require(course.eOperations.first { $0.name == "enrol" })
        #expect(enrol.eParameters.map(\.name) == ["student"])
        #expect(enrol.eParameters[0].eType?.name == "Student" && enrol.eParameters[0].lowerBound == 1)
        #expect(enrol.lowerBound == 0)
        let details = try #require(enrol.getEAnnotation(source: OCLAnnotation.pivotSource)).details
        #expect(Array(details.keys) == ["pre_Open", "pre", "post_Recorded"])
        #expect(details["pre"] == "student <> null")
    }

    @Test("Initial values and derivations are stored on features")
    func featureSpecifications() throws {
        let (_, package) = try Self.school()
        let year = try #require(try Self.eClass("Student", in: package).getEAttribute(name: "year"))
        #expect(year.getEAnnotationDetail(source: OCLAnnotation.pivotSource, key: "initial") == "1")
        let enrolments = try #require(try Self.eClass("Course", in: package).getEReference(name: "enrolments"))
        #expect(enrolments.getEAnnotationDetail(source: OCLAnnotation.pivotSource, key: "derivation")
            == "school.students.enrolments->select(e | e.course = self)")
    }

    @Test("The root package names the OCL delegates and records its imports")
    func delegates() throws {
        let (_, package) = try Self.school()
        for key in OCLAnnotation.delegateKeys {
            #expect(package.getEAnnotationDetail(source: AnnotationSource.ecore, key: key) == OCLAnnotation.pivotSource)
        }
        #expect(package.getEAnnotationDetail(source: OCLAnnotation.importSource, key: "ecore") == EcorePackage.nsURI)
        #expect(package.getEAnnotationDetail(source: AnnotationSource.genModel, key: "documentation") == "A neutral school model for tests.")
        let plain = OCLinEcoreReader.parse("package p : p = 'http://example.org/p' { class A; }")
        #expect(plain.packages[0].eAnnotations.isEmpty)
    }

    @Test("Enumerations number their literals in order")
    func enumerations() throws {
        let (_, package) = try Self.school()
        let level = try #require(package.getEEnum("Level"))
        #expect(level.literals.map(\.name) == ["introductory", "advanced", "research"])
        #expect(level.literals.map(\.value) == [0, 5, 6])
        #expect(level.literals.map(\.literal) == [nil, nil, "Research"])
    }

    @Test("Alternative spellings read as expected")
    func informal() throws {
        let result = OCLinEcoreReader.parse(OCLinEcoreFixtures.informal)
        #expect(result.isValid, "\(result.diagnostics.map(\.message))")
        let package = try #require(result.packages.first)
        let product = try #require(package.getEClass("Product"))
        #expect(product.getEAttribute(name: "price")?.eType.name == "EBigDecimal")
        #expect(product.getEAttribute(name: "sku")?.isID == true)
        #expect(product.getEAnnotationDetail(source: OCLAnnotation.pivotSource, key: "PositivePrice") == "price > 0.0")
        let discounted = try #require(product.eOperations.first)
        #expect(discounted.getEAnnotationDetail(source: OCLAnnotation.pivotSource, key: "body") == "price * (1 - rate)")
        #expect(package.getEEnum("Size")?.literals.map(\.value) == [0, 1, 10])
        let basket = try #require(package.getEClass("Basket"))
        let items = try #require(basket.getEReference(name: "items"))
        #expect(items.ordered && items.unique && items.lowerBound == 0 && items.upperBound == -1)
        #expect(basket.getEAttribute(name: "count")?.lowerBound == 1)
    }

    @Test("Escaped names and keywords used as names")
    func names() throws {
        let text = "package p { class _'Set' { attribute class : String; attribute _'odd name' : String; } class property; }"
        let result = OCLinEcoreReader.parse(text)
        #expect(result.isValid, "\(result.diagnostics.map(\.message))")
        let set = try #require(result.packages.first?.getEClass("Set"))
        #expect(set.eStructuralFeatures.map(\.name) == ["class", "odd name"])
        #expect(result.packages.first?.getEClass("property") != nil)
    }

    @Test("Types qualified by package and imports resolve")
    func qualifiedTypes() throws {
        let text = """
            import e : 'http://www.eclipse.org/emf/2002/Ecore';
            package outer { package inner { class Leaf; } class Root { property leaf : outer::inner::Leaf; attribute when : e::EDate; attribute meta : ecore::EInt; } }
            """
        let result = OCLinEcoreReader.parse(text)
        #expect(result.isValid, "\(result.diagnostics.map(\.message))")
        let root = try #require(result.packages.first?.getEClass("Root"))
        #expect(root.getEReference(name: "leaf")?.eType.name == "Leaf")
        #expect(root.getEAttribute(name: "when")?.eType.name == "EDate")
        #expect(root.getEAttribute(name: "meta")?.eType.name == "EInt")
    }

    @Test("External packages are found through imports")
    func externalImports() throws {
        var base = EPackage(name: "base", nsURI: "http://example.org/base", nsPrefix: "base")
        base.eClassifiers = [EClass(name: "Thing")]
        let text = "import b : 'http://example.org/base#/'; package p { class Item extends b::Thing { property other : b::Thing[?]; } }"
        let result = OCLinEcoreReader.parse(text, sourceName: nil, importing: [base])
        #expect(result.isValid, "\(result.diagnostics.map(\.message))")
        let item = try #require(result.packages.first?.getEClass("Item"))
        #expect(item.eSuperTypes.map(\.name) == ["Thing"])
        #expect(item.getEReference(name: "other")?.eType.id == base.eClassifiers[0].id)
    }

    @Test("Problems are reported with positions and reading continues")
    func recovery() throws {
        let text = """
            package p
            {
            \tclass A
            \t{
            \t\tattribute x : Missing;
            \t\tattribute y : String = ;
            \t\tinvariant Bad: x + ;
            \t\tattribute z : Integer;
            \t}
            \tclass B extends Nowhere;
            \tclass C { property d#nothing : A; }
            }
            """
        let result = OCLinEcoreReader.parse(text, sourceName: "broken.oclinecore")
        let errors = result.diagnostics.filter { $0.severity == .error }
        #expect(errors.map { $0.range?.start.line ?? 0 } == [5, 6, 7, 10, 11])
        #expect(errors.allSatisfy { $0.document == "broken.oclinecore" })
        #expect(errors.map(\.code) == [OCLDiagnosticCode.unresolvedName, OCLDiagnosticCode.unexpectedToken,
            OCLDiagnosticCode.invalidExpression, OCLDiagnosticCode.unresolvedName, OCLDiagnosticCode.unresolvedName])
        let a = try #require(result.packages.first?.getEClass("A"))
        #expect(a.eStructuralFeatures.map(\.name) == ["x", "z"])
        #expect(a.getEAnnotationDetail(source: OCLAnnotation.pivotSource, key: "Bad") == "x +")
        #expect(result.packages.first?.getEClass("B") != nil)
        #expect(result.packages.first?.getEClass("C") != nil)
    }

    @Test("A missing closing brace is reported at the end")
    func unterminated() {
        let result = OCLinEcoreReader.parse("package p { class A {")
        #expect(result.diagnostics.contains { $0.code == OCLDiagnosticCode.unexpectedEnd })
        #expect(result.packages.count == 1)
    }

    @Test("Unsupported constructs are read with warnings")
    func unsupported() {
        let text = """
            package p { class G(T) { static attribute s : String; operation f() : String { derived }; }
            class H { property r : H { opposite back : H[*]; } } }
            """
        let result = OCLinEcoreReader.parse(text)
        #expect(result.isValid, "\(result.diagnostics.map(\.message))")
        #expect(result.diagnostics.filter { $0.code == OCLDiagnosticCode.unsupportedConstruct }.count == 4)
    }

    @Test("The outline lists declarations with their ranges")
    func outline() throws {
        let (result, _) = try Self.school()
        #expect(result.outline.map(\.kind) == [OCLinEcoreOutlineKind.import, OCLinEcoreOutlineKind.package])
        let school = result.outline[1]
        #expect(school.children.map(\.name) == ["records", "Level", "Code", "Named", "School", "Course", "Student", "Enrolment"])
        let course = try #require(school.children.first { $0.name == "Course" })
        #expect(course.id == "class:school.Course")
        #expect(course.children.map(\.kind).prefix(3) == [OCLinEcoreOutlineKind.invariant, OCLinEcoreOutlineKind.invariant, OCLinEcoreOutlineKind.attribute])
        let enrol = try #require(course.children.first { $0.name == "enrol" })
        #expect(enrol.detail == "(Student) : Enrolment[?]")
        #expect(enrol.children.map(\.kind) == [OCLinEcoreOutlineKind.precondition, OCLinEcoreOutlineKind.precondition, OCLinEcoreOutlineKind.postcondition])
        #expect(course.selectionRange.start.line == course.range.start.line)
        #expect(course.range.end.line > course.range.start.line)
    }

    @Test("Tokens classify keywords, names, strings and comments")
    func tokens() {
        let tokens = OCLinEcoreSyntax.tokens(in: "package p { -- note\n class A { invariant x: self.n > 'a'; } }")
        #expect(tokens.map(\.kind) == [.keyword, .identifier, .punctuation, .comment, .keyword, .identifier, .punctuation,
            .keyword, .identifier, .operator, .keyword, .operator, .identifier, .operator, .string, .punctuation, .punctuation, .punctuation])
    }
}
