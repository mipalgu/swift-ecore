//
// CompleteOCLTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import OCL
import Testing

@testable import ECore


/// Self-authored documents for the Complete OCL tests.
enum CompleteOCLFixtures {
    /// A school metamodel with its constraints inline.
    static let inline = """
        package school : sch = 'http://example.org/school'
        {
        \tclass Course
        \t{
        \t\tinvariant HasCapacity: capacity > 0;
        \t\tinvariant NotOverfull('Too many enrolments for ' + name): enrolments->size() <= capacity;
        \t\tattribute name : String;
        \t\tattribute capacity : Integer;
        \t\tproperty enrolments : Enrolment[*] { composes };
        \t\tattribute load : Real { derived, readonly, transient, volatile }
        \t\t{
        \t\t\tderivation: enrolments->size() / capacity;
        \t\t}
        \t\tattribute rating : Integer
        \t\t{
        \t\t\tinitial: 0;
        \t\t}
        \t\toperation isFull() : Boolean
        \t\t{
        \t\t\tbody: enrolments->size() >= capacity;
        \t\t}
        \t\toperation enrol(student : Student) : Enrolment[?]
        \t\t{
        \t\t\tprecondition Open: not isFull();
        \t\t\tprecondition: student <> null;
        \t\t\tpostcondition Recorded: enrolments->exists(e | e.student = student);
        \t\t}
        \t}
        \tclass Student
        \t{
        \t\tinvariant: name <> '';
        \t\tattribute name : String;
        \t}
        \tclass Enrolment
        \t{
        \t\tproperty student : Student;
        \t}
        }

        """

    /// The same metamodel without constraints.
    static var bare: String {
        inline.split(separator: "\n", omittingEmptySubsequences: false).filter { line in
            !["invariant", "derivation:", "initial:", "body:", "precondition", "postcondition"].contains {
                line.trimmingCharacters(in: .whitespaces).hasPrefix($0)
            }
        }.joined(separator: "\n")
    }

    /// The constraints of the metamodel as a Complete OCL document.
    static let constraints = """
        import 'school.ecore'

        package school

        -- Invariants of courses
        context Course
        inv HasCapacity: capacity > 0
        inv NotOverfull('Too many enrolments for ' + name): enrolments->size() <= capacity

        context Course::load : Real
        derive: enrolments->size() / capacity

        context Course::rating : Integer
        init: 0

        context Course::isFull() : Boolean
        body: enrolments->size() >= capacity

        context Course::enrol(student : Student) : Enrolment
        pre Open: not isFull()
        pre: student <> null
        post Recorded: enrolments->exists(e | e.student = student)

        context Student
        inv: name <> ''

        endpackage
        """
}

@Suite("Complete OCL")
struct CompleteOCLTests {
    static func bare() throws -> [EPackage] {
        let result = OCLinEcoreReader.parse(CompleteOCLFixtures.bare)
        #expect(result.isValid, "\(result.diagnostics.map(\.message))")
        return result.packages
    }

    @Test("A document lists its imports, packages and contexts")
    func reading() throws {
        let result = CompleteOCLReader.parse(CompleteOCLFixtures.constraints, sourceName: "school.ocl")
        #expect(result.isValid, "\(result.diagnostics.map(\.message))")
        let document = result.document
        #expect(document.imports == [CompleteOCLImport(keyword: "import", alias: nil, target: "school.ecore", range: document.imports.first?.range)])
        #expect(document.packages.map(\.path) == [["school"]])
        #expect(document.classifierContexts.map(\.path) == [["Course"], ["Student"]])
        #expect(document.classifierContexts.allSatisfy { $0.packagePath == ["school"] })
        let course = document.classifierContexts[0]
        #expect(course.invariants.map(\.name) == ["HasCapacity", "NotOverfull"])
        #expect(course.invariants[1].message == "'Too many enrolments for ' + name")
        #expect(course.invariants[1].expression == "enrolments->size() <= capacity")
        #expect(course.invariants[1].parsedExpression != nil)
        #expect(document.classifierContexts[1].invariants.map(\.name) == [nil])
        let enrol = try #require(document.operationContexts.first { $0.path == ["Course", "enrol"] })
        #expect(enrol.parameters == [CompleteOCLParameter(name: "student", type: enrol.parameters[0].type)])
        #expect(enrol.parameters[0].type.text == "Student")
        #expect(enrol.resultType?.text == "Enrolment")
        #expect(enrol.preconditions.map(\.name) == ["Open", nil])
        #expect(enrol.postconditions.map(\.expression) == ["enrolments->exists(e | e.student = student)"])
        #expect(document.operationContexts[0].bodies.map(\.expression) == ["enrolments->size() >= capacity"])
        #expect(document.propertyContexts.map(\.path) == [["Course", "load"], ["Course", "rating"]])
        #expect(document.propertyContexts[0].derivations.map(\.expression) == ["enrolments->size() / capacity"])
        #expect(document.propertyContexts[1].initialisers.map(\.expression) == ["0"])
        #expect(document.allConstraints.count == 9)
    }

    @Test("The outline follows the source order")
    func outline() throws {
        let result = CompleteOCLReader.parse(CompleteOCLFixtures.constraints)
        #expect(result.outline.map(\.kind) == [CompleteOCLOutlineKind.import, CompleteOCLOutlineKind.package])
        let package = result.outline[1]
        #expect(package.children.map(\.kind) == ["classifier", "property", "property", "operation", "operation", "classifier"])
        #expect(package.children[0].children.map(\.name) == ["HasCapacity", "NotOverfull"])
        #expect(package.children[4].detail == "(Student) : Enrolment")
        #expect(package.children[4].children.map(\.kind) == ["pre", "pre", "post"])
        #expect(package.children[0].id == "classifier:school::Course")
    }

    @Test("Tokens classify Complete OCL keywords")
    func tokens() {
        let result = CompleteOCLReader.parse("context A inv x: self.y -- c")
        #expect(result.tokens.map(\.kind) == [.keyword, .identifier, .keyword, .identifier, .operator, .keyword, .operator, .identifier, .comment])
    }

    @Test("Applying the document gives the annotations of the inline constraints")
    func equivalence() throws {
        let document = CompleteOCLReader.parse(CompleteOCLFixtures.constraints).document
        let applied = CompleteOCLApplier.apply(document, to: try Self.bare())
        #expect(applied.isComplete, "\(applied.diagnostics.map(\.message))")
        #expect(applied.appliedCount == 9)
        let inline = OCLinEcoreReader.parse(CompleteOCLFixtures.inline).packages
        #expect(MetamodelSummary.describe(applied.packages) == MetamodelSummary.describe(inline))
        #expect(OCLinEcoreWriter.write(applied.packages).text == CompleteOCLFixtures.inline)
    }

    @Test("Self and parameter names are bound when they differ")
    func renaming() throws {
        let text = """
            context c : Course inv Named: c.name <> ''
            context Student inv: true
            context s Student inv Short: s.name.size() < 40
            context Course::enrol(who : Student) : Enrolment pre: who <> null
            """
        let result = CompleteOCLReader.parse(text)
        #expect(result.isValid, "\(result.diagnostics.map(\.message))")
        #expect(result.document.classifierContexts.map(\.selfName) == ["c", nil, "s"])
        let applied = CompleteOCLApplier.apply(result.document, to: try Self.bare())
        #expect(applied.isComplete, "\(applied.diagnostics.map(\.message))")
        let package = try #require(applied.packages.first)
        #expect(package.getEClass("Course")?.getEAnnotationDetail(source: OCLAnnotation.pivotSource, key: "Named") == "let c = self in c.name <> ''")
        #expect(package.getEClass("Student")?.getEAnnotationDetail(source: OCLAnnotation.pivotSource, key: "Short")
            == "let s = self in s.name.size() < 40")
        let enrol = try #require(package.getEClass("Course")?.eOperations.first { $0.name == "enrol" })
        #expect(enrol.getEAnnotationDetail(source: OCLAnnotation.pivotSource, key: "pre") == "let who = student in who <> null")
    }

    @Test("Definitions add operations and derived features")
    func definitions() throws {
        let text = """
            context Course
            def: spare() : Integer = capacity - enrolments->size()
            def: students : Set(Student) = enrolments.student->asSet()
            def label: title : String = name.toUpperCase()
            static def: limit : Integer = 100
            """
        let result = CompleteOCLReader.parse(text)
        #expect(result.isValid, "\(result.diagnostics.map(\.message))")
        let definitions = result.document.classifierContexts[0].definitions
        #expect(definitions.map(\.name) == ["spare", "students", "title", "limit"])
        #expect(definitions.map(\.isOperation) == [true, false, false, false])
        #expect(definitions[3].isStatic)
        let applied = CompleteOCLApplier.apply(result.document, to: try Self.bare())
        #expect(applied.diagnostics.map(\.code) == [OCLDiagnosticCode.unsupportedConstruct])
        let course = try #require(applied.packages.first?.getEClass("Course"))
        let spare = try #require(course.eOperations.first { $0.name == "spare" })
        #expect(spare.eType?.name == "EBigInteger")
        #expect(spare.getEAnnotationDetail(source: OCLAnnotation.pivotSource, key: "body") == "capacity - enrolments->size()")
        let students = try #require(course.getEReference(name: "students"))
        #expect(students.derived && students.volatile && students.transient && !students.changeable)
        #expect(students.upperBound == -1 && students.unique && !students.ordered && students.eType.name == "Student")
        #expect(students.getEAnnotationDetail(source: OCLAnnotation.pivotSource, key: "derivation") == "enrolments.student->asSet()")
        #expect(course.getEAttribute(name: "title")?.eType.name == "EString")
        let written = OCLinEcoreWriter.write(applied.packages).text
        #expect(written.contains("property students : Student[*] { derived, readonly, transient, volatile }"))
        #expect(written.contains("operation spare() : Integer\n\t\t{\n\t\t\tbody: capacity - enrolments->size();"))
    }

    @Test("Operations are chosen among overloads by their parameter types")
    func overloads() throws {
        let metamodel = """
            package m { class A { operation f(x : String) : Boolean; operation f(x : Integer) : Boolean; } }
            """
        let packages = OCLinEcoreReader.parse(metamodel).packages
        let document = CompleteOCLReader.parse("context A::f(n : Integer) : Boolean body: n > 0").document
        let applied = CompleteOCLApplier.apply(document, to: packages)
        #expect(applied.isComplete, "\(applied.diagnostics.map(\.message))")
        let operations = try #require(applied.packages.first?.getEClass("A")).eOperations
        #expect(operations[0].getEAnnotation(source: OCLAnnotation.pivotSource) == nil)
        #expect(operations[1].getEAnnotationDetail(source: OCLAnnotation.pivotSource, key: "body") == "let n = x in n > 0")
    }

    @Test("Unresolved contexts are reported with their positions")
    func unresolved() throws {
        let text = """
            context Missing inv: true
            context Course::missing() : Boolean body: true
            context Course::nothing : Integer init: 0
            context Enrolment::name : String derive: ''
            package elsewhere
            context Course inv: true
            endpackage
            """
        let document = CompleteOCLReader.parse(text, sourceName: "bad.ocl").document
        var packages = try Self.bare()
        var named = EClass(name: "Named")
        named.eStructuralFeatures = [EAttribute(name: "label", eType: EcorePackage.dataType(.eString)!)]
        packages[0].eClassifiers.append(named)
        let applied = CompleteOCLApplier.apply(document, to: packages, sourceName: "bad.ocl")
        #expect(applied.diagnostics.map { $0.range?.start.line ?? 0 } == [1, 6, 2, 3, 4])
        #expect(applied.diagnostics.allSatisfy { $0.code == OCLDiagnosticCode.unresolvedContext && $0.document == "bad.ocl" })
        #expect(applied.appliedCount == 0)
        #expect(!applied.packages[0].eAnnotations.contains { $0.source == AnnotationSource.ecore })
    }

    @Test("Inherited operations are reported rather than changed")
    func inherited() throws {
        let packages = OCLinEcoreReader.parse("package m { class A { operation f() : Boolean; } class B extends A; }").packages
        let applied = CompleteOCLApplier.apply(CompleteOCLReader.parse("context B::f() : Boolean body: true").document, to: packages)
        #expect(applied.diagnostics.first?.message.contains("inherited") == true)
    }

    @Test("Problems in a document are reported and reading continues")
    func recovery() {
        let text = """
            context A
            inv Bad: x +
            inv Good: y > 0
            context B inv: )
            context C inv Fine: true
            """
        let result = CompleteOCLReader.parse(text)
        #expect(result.diagnostics.map { $0.range?.start.line ?? 0 } == [3, 4])
        #expect(result.diagnostics.map(\.code) == [OCLDiagnosticCode.invalidExpression, OCLDiagnosticCode.invalidExpression])
        #expect(result.document.classifierContexts.map(\.path) == [["A"], ["B"], ["C"]])
        #expect(result.document.classifierContexts[0].invariants.map(\.name) == ["Bad", "Good"])
        #expect(result.document.classifierContexts[0].invariants[0].expression == "x +")
        #expect(result.document.classifierContexts[2].invariants.map(\.name) == ["Fine"])
    }

    @Test("Structural problems are reported", arguments: [
        ("context", 1), ("package p context A inv: true", 1), ("endpackage", 1), ("context A::b : Integer", 1),
        ("frobnicate", 1), ("context A inv x: true\ncontext B::f( inv", 2),
    ])
    func structuralErrors(_ text: String, _ line: Int) {
        let result = CompleteOCLReader.parse(text)
        #expect(!result.isValid)
        #expect(result.diagnostics.first?.range?.start.line == line)
    }

    @Test("A context without constraints is read with a warning")
    func emptyContext() {
        let result = CompleteOCLReader.parse("context A\ncontext B inv: true")
        #expect(result.isValid)
        #expect(result.diagnostics.map(\.severity) == [.warning])
        #expect(result.document.classifierContexts.map(\.path) == [["A"], ["B"]])
    }

    @Test("A leading import alias in a context is skipped")
    func aliasedContext() throws {
        let document = CompleteOCLReader.parse("import s : 'school.ecore'\ncontext s::school::Student inv Aliased: true").document
        let applied = CompleteOCLApplier.apply(document, to: try Self.bare())
        #expect(applied.isComplete, "\(applied.diagnostics.map(\.message))")
        #expect(applied.packages.first?.getEClass("Student")?.getEAnnotationDetail(source: OCLAnnotation.pivotSource, key: "Aliased") == "true")
    }

    @Test("Messages, imports with aliases and qualified contexts")
    func forms() throws {
        let text = """
            import sch : 'http://example.org/school#/'
            include 'more.ocl'
            context school::Course inv Counted('at most ' + capacity.toString()): enrolments->size() <= capacity
            context Course::isFull() : Boolean post: result = (enrolments->size() >= capacity)
            context Course inv Sent: self^notify(1, ?) or true
            """
        let result = CompleteOCLReader.parse(text)
        #expect(result.isValid, "\(result.diagnostics.map(\.message))")
        #expect(result.document.imports.map(\.alias) == ["sch", nil])
        #expect(result.document.imports.map(\.keyword) == ["import", "include"])
        let applied = CompleteOCLApplier.apply(result.document, to: try Self.bare())
        #expect(applied.isComplete, "\(applied.diagnostics.map(\.message))")
        let course = try #require(applied.packages.first?.getEClass("Course"))
        #expect(OCLConstraintAnnotations.invariants(of: course).first
            == OCLConstraintText(name: "Counted", expression: "enrolments->size() <= capacity", message: "'at most ' + capacity.toString()"))
        #expect(course.eOperations.first?.getEAnnotationDetail(source: OCLAnnotation.pivotSource, key: "post")
            == "result = (enrolments->size() >= capacity)")
    }
}
