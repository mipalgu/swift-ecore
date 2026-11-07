import EMFBase
import Foundation
import Testing

@testable import ECore

/// Verifies that UML class models are converted into Ecore metamodels as Eclipse UML2 converts them.
@Suite("UML to Ecore")
struct UMLToEcoreTests {
    /// The directory of the dialect fixtures.
    static let directory = OMGXMIDialectTests.directory

    /// The namespace URI that the Ecore profile gives the library fixture.
    static let libraryURI = "http://example.org/lending"

    /// Reads a fixture and converts it with the given options.
    static func convert(
        _ name: String, options: UMLToEcore.Options = UMLToEcore.Options(), in resourceSet: ResourceSet = ResourceSet()
    ) async throws -> ModelDocumentReadResult {
        await UMLToEcore.registerEcoreProfile(in: resourceSet)
        let read = try await UMLFormat.read(url: directory.appendingPathComponent(name), resourceSet: resourceSet)
        return try await UMLToEcore.convert(read.resource, options: options)
    }

    /// Reads an inline UML document and converts it with the given options.
    static func convert(text: String, options: UMLToEcore.Options = UMLToEcore.Options()) async throws
        -> ModelDocumentReadResult
    {
        let resourceSet = ResourceSet()
        await UMLToEcore.registerEcoreProfile(in: resourceSet)
        let read = try await UMLFormat.read(
            data: Data(text.utf8), uri: "memory:/inline.uml", resourceSet: resourceSet)
        return try await UMLToEcore.convert(read.resource, options: options)
    }

    /// The library package of the converted fixture.
    static func library(options: UMLToEcore.Options = UMLToEcore.Options()) async throws
        -> (package: EPackage, result: ModelDocumentReadResult)
    {
        let result = try await convert("library-classes.uml", options: options)
        let package = try #require(result.packages.first { $0.name == "library" })
        return (package, result)
    }

    /// A feature of a class by name.
    static func feature(_ name: String, of eClass: EClass?) -> (any EStructuralFeature)? {
        eClass?.eStructuralFeatures.first { $0.name == name }
    }

    /// The name of the type of a feature.
    static func typeName(of feature: (any EStructuralFeature)?) -> String? {
        (feature as? EAttribute)?.eType.name ?? (feature as? EReference)?.eType.name
    }

    /// The names of the elements of a kind that an annotation contains.
    ///
    /// The Ecore loader keeps the contents of annotations as generic objects.
    static func contentNames(of annotation: EAnnotation, kind: String) -> [String] {
        annotation.contents.filter { $0.eClass.name == kind }.compactMap {
            ($0 as? DynamicEObject)?.eGet(EcoreFeatureName.name.rawValue) as? String
        }
    }

    /// Wraps the body of a model in a UML 2.5 document.
    static func document(_ body: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <uml:Model xmi:version="20131001" xmlns:xmi="http://www.omg.org/spec/XMI/20131001" \
        xmlns:uml="http://www.eclipse.org/uml2/5.0.0/UML" xmi:id="m" name="shapes">
        \(body)
        </uml:Model>
        """
    }

    /// The type element of a UML primitive type.
    static func primitive(_ name: String) -> String {
        "<type xmi:type=\"uml:PrimitiveType\" href=\"pathmap://UML_LIBRARIES/UMLPrimitiveTypes.library.uml#\(name)\"/>"
    }

    // MARK: - Packages

    @Test("A package takes its namespace from the Ecore profile, or derives it as UML2 does")
    func packages() async throws {
        let (package, result) = try await Self.library()
        #expect(result.packages.count == 1)
        #expect(package.nsURI == Self.libraryURI)
        #expect(package.nsPrefix == "lend")
        let circulation = try #require(package.getSubpackage("circulation"))
        #expect(circulation.nsURI == "http:///library/circulation.ecore")
        #expect(circulation.nsPrefix == "library.circulation")
        #expect(result.diagnostics.allSatisfy { $0.severity != .error }, "\(result.diagnostics.map(\.message))")

        let api = try await Self.library(options: .eclipseAPI).package
        #expect(api.nsURI == "http:///library.ecore")
        #expect(api.nsPrefix == "library")
    }

    @Test("A package URI becomes the namespace URI")
    func packageURI() async throws {
        let result = try await Self.convert("library-extension.uml")
        let archive = try #require(result.packages.first { $0.name == "archive" })
        #expect(archive.nsURI == "http://example.org/archive")
        #expect(archive.nsPrefix == "archive")
    }

    // MARK: - Classifiers

    @Test("Classes, interfaces, data types and enumerations become classifiers")
    func classifiers() async throws {
        let (package, _) = try await Self.library()
        let item = try #require(package.getEClass("Item"))
        #expect(item.isAbstract)
        #expect(!item.isInterface)
        let borrowable = try #require(package.getEClass("Borrowable"))
        #expect(borrowable.isAbstract)
        #expect(borrowable.isInterface)
        let book = try #require(package.getEClass("Book"))
        #expect(book.eSuperTypes.map(\.name) == ["Item", "Borrowable"])
        let address = try #require(package.getEClass("Address"))
        #expect(!address.isAbstract)
        #expect(Self.feature("street", of: address) is EAttribute)

        let isbn = try #require(package.getEDataType("Isbn"))
        #expect(isbn.instanceClassName == "java.lang.String")
        let genre = try #require(package.getEEnum("Genre"))
        #expect(genre.literals.map(\.name) == ["Fiction", "Poetry", "Science"])
        #expect(genre.literals.map(\.value) == [0, 1, 7])

        #expect(package.getEClass("Author") == nil)
        let writer = try #require(package.getEClass("Writer"))
        #expect(writer.getEAnnotationDetail(source: UMLToEcore.Syntax.umlAnnotationSource, key: "originalName")
            == "Author")
    }

    @Test("The Ecore profile is ignored or reported unless it is processed")
    func taggedValueChoices() async throws {
        var options = UMLToEcore.Options()
        options.ecoreTaggedValues = .ignore
        let ignored = try await Self.library(options: options)
        #expect(ignored.package.nsURI == "http:///library.ecore")
        #expect(ignored.package.getEClass("Author") != nil)
        #expect(!ignored.result.diagnostics.contains { $0.code == UMLToEcore.Diagnostic.ecoreTaggedValue })

        options.ecoreTaggedValues = .report
        let reported = try await Self.library(options: options)
        #expect(reported.package.getEClass("Author") != nil)
        let warnings = reported.result.diagnostics.filter { $0.code == UMLToEcore.Diagnostic.ecoreTaggedValue }
        #expect(warnings.count == 7, "\(warnings.map(\.message))")
        #expect(warnings.allSatisfy { $0.severity == .warning })
    }

    // MARK: - Features

    @Test("Properties typed by data types become attributes")
    func attributes() async throws {
        let (package, _) = try await Self.library()
        let item = try #require(package.getEClass("Item"))
        let title = try #require(Self.feature("title", of: item) as? EAttribute)
        #expect(title.eType.name == "EString")
        #expect(title.lowerBound == 1)
        #expect(title.upperBound == 1)
        #expect(!title.ordered)
        #expect(title.unique)
        let published = try #require(Self.feature("published", of: item) as? EAttribute)
        #expect(published.eType.name == "EInt")
        #expect(published.lowerBound == 0)
        let tags = try #require(Self.feature("tags", of: item) as? EAttribute)
        #expect(tags.upperBound == -1)
        #expect(tags.ordered)
        #expect(!tags.unique)
        let price = try #require(Self.feature("price", of: item) as? EAttribute)
        #expect(price.eType.name == "EDouble")
        #expect(price.defaultValueLiteral == "9.5")
        let copies = try #require(Self.feature("copies", of: item) as? EAttribute)
        #expect(copies.eType.name == "EInt")
        #expect(copies.defaultValueLiteral == "1")

        let summary = try #require(Self.feature("summary", of: item) as? EAttribute)
        #expect(summary.derived)
        #expect(!summary.changeable)
        #expect(summary.transient)
        #expect(summary.volatile)

        let book = try #require(package.getEClass("Book"))
        let isbn = try #require(Self.feature("isbnCode", of: book) as? EAttribute)
        #expect(isbn.isID)
        #expect(isbn.eType.name == "Isbn")
        #expect(isbn.getEAnnotationDetail(source: UMLToEcore.Syntax.umlAnnotationSource, key: "originalName")
            == "isbn")
        let genre = try #require(Self.feature("genre", of: book) as? EAttribute)
        #expect(genre.eType.name == "Genre")
        #expect(genre.defaultValueLiteral == "Poetry")
        let pages = try #require(Self.feature("pages", of: book) as? EAttribute)
        #expect(pages.unsettable)
        #expect(pages.defaultValueLiteral == "100")
        #expect(Self.feature("pages", of: package.getEClass("Loan")) == nil)
    }

    @Test("Properties typed by classes become references, with containment and opposites")
    func references() async throws {
        let (package, _) = try await Self.library()
        let library = try #require(package.getEClass("Library"))
        let items = try #require(Self.feature("items", of: library) as? EReference)
        #expect(items.containment)
        #expect(items.opposite == nil)
        #expect(items.upperBound == -1)
        #expect(items.eType.name == "Item")

        let book = try #require(package.getEClass("Book"))
        let writer = try #require(package.getEClass("Writer"))
        let authors = try #require(Self.feature("authors", of: book) as? EReference)
        let books = try #require(Self.feature("books", of: writer) as? EReference)
        #expect(authors.lowerBound == 1)
        #expect(authors.upperBound == -1)
        #expect(!authors.resolveProxies)
        #expect(books.resolveProxies)
        #expect(authors.opposite == books.id)
        #expect(books.opposite == authors.id)
        #expect(!authors.containment && !books.containment)

        let member = try #require(package.getEClass("Member"))
        let loan = try #require(package.getEClass("Loan"))
        let loans = try #require(Self.feature("loans", of: member) as? EReference)
        let owner = try #require(Self.feature("member", of: loan) as? EReference)
        #expect(loans.containment)
        #expect(loans.opposite == owner.id)
        #expect(owner.opposite == loans.id)
        let address = try #require(Self.feature("address", of: member) as? EReference)
        #expect(address.containment)
        #expect(address.eType.name == "Address")
    }

    @Test("Navigable ends owned by associations are reported, or converted on request")
    func associationOwnedEnds() async throws {
        let (package, result) = try await Self.library()
        #expect(Self.feature("item", of: package.getEClass("Loan")) == nil)
        let reported = result.diagnostics.filter { $0.code == UMLToEcore.Diagnostic.associationOwnedEnd }
        #expect(reported.count == 1)
        #expect(reported.first?.severity == .warning)

        var options = UMLToEcore.Options()
        options.navigableAssociationOwnedEnds = .process
        let processed = try await Self.library(options: options)
        let item = try #require(Self.feature("item", of: processed.package.getEClass("Loan")) as? EReference)
        #expect(item.eType.name == "Book")
        #expect(item.lowerBound == 1)
        #expect(!item.containment)
    }

    // MARK: - Operations

    @Test("Operations take their type from the return parameter")
    func operations() async throws {
        let (package, _) = try await Self.library()
        let borrow = try #require(package.getEClass("Borrowable")?.getOperation(name: "borrow"))
        #expect(borrow.eType?.name == "EBoolean")
        #expect(borrow.eParameters.map(\.name) == ["days"])
        #expect(borrow.eParameters.first?.eType?.name == "EInt")
        let label = try #require(package.getEClass("Item")?.getOperation(name: "label"))
        #expect(label.eType?.name == "EString")
        #expect(label.getEAnnotationDetail(source: UMLToEcore.Syntax.oclPivotDelegate, key: "body") == "title")
        #expect(label.getEAnnotationDetail(source: AnnotationSource.genModel, key: "documentation") == nil)
    }

    // MARK: - Constraints and comments

    @Test("Invariants become OCL constraints with the delegates of the package")
    func constraints() async throws {
        let (package, _) = try await Self.library()
        let book = try #require(package.getEClass("Book"))
        #expect(book.getEAnnotationDetail(source: AnnotationSource.ecore, key: "constraints") == "hasTitle")
        #expect(book.getEAnnotationDetail(source: UMLToEcore.Syntax.oclPivotDelegate, key: "hasTitle")
            == "title.size() > 0")
        #expect(book.getOperation(name: "hasTitle") == nil)
        for key in [AnnotationSource.EcoreKey.validationDelegates, AnnotationSource.EcoreKey.invocationDelegates] {
            #expect(package.getEAnnotationDetail(source: AnnotationSource.ecore, key: key)
                == UMLToEcore.Syntax.oclPivotDelegate)
        }

        var options = UMLToEcore.Options.eclipseDialog
        options.validationDelegates = .ignore
        let api = try await Self.library(options: options).package
        let invariant = try #require(api.getEClass("Book")?.getOperation(name: "hasTitle"))
        #expect(invariant.eType?.name == "EBoolean")
        #expect(invariant.eParameters.map(\.name) == ["diagnostics", "context"])
        #expect(invariant.getEAnnotationDetail(source: UMLToEcore.Syntax.uml2GenModel, key: "body")
            == "title.size() > 0")
    }

    @Test("Comments become documentation")
    func comments() async throws {
        let (package, _) = try await Self.library()
        let documentation = package.getEClass("Book")?.getEAnnotationDetail(
            source: AnnotationSource.genModel, key: AnnotationSource.GenModelKey.documentation)
        #expect(documentation == "title.size() > 0\nA book that the library holds.")
        let api = try await Self.library(options: .eclipseAPI).package
        #expect(api.getEClass("Book")?.getEAnnotationDetail(
            source: AnnotationSource.genModel, key: AnnotationSource.GenModelKey.documentation) == "title.size() > 0")
        #expect(api.getEClass("Item")?.getOperation(name: "label")?.getEAnnotationDetail(
            source: AnnotationSource.genModel, key: AnnotationSource.GenModelKey.documentation) == "result = (title)")
    }

    // MARK: - Templates

    @Test("Template parameters of classes become type parameters")
    func templates() async throws {
        let (package, _) = try await Self.library()
        let shelf = try #require(package.getSubpackage("circulation")?.getEClass("Shelf"))
        #expect(shelf.eTypeParameters.map(\.name) == ["T"])
        let contents = try #require(Self.feature("contents", of: shelf) as? EReference)
        #expect(contents.eGenericType?.eTypeParameter == shelf.eTypeParameters.first?.id)
        #expect(contents.upperBound == -1)
        #expect(package.getSubpackage("circulation")?.getEClass("T") == nil)
    }

    // MARK: - Other documents

    @Test("Types of other documents and libraries are converted or mapped")
    func otherDocuments() async throws {
        let result = try await Self.convert("library-extension.uml")
        let archive = try #require(result.packages.first { $0.name == "archive" }?.getEClass("Archive"))
        #expect(result.packages.map(\.name).sorted() == ["archive", "library"])
        #expect(archive.eSuperTypes.map(\.name) == ["Library"])
        #expect(Self.typeName(of: Self.feature("oldest", of: archive)) == "Book")
        #expect(Self.typeName(of: Self.feature("flags", of: archive)) == "ELong")
        #expect(Self.typeName(of: Self.feature("stamp", of: archive)) == "EDate")
        let owner = try #require(Self.feature("owner", of: archive) as? EReference)
        let (uml, _) = try await UMLMetamodel.packages()
        #expect(owner.eType.id == uml.getEClass("Class")?.id)
        #expect(result.diagnostics.allSatisfy { $0.severity != .error }, "\(result.diagnostics.map(\.message))")
    }

    @Test("UML primitive types can refer to the UML types package instead")
    func umlPrimitiveTypes() async throws {
        var options = UMLToEcore.Options()
        options.primitiveTypes = .umlTypes
        let (package, _) = try await Self.library(options: options)
        let title = try #require(Self.feature("title", of: package.getEClass("Item")) as? EAttribute)
        #expect(title.eType.name == "String")
        let (_, types) = try await UMLMetamodel.packages()
        #expect(title.eType.id == types.getEDataType("String")?.id)
        #expect((title.eType as? EDataType)?.instanceClassName == "java.lang.String")
    }

    // MARK: - Instances

    @Test("A converted class model is a metamodel for instance documents")
    func instances() async throws {
        let resourceSet = ResourceSet()
        let result = try await Self.convert("library-classes.uml", in: resourceSet)
        let package = try #require(result.packages.first)
        #expect(await resourceSet.getMetamodel(uri: Self.libraryURI)?.id == package.id)
        let instance = try await XMIParser(resourceSet: resourceSet).parse(
            Self.directory.appendingPathComponent("library-instance.xmi"))
        let root = try #require(await instance.getRootObjects().first)
        #expect(root.eClass.name == "Library")
        let reference = EcoreReferenceModel(rootPackage: package, resource: result.resource)
        let model = EcoreModel(resource: instance, referenceModel: reference)
        let evaluator = ECoreQueryEvaluator(executionEngine: ECoreExecutionEngine(models: ["library": model]))
        let context = try #require(package.getEClass("Library"))
        func query(_ text: String) async throws -> (any EcoreValue)? {
            try await evaluator.evaluate(ECoreQuery(text, context: context), on: root)
        }
        #expect(try await query("self.items.size()") as? Int == 2)
        #expect(try await query("self.authors.size()") as? Int == 2)
        let items = try #require(await instance.eGet(objectId: root.id, feature: "items") as? [EUUID])
        let second = try #require(items.last)
        #expect(await instance.eGet(objectId: second, feature: "title") as? String == "Night Verses")
        #expect((await instance.eGet(objectId: second, feature: "authors") as? [EUUID])?.count == 2)
        let first = try #require(items.first)
        #expect(await instance.eGet(objectId: first, feature: "pages") as? Int == 240)
        #expect((await instance.eGet(objectId: first, feature: "tags") as? [String]) == ["travel", "travel"])
    }

    // MARK: - Reading as a metamodel

    @Test("The Ecore profile can be read without its description, except for values written as elements")
    func profileWithoutDescription() async throws {
        let resourceSet = ResourceSet()
        let read = try await UMLFormat.read(
            data: Data(Self.profiled.utf8), uri: "memory:/profiled.uml", resourceSet: resourceSet)
        #expect(read.diagnostics.contains { $0.code == ModelDocumentDiagnostic.unresolvedProfile })
        let result = try await UMLToEcore.convert(read.resource)
        let package = try #require(result.packages.first)
        #expect(package.nsURI == "http://example.org/store")
        let code = try #require(Self.feature("code", of: package.getEClass("Box")) as? EAttribute)
        #expect(code.transient)
        #expect(code.getEAnnotation(source: "http://example.org/extra") == nil)

        let described = ResourceSet()
        await UMLToEcore.registerEcoreProfile(in: described)
        let typed = try await UMLFormat.read(
            data: Data(Self.profiled.utf8), uri: "memory:/profiled.uml", resourceSet: described)
        #expect(typed.diagnostics.isEmpty, "\(typed.diagnostics.map(\.message))")
    }

    @Test("A UML document can be read directly as a metamodel")
    func readsAsMetamodel() async throws {
        let resourceSet = ResourceSet()
        let read = try await UMLToEcore.read(
            url: Self.directory.appendingPathComponent("library-classes.uml"), resourceSet: resourceSet)
        #expect(read.packages.map(\.name) == ["library"])
        #expect(await read.resource.getRootObjects().count == 1)
        #expect(read.diagnostics.contains { $0.code == ModelDocumentDiagnostic.unresolvedProfile } == false)
        #expect(await resourceSet.getMetamodel(uri: Self.libraryURI) != nil)
        let text = try #require(String(data: try Data(
            contentsOf: Self.directory.appendingPathComponent("library-classes.uml")), encoding: .utf8))
        let fromData = try await UMLToEcore.read(
            data: Data(text.utf8), uri: "memory:/library-classes.uml", resourceSet: ResourceSet())
        #expect(fromData.packages.first?.getEClass("Writer") != nil)
    }

    @Test("A converted metamodel can be written and read again as an Ecore document")
    func writesEcore() async throws {
        let resourceSet = ResourceSet()
        let read = try await UMLFormat.read(
            url: Self.directory.appendingPathComponent("library-classes.uml"), resourceSet: resourceSet)
        let translation = try await UMLToEcore.translate(read.resource)
        #expect(translation.text.contains("nsURI=\"\(Self.libraryURI)\""))
        let result = try await UMLToEcore.convert(read.resource)
        let text = XMISerializer(options: .emf).serialize(result.packages, relativeTo: nil)
        let reread = try await ResourceSet().loadEcoreResource(text: text, uri: "memory:/library.ecore")
        let package = try #require(await reread.getRootObjects().first as? EPackage)
        #expect(package.nsURI == Self.libraryURI)
        #expect(package.eClassifiers.map(\.name).sorted() == result.packages[0].eClassifiers.map(\.name).sorted())
        let book = try #require(package.getEClass("Book"))
        #expect(book.eSuperTypes.map(\.name) == ["Item", "Borrowable"])
        let authors = try #require(Self.feature("authors", of: book) as? EReference)
        #expect(authors.opposite == (Self.feature("books", of: package.getEClass("Writer")) as? EReference)?.id)
    }

    @Test("A document without a UML package cannot be converted")
    func rejectsNonUML() async throws {
        let resource = Resource(uri: "memory:/empty.uml")
        await #expect(throws: UMLToEcoreError.self) {
            try await UMLToEcore.convert(resource)
        }
    }

    // MARK: - Options

    /// A model that exercises derived unions, subsets, redefinitions, duplicates and untyped properties.
    static let shapes = document("""
        <packagedElement xmi:type="uml:Class" xmi:id="Shape" name="Shape" isAbstract="true">
          <ownedAttribute xmi:id="Shape-parts" name="parts" type="Shape" isReadOnly="true" isDerived="true" isDerivedUnion="true">
            <lowerValue xmi:type="uml:LiteralInteger" xmi:id="Shape-parts-lower"/>
            <upperValue xmi:type="uml:LiteralUnlimitedNatural" xmi:id="Shape-parts-upper" value="*"/>
          </ownedAttribute>
          <ownedAttribute xmi:id="Shape-label" name="label">\(primitive("String"))</ownedAttribute>
          <ownedAttribute xmi:id="Shape-note" name="note"/>
          <ownedAttribute xmi:id="Shape-area" name="area">\(primitive("Real"))
            <defaultValue xmi:type="uml:OpaqueExpression" xmi:id="Shape-area-default">
              <language>OCL</language>
              <body>0.0</body>
            </defaultValue>
          </ownedAttribute>
          <ownedOperation xmi:id="Shape-describe" name="describe">
            <ownedParameter xmi:id="Shape-describe-result" name="result" direction="return">\(primitive("String"))</ownedParameter>
          </ownedOperation>
        </packagedElement>
        <packagedElement xmi:type="uml:Class" xmi:id="Group" name="Group">
          <generalization xmi:id="Group-general" general="Shape"/>
          <ownedAttribute xmi:id="Group-members" name="members" type="Shape" aggregation="composite" subsettedProperty="Shape-parts">
            <lowerValue xmi:type="uml:LiteralInteger" xmi:id="Group-members-lower"/>
            <upperValue xmi:type="uml:LiteralUnlimitedNatural" xmi:id="Group-members-upper" value="*"/>
          </ownedAttribute>
          <ownedAttribute xmi:id="Group-label" name="label" redefinedProperty="Shape-label">\(primitive("String"))</ownedAttribute>
          <ownedOperation xmi:id="Group-describe" name="describe" redefinedOperation="Shape-describe">
            <ownedParameter xmi:id="Group-describe-result" name="result" direction="return">\(primitive("String"))</ownedParameter>
          </ownedOperation>
          <ownedOperation xmi:id="Group-resize_all" name="resize_all"/>
        </packagedElement>
        """)

    @Test("Derived unions, subsets and redefinitions are annotated as UML2 annotates them")
    func unionsSubsetsRedefinitions() async throws {
        let result = try await Self.convert(text: Self.shapes)
        let package = try #require(result.packages.first)
        let shape = try #require(package.getEClass("Shape"))
        let group = try #require(package.getEClass("Group"))
        let parts = try #require(Self.feature("parts", of: shape) as? EReference)
        #expect(parts.getEAnnotation(source: UMLToEcore.Syntax.unionAnnotation) != nil)
        #expect(parts.derived && parts.transient && parts.volatile && !parts.changeable)
        let members = try #require(Self.feature("members", of: group) as? EReference)
        #expect(members.containment)
        #expect(members.getEAnnotation(source: UMLToEcore.Syntax.subsetsAnnotation)?.references.count == 1)
        let duplicates = try #require(group.getEAnnotation(source: UMLToEcore.Syntax.duplicatesAnnotation))
        #expect(Self.contentNames(of: duplicates, kind: "EOperation") == ["describe"])
        #expect(group.eOperations.map(\.name) == ["resize_all"])
        #expect(result.diagnostics.contains { $0.code == UMLToEcore.Diagnostic.unionProperty })
        #expect(result.diagnostics.contains { $0.code == UMLToEcore.Diagnostic.subsettingProperty })
        #expect(result.diagnostics.contains { $0.code == UMLToEcore.Diagnostic.redefiningOperation })

        let api = try await Self.convert(text: Self.shapes, options: .eclipseAPI).packages.first
        let apiParts = try #require(Self.feature("parts", of: api?.getEClass("Shape")) as? EReference)
        #expect(apiParts.getEAnnotation(source: UMLToEcore.Syntax.unionAnnotation) == nil)
        #expect(!apiParts.transient)
    }

    @Test("A feature that duplicates an inherited one is moved, reported or discarded")
    func duplicateFeatures() async throws {
        let processed = try await Self.convert(text: Self.shapes)
        let group = try #require(processed.packages.first?.getEClass("Group"))
        #expect(Self.feature("label", of: group) == nil)
        let duplicates = try #require(group.getEAnnotation(source: UMLToEcore.Syntax.duplicatesAnnotation))
        #expect(Self.contentNames(of: duplicates, kind: "EAttribute") == ["label"])
        #expect(group.allStructuralFeatures.filter { $0.name == "label" }.count == 1)

        var options = UMLToEcore.Options()
        options.duplicateFeatures = .discard
        options.duplicateOperations = .discard
        let discarded = try await Self.convert(text: Self.shapes, options: options)
        let discardedGroup = try #require(discarded.packages.first?.getEClass("Group"))
        #expect(Self.feature("label", of: discardedGroup) == nil)
        #expect(discardedGroup.getEAnnotation(source: UMLToEcore.Syntax.duplicatesAnnotation) == nil)
        #expect(discardedGroup.eOperations.map(\.name) == ["resize_all"])

        options.duplicateFeatures = .report
        let reported = try await Self.convert(text: Self.shapes, options: options)
        #expect(Self.feature("label", of: reported.packages.first?.getEClass("Group")) != nil)
        #expect(reported.diagnostics.contains {
            $0.code == UMLToEcore.Diagnostic.duplicateFeature && $0.severity == .warning
        })
    }

    @Test("Untyped properties are reported, discarded or typed as EObject")
    func untypedProperties() async throws {
        let reported = try await Self.convert(text: Self.shapes)
        let shape = try #require(reported.packages.first?.getEClass("Shape"))
        #expect(Self.feature("note", of: shape) is EAttribute)
        #expect(reported.diagnostics.contains {
            $0.code == UMLToEcore.Diagnostic.untypedProperty && $0.severity == .error
        })

        var options = UMLToEcore.Options()
        options.untypedProperties = .process
        let processed = try await Self.convert(text: Self.shapes, options: options)
        let note = try #require(Self.feature("note", of: processed.packages.first?.getEClass("Shape")) as? EReference)
        #expect(note.eType.name == "EObject")

        options.untypedProperties = .discard
        let discarded = try await Self.convert(text: Self.shapes, options: options)
        #expect(Self.feature("note", of: discarded.packages.first?.getEClass("Shape")) == nil)
    }

    @Test("Default expressions become setting delegate annotations")
    func defaultExpressions() async throws {
        let result = try await Self.convert(text: Self.shapes)
        let package = try #require(result.packages.first)
        let area = try #require(Self.feature("area", of: package.getEClass("Shape")) as? EAttribute)
        #expect(area.getEAnnotationDetail(source: UMLToEcore.Syntax.oclPivotDelegate, key: "initial") == "0.0")
        #expect(area.defaultValueLiteral == nil)
        #expect(package.getEAnnotationDetail(source: AnnotationSource.ecore, key: AnnotationSource.EcoreKey.settingDelegates)
            == UMLToEcore.Syntax.oclPivotDelegate)
    }

    @Test("Names can be converted to camel case")
    func camelCaseNames() async throws {
        var options = UMLToEcore.Options()
        options.camelCaseNames = .process
        let result = try await Self.convert(text: Self.shapes, options: options)
        let group = try #require(result.packages.first?.getEClass("Group"))
        let operation = try #require(group.getOperation(name: "resizeAll"))
        #expect(operation.getEAnnotationDetail(source: UMLToEcore.Syntax.umlAnnotationSource, key: "originalName")
            == "resize_all")
        let kept = try await Self.convert(text: Self.shapes)
        #expect(kept.packages.first?.getEClass("Group")?.getOperation(name: "resize_all") != nil)
    }

    @Test("Options that are not implemented are reported once")
    func unsupportedOptions() async throws {
        var options = UMLToEcore.Options()
        options.duplicateFeatureInheritance = .process
        let result = try await Self.convert(text: Self.shapes, options: options)
        #expect(result.diagnostics.filter { $0.code == UMLToEcore.Diagnostic.unsupportedOption }.count == 1)
    }

    @Test("Camel case names follow the word boundaries of UML2")
    func camelCaseWords() {
        #expect(UMLToEcore.camelCase("resize_all", capitalised: false) == "resizeAll")
        #expect(UMLToEcore.camelCase("XMLParser", capitalised: true) == "XmlParser")
        #expect(UMLToEcore.camelCase("URI", capitalised: false) == "uri")
        #expect(UMLToEcore.camelCase("my shape", capitalised: true) == "MyShape")
        #expect(UMLToEcore.validIdentifier("2nd-place") == "_2ndplace")
        #expect(UMLToEcore.validIdentifier("") == "_")
    }

    @Test("Ecore annotations of the profile are parsed as UML2 parses them")
    func annotationTaggedValues() {
        let parsed = UMLToEcore.parseAnnotation("http://example.org/a key='va\\'lue' other=\"x y\"")
        #expect(parsed?.source == "http://example.org/a")
        #expect(parsed?.details.map(\.0) == ["key", "other"])
        #expect(parsed?.details.map(\.1) == ["va'lue", "x y"])
        #expect(UMLToEcore.parseAnnotation("   ") == nil)
    }

    // MARK: - Further constructs

    /// A model with the Ecore profile applied to many kinds of elements, generic types, nested
    /// classifiers, annotations and further option cases.
    static let profiled = """
        <?xml version="1.0" encoding="UTF-8"?>
        <xmi:XMI xmi:version="20131001" xmlns:xmi="http://www.omg.org/spec/XMI/20131001" \
        xmlns:Ecore="http://www.eclipse.org/uml2/schemas/Ecore/5" xmlns:ecore="http://www.eclipse.org/emf/2002/Ecore" \
        xmlns:uml="http://www.eclipse.org/uml2/5.0.0/UML">
          <uml:Model xmi:id="m" name="store">
            <packagedElement xmi:type="uml:Class" xmi:id="Box" name="Box">
              <eAnnotations xmi:id="Box-note" source="http://example.org/notes">
                <details xmi:id="Box-note-d" key="colour" value="blue"/>
              </eAnnotations>
              <ownedTemplateSignature xmi:type="uml:RedefinableTemplateSignature" xmi:id="Box-sig" parameter="Box-T">
                <ownedParameter xmi:type="uml:ClassifierTemplateParameter" xmi:id="Box-T" parameteredElement="Box-T-c">
                  <ownedParameteredElement xmi:type="uml:Class" xmi:id="Box-T-c" name="T" templateParameter="Box-T"/>
                </ownedParameter>
              </ownedTemplateSignature>
              <nestedClassifier xmi:type="uml:Class" xmi:id="Lid" name="Lid"/>
              <ownedAttribute xmi:id="Box-code" name="code">\(primitive("String"))
                <lowerValue xmi:type="uml:LiteralInteger" xmi:id="Box-code-l"/>
              </ownedAttribute>
              <ownedAttribute xmi:id="Box-size" name="size" type="Size">
                <lowerValue xmi:type="uml:LiteralInteger" xmi:id="Box-size-l"/>
              </ownedAttribute>
              <ownedAttribute xmi:id="Box-weight" name="weight" type="Grams"/>
              <ownedAttribute xmi:id="Box-shelf" name="shelf" type="Shelf" association="Box-on"/>
              <ownedOperation xmi:id="Box-seal" name="seal">
                <ownedParameter xmi:id="Box-seal-force" name="force">\(primitive("Boolean"))</ownedParameter>
              </ownedOperation>
              <ownedOperation xmi:id="Box-open" name="open" method="Box-open-impl"/>
              <ownedBehavior xmi:type="uml:OpaqueBehavior" xmi:id="Box-open-impl" name="openImpl" specification="Box-open">
                <language>Java</language>
                <body>return;</body>
              </ownedBehavior>
            </packagedElement>
            <packagedElement xmi:type="uml:Class" xmi:id="Shelf" name="Shelf">
              <ownedAttribute xmi:id="Shelf-bin" name="bin" type="BoxOfShelves"/>
              <ownedAttribute xmi:id="Shelf-label" name="label">\(primitive("String"))</ownedAttribute>
            </packagedElement>
            <packagedElement xmi:type="uml:Association" xmi:id="Box-on" name="on" memberEnd="Box-shelf Box-on-box">
              <ownedEnd xmi:id="Box-on-box" name="crate" type="Box" association="Box-on"/>
            </packagedElement>
            <packagedElement xmi:type="uml:DataType" xmi:id="BoxOfShelves" name="BoxOfShelves">
              <templateBinding xmi:id="BoxOfShelves-b" signature="Box-sig">
                <parameterSubstitution xmi:id="BoxOfShelves-s" actual="Shelf" formal="Box-T"/>
              </templateBinding>
            </packagedElement>
            <packagedElement xmi:type="uml:Enumeration" xmi:id="Size" name="Size">
              <ownedLiteral xmi:id="Size-small" name="small"/>
              <ownedLiteral xmi:id="Size-large" name="large"/>
            </packagedElement>
            <packagedElement xmi:type="uml:PrimitiveType" xmi:id="Grams" name="Grams">
              <generalization xmi:id="Grams-g">
                <general xmi:type="uml:PrimitiveType" href="pathmap://UML_LIBRARIES/UMLPrimitiveTypes.library.uml#Integer"/>
              </generalization>
            </packagedElement>
            <packagedElement xmi:type="uml:PrimitiveType" xmi:id="Kilograms" name="Kilograms">
              <generalization xmi:id="Kilograms-g" general="Grams"/>
            </packagedElement>
            <packagedElement xmi:type="uml:Class" xmi:id="Crate" name="Crate">
              <generalization xmi:id="Crate-g1" general="Shelf"/>
              <generalization xmi:id="Crate-g2" general="Box"/>
              <ownedAttribute xmi:id="Crate-lost" name="lost">
                <type xmi:type="uml:Class" href="missing.uml#Nowhere"/>
              </ownedAttribute>
            </packagedElement>
          </uml:Model>
          <Ecore:EPackage xmi:id="m-p" base_Package="m" packageName="shop" nsURI="http://example.org/store" basePackage="org.example"/>
          <Ecore:EClass xmi:id="Box-c" base_Class="Box" xmlName="box-element" xmlContentKind="ElementOnly"/>
          <Ecore:EAttribute xmi:id="Box-code-a" base_Property="Box-code" isTransient="true" isVolatile="true" xmlName="CODE" xmlNamespace="http://example.org/xml" xmlFeatureKind="Attribute" visibility="ReadOnly">
            <annotations>http://example.org/extra key='va\\'lue' other="x"</annotations>
          </Ecore:EAttribute>
          <Ecore:EReference xmi:id="Box-shelf-r" base_Property="Box-shelf" referenceName="place" keys="Shelf-label"/>
          <Ecore:EOperation xmi:id="Box-seal-o" base_Operation="Box-seal" operationName="close" visibility="None"/>
          <Ecore:EParameter xmi:id="Box-seal-force-p" base_Parameter="Box-seal-force" parameterName="hard"/>
          <Ecore:EEnum xmi:id="Size-e" base_Enumeration="Size" enumName="Dimension"/>
          <Ecore:EEnumLiteral xmi:id="Size-small-l" base_EnumerationLiteral="Size-small" enumLiteralName="SMALL" literal="s"/>
          <Ecore:EGenericType xmi:id="BoxOfShelves-g" base_DataType="BoxOfShelves"/>
        </xmi:XMI>
        """

    @Test("The tagged values of the Ecore profile are applied to every kind of element")
    func profileTaggedValues() async throws {
        let result = try await Self.convert(text: Self.profiled)
        let package = try #require(result.packages.first)
        #expect(package.name == "shop")
        #expect(package.nsURI == "http://example.org/store")
        #expect(package.nsPrefix == "store")
        let box = try #require(package.getEClass("Box"))
        #expect(box.getEAnnotationDetail(source: AnnotationSource.extendedMetaData, key: "name") == "box-element")
        #expect(box.getEAnnotationDetail(source: AnnotationSource.extendedMetaData, key: "kind") == "elementOnly")
        let code = try #require(Self.feature("code", of: box) as? EAttribute)
        #expect(code.transient && code.volatile)
        #expect(code.getEAnnotationDetail(source: AnnotationSource.extendedMetaData, key: "name") == "CODE")
        #expect(code.getEAnnotationDetail(source: AnnotationSource.extendedMetaData, key: "namespace")
            == "http://example.org/xml")
        #expect(code.getEAnnotationDetail(source: AnnotationSource.extendedMetaData, key: "kind") == "attribute")
        #expect(code.getEAnnotationDetail(source: AnnotationSource.genModel, key: "suppressedSetVisibility") == "true")
        #expect(code.getEAnnotationDetail(source: "http://example.org/extra", key: "key") == "va'lue")
        #expect(code.getEAnnotationDetail(source: "http://example.org/extra", key: "other") == "x")
        let place = try #require(Self.feature("place", of: box) as? EReference)
        let label = try #require(Self.feature("label", of: package.getEClass("Shelf")))
        #expect(place.eKeys == [label.id])
        let close = try #require(box.getOperation(name: "close"))
        #expect(close.getEAnnotationDetail(source: AnnotationSource.genModel, key: "suppressedVisibility") == "true")
        #expect(close.eParameters.map(\.name) == ["hard"])
        #expect(close.lowerBound == 1)
        #expect(close.eType == nil)
        let size = try #require(package.getEEnum("Dimension"))
        #expect(size.literals.map(\.name) == ["SMALL", "large"])
        #expect(size.literals.first?.literal == "s")
    }

    @Test("Annotations, nested classifiers, generic types, data type bases and Java bodies are converted")
    func furtherConstructs() async throws {
        let result = try await Self.convert(text: Self.profiled)
        let package = try #require(result.packages.first)
        let box = try #require(package.getEClass("Box"))
        #expect(box.getEAnnotationDetail(source: "http://example.org/notes", key: "colour") == "blue")
        let lid = try #require(package.getEClass("Box_Lid"))
        #expect(lid.getEAnnotationDetail(source: UMLToEcore.Syntax.umlAnnotationSource, key: "originalName") == "Lid")
        #expect(package.getClassifier("BoxOfShelves") == nil)
        let bin = try #require(Self.feature("bin", of: package.getEClass("Shelf")) as? EReference)
        #expect(bin.containment)
        #expect(bin.eGenericType?.eClassifier?.name == "Box")
        #expect(bin.eGenericType?.eTypeArguments.map { $0.eClassifier?.name } == ["Shelf"])
        let kilograms = try #require(package.getEDataType("Kilograms"))
        #expect(kilograms.getEAnnotationDetail(source: AnnotationSource.extendedMetaData, key: "baseType") == "Grams")
        let open = try #require(box.getOperation(name: "open"))
        #expect(open.getEAnnotationDetail(source: AnnotationSource.genModel, key: "body") == "return;")
        let crate = try #require(package.getEClass("Crate"))
        #expect(crate.eSuperTypes.map(\.name) == ["Box", "Shelf"])
        #expect(result.diagnostics.contains {
            $0.code == UMLToEcore.Diagnostic.superClassOrder && $0.severity == .information
        })
        #expect(result.diagnostics.contains {
            $0.code == UMLToEcore.Diagnostic.unsupported && $0.message.contains("missing.uml")
        })
    }

    @Test("Optional attributes become unsettable or nullable, and opposite role names are recorded, on request")
    func optionalAttributesAndRoleNames() async throws {
        var options = UMLToEcore.Options()
        options.unsettablePrimitiveAttributes = .process
        options.nullableEnumAttributes = .process
        options.oppositeRoleNames = .process
        let result = try await Self.convert(text: Self.profiled, options: options)
        let package = try #require(result.packages.first)
        let box = try #require(package.getEClass("Box"))
        #expect((Self.feature("code", of: box) as? EAttribute)?.unsettable == true)
        let size = try #require(Self.feature("size", of: box) as? EAttribute)
        #expect(size.unsettable)
        #expect(size.eType.name == "Size_Optional")
        let optional = try #require(package.getEDataType("Size_Optional"))
        #expect(optional.instanceClassName == "org.eclipse.emf.common.util.Enumerator")
        let place = try #require(Self.feature("place", of: box) as? EReference)
        #expect(place.getEAnnotationDetail(source: UMLToEcore.Syntax.oppositeRoleNameAnnotation, key: "body") == "crate")

        options = UMLToEcore.Options()
        options.unsettablePrimitiveAttributes = .report
        options.comments = .report
        let reported = try await Self.convert(text: Self.profiled, options: options)
        #expect(reported.diagnostics.contains {
            $0.code == UMLToEcore.Diagnostic.optionalAttribute && $0.severity == .warning
        })
        #expect((Self.feature("code", of: reported.packages.first?.getEClass("Box")) as? EAttribute)?.unsettable == false)
    }
}
