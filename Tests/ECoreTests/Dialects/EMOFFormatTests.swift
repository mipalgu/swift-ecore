import EMFBase
import Foundation
import Testing

@testable import ECore

/// Verifies that EMOF metamodels are read and written as EMF reads and writes them.
@Suite("EMOF metamodels")
struct EMOFFormatTests {
    /// The directory of the dialect fixtures.
    static let directory = OMGXMIDialectTests.directory

    /// The directory of the existing test resources.
    static let resources = directory.deletingLastPathComponent()

    /// Reads the EMOF fixture into a new resource set.
    static func readLibrary(in resourceSet: ResourceSet = ResourceSet()) async throws -> ModelDocumentReadResult {
        try await EMOFFormat.read(url: directory.appendingPathComponent("library.emof"), resourceSet: resourceSet)
    }

    /// The feature of a class with a given name.
    static func feature(_ name: String, of eClass: EClass) -> (any EStructuralFeature)? {
        eClass.eStructuralFeatures.first { $0.name == name }
    }

    @Test("An EMOF metamodel is read with the mapping of EMF")
    func readsMetamodel() async throws {
        let read = try await Self.readLibrary()
        #expect(read.diagnostics.isEmpty, "\(read.diagnostics.map(\.message))")
        let package = try #require(read.packages.first)
        #expect(read.packages.count == 1)
        #expect(package.name == "library")
        #expect(package.nsURI == "http://example.org/library")
        #expect(package.nsPrefix == "lib")
        #expect(package.eAnnotations.first?.source == EMOFSyntax.commentSource)
        #expect(package.eAnnotations.first?.details["body"] == "A small lending library.")

        let item = try #require(package.getEClass("Item"))
        let book = try #require(package.getEClass("Book"))
        let author = try #require(package.getEClass("Author"))
        let library = try #require(package.getEClass("Library"))
        #expect(item.isAbstract)
        #expect(book.eSuperTypes.map(\.name) == ["Item"])

        let title = try #require(Self.feature("title", of: item) as? EAttribute)
        #expect(title.eType.name == "EString")
        #expect(title.lowerBound == 0 && title.upperBound == 1 && title.ordered && title.unique)
        let code = try #require(Self.feature("code", of: item) as? EAttribute)
        #expect(code.lowerBound == 1)
        #expect(code.isID)
        #expect(!code.changeable)

        let pages = try #require(Self.feature("pages", of: book) as? EAttribute)
        #expect(pages.eType.name == "EInt")
        let format = try #require(Self.feature("format", of: book) as? EAttribute)
        #expect(format.eType.name == "Format")
        #expect(format.defaultValueLiteral == "Hardback")
        let published = try #require(Self.feature("published", of: book) as? EAttribute)
        #expect(published.eType.name == "EDate")
        #expect(published.transient)
        let authors = try #require(Self.feature("authors", of: book) as? EReference)
        let books = try #require(Self.feature("books", of: author) as? EReference)
        #expect(authors.upperBound == -1)
        #expect(authors.opposite == books.id)
        #expect(books.opposite == authors.id)
        #expect(!books.unique)
        let items = try #require(Self.feature("items", of: library) as? EReference)
        #expect(items.containment)

        let lend = try #require(book.eOperations.first)
        #expect(lend.name == "lend")
        #expect(lend.eType?.name == "EBoolean")
        #expect(lend.eParameters.map(\.name) == ["days"])
        #expect(lend.eParameters.first?.eType?.name == "EInt")
        #expect(book.getEAnnotationDetail(source: AnnotationSource.genModel, key: "documentation")
            == "A book that can be lent.")
        let tag = try #require(book.eAnnotations.first { $0.source == EMOFSyntax.namespaceURI })
        #expect(tag.details["name"] == "org.example.audience")
        #expect(tag.details["value"] == "students")

        let formats = try #require(package.getEEnum("Format"))
        #expect(formats.literals.map(\.name) == ["Paperback", "Hardback"])
        #expect(formats.literals.map(\.value) == [0, 1])
        #expect(package.getEDataType("Isbn")?.instanceClassName == "java.lang.String")
        let shelving = try #require(package.getSubpackage("shelving"))
        #expect(shelving.nsPrefix == "shelf")
        let holds = try #require(shelving.getEClass("Shelf").flatMap { Self.feature("holds", of: $0) } as? EReference)
        #expect(holds.eType.name == "Item")
    }

    @Test("An EMOF metamodel round-trips")
    func roundTrips() async throws {
        let first = try await Self.readLibrary()
        let written = EMOFFormat.write(first.packages)
        let text = written.text
        #expect(text.hasPrefix("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<xmi:XMI xmi:version=\"2.0\""))
        #expect(text.contains("xmlns:emof=\"http://schema.omg.org/spec/MOF/2.0/emof.xml\""))
        #expect(text.contains("<emof:Package xmi:id=\"library\" name=\"library\" uri=\"http://example.org/library\">"))
        #expect(text.contains("<nsPrefix>lib</nsPrefix>"))
        #expect(text.contains("<ownedType xmi:type=\"emof:Class\" xmi:id=\"library.Book\" name=\"Book\" superClass=\"library.Item\">"))
        #expect(text.contains("xmi:id=\"library.Book.authors\" name=\"authors\" isOrdered=\"true\" lower=\"0\" upper=\"*\" type=\"library.Author\" opposite=\"library.Author.books\""))
        #expect(text.contains("<type xmi:type=\"emof:PrimitiveType\" href=\"http://schema.omg.org/spec/MOF/2.0/emof.xml#String\"/>"))
        #expect(text.contains("href=\"http://www.eclipse.org/emf/2002/Ecore.emof#ecore.EDate\""))
        #expect(text.contains("isReadOnly=\"true\""))
        #expect(text.contains("isComposite=\"true\""))
        #expect(text.contains("<ownedComment body=\"A small lending library.\"/>"))
        #expect(text.contains("<emof:Tag xmi:id=\"_tag0\" name=\"org.example.audience\" value=\"students\" element=\"library.Book\"/>"))
        #expect(EMOFFormat.sniff(data: Data(text.utf8)))

        let second = try await EMOFFormat.read(
            data: Data(text.utf8), uri: Self.directory.appendingPathComponent("library-copy.emof").absoluteString,
            resourceSet: ResourceSet())
        #expect(second.diagnostics.isEmpty, "\(second.diagnostics.map(\.message))")
        #expect(EMOFFormat.write(second.packages).text == text)
        let firstEcore = XMISerializer(options: .emf).serialize(first.packages)
        let secondEcore = XMISerializer(options: .emf).serialize(second.packages)
        #expect(firstEcore == secondEcore)
    }

    @Test(
        "Ecore metamodels survive a round trip through EMOF",
        arguments: [
            "xmi/animals.ecore", "metamodels/Families.ecore", "xmi/organisation.ecore", "xmi/classifiers.ecore",
            "jsonmeta/JSONLibrary.ecore", "metamodels/Nested.ecore", "annotations/annotated.ecore",
        ])
    func ecoreRoundTrips(path: String) async throws {
        let url = Self.resources.appendingPathComponent(path)
        let original = try await EPackage.rootPackages(url: url)
        let emof = EMOFFormat.write(original, relativeTo: url)
        let read = try await EMOFFormat.read(
            data: Data(emof.text.utf8), uri: url.deletingPathExtension().appendingPathExtension("emof").absoluteString,
            resourceSet: ResourceSet())
        #expect(!read.diagnostics.contains { $0.severity == .error }, "\(read.diagnostics.map(\.message))")
        #expect(EMOFFormat.write(read.packages, relativeTo: url).text == emof.text)
        #expect(read.packages.map(\.name) == original.map(\.name))
        for (copy, source) in zip(read.packages, original) {
            #expect(copy.nsURI == source.nsURI)
            #expect(copy.nsPrefix == source.nsPrefix)
            #expect(copy.eClassifiers.map(\.name) == source.eClassifiers.map(\.name))
        }
    }

    @Test("EMOF documents are recognised, and CMOF and other documents are refused")
    func recognisesDocuments() async throws {
        let library = try Data(contentsOf: Self.directory.appendingPathComponent("library.emof"))
        #expect(EMOFFormat.sniff(data: library))
        #expect(!EMOFFormat.sniff(data: try Data(contentsOf: Self.directory.appendingPathComponent("shop.ecore"))))
        #expect(!EMOFFormat.sniff(data: try Data(contentsOf: Self.directory.appendingPathComponent("garden.uml"))))
        #expect(EMOFFormat.fileExtension == "emof")
        let single = """
            <emof:Package xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI" \
            xmlns:emof="http://schema.omg.org/spec/mof/2.0/emof.xmi" xmi:id="p" name="p" uri="urn:p">
              <ownedType xmi:type="emof:Class" xmi:id="p.A" name="A"/>
            </emof:Package>
            """
        #expect(EMOFFormat.sniff(data: Data(single.utf8)))
        let read = try await EMOFFormat.read(data: Data(single.utf8), uri: "memory:/p.emof", resourceSet: ResourceSet())
        #expect(read.packages.first?.getEClass("A") != nil)

        let cmof = """
            <cmof:Package xmlns:xmi="http://schema.omg.org/spec/XMI/2.1" \
            xmlns:cmof="http://schema.omg.org/spec/MOF/2.0/cmof.xml" xmi:id="p" name="p"/>
            """
        await #expect(throws: EMOFError.cmofNotSupported("memory:/p.cmof")) {
            try await EMOFFormat.read(data: Data(cmof.utf8), uri: "memory:/p.cmof", resourceSet: ResourceSet())
        }
        let ecore = try Data(contentsOf: Self.directory.appendingPathComponent("shop.ecore"))
        await #expect(throws: EMOFError.self) {
            try await EMOFFormat.read(data: ecore, uri: "memory:/shop.ecore", resourceSet: ResourceSet())
        }
    }

    @Test("Unknown EMOF content is reported and left out")
    func reportsUnsupportedContent() async throws {
        let text = """
            <xmi:XMI xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI" \
            xmlns:emof="http://schema.omg.org/spec/MOF/2.0/emof.xml">
              <emof:Package xmi:id="p" name="p" uri="urn:p">
                <xmi:Extension extender="urn:another-tool"><layout/></xmi:Extension>
                <ownedType xmi:type="emof:Class" xmi:id="p.A" name="A">
                  <ownedAttribute xmi:id="p.A.size" name="size">
                    <type xmi:type="emof:PrimitiveType" href="http://schema.omg.org/spec/MOF/2.0/emof.xml#Colour"/>
                  </ownedAttribute>
                </ownedType>
              </emof:Package>
              <emof:Tag xmi:id="t" name="orphan" value="1"/>
            </xmi:XMI>
            """
        let read = try await EMOFFormat.read(data: Data(text.utf8), uri: "memory:/p.emof", resourceSet: ResourceSet())
        let unsupported = read.diagnostics.filter { $0.code == ModelDocumentDiagnostic.unsupportedEMOF }
        #expect(unsupported.count == 3)
        let size = try #require(read.packages.first?.getEClass("A")?.eStructuralFeatures.first as? EAttribute)
        #expect(size.eType.name == "EString")
        #expect(size.lowerBound == 1)
        #expect(!size.ordered)
    }
}
