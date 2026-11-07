import EMFBase
import Foundation
import Testing

@testable import ECore

/// Verifies that XMI documents are read in the encoding that their XML declaration names.
@Suite("XMI encodings")
struct XMIEncodingTests {
    /// The source of documentation annotations.
    private static let documentationSource = "http://www.eclipse.org/emf/2002/GenModel"

    /// An Ecore document with a declaration naming an encoding and a documentation value.
    ///
    /// - Parameters:
    ///   - encoding: The encoding named in the declaration, or `nil` for no declaration.
    ///   - value: The bytes of the documentation value in the target encoding.
    /// - Returns: The bytes of the document; everything but the value is ASCII.
    private static func ecore(declaring encoding: String?, value: [UInt8]) -> Data {
        let declaration = encoding.map { "<?xml version=\"1.0\" encoding=\"\($0)\"?>\n" } ?? ""
        let head = declaration + """
        <ecore:EPackage xmlns:xmi="http://www.omg.org/XMI" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
            xmlns:ecore="http://www.eclipse.org/emf/2002/Ecore" name="notes" nsURI="urn:test:notes" nsPrefix="notes">
          <eClassifiers xsi:type="ecore:EClass" name="Note">
            <eAnnotations source="\(documentationSource)">
              <details key="documentation" value="
        """
        let tail = """
        "/>
            </eAnnotations>
          </eClassifiers>
        </ecore:EPackage>

        """
        return Data(Array(head.utf8) + value + Array(tail.utf8))
    }

    /// The ISO-8859-1 bytes of "Café".
    private static let cafeLatin1: [UInt8] = Array("Caf".utf8) + [0xE9]

    /// Loads an Ecore document from bytes through an in-memory handler.
    private static func load(_ data: Data, uri: String = "memory:/notes.ecore") async throws -> (Resource, EPackage) {
        let set = ResourceSet()
        await set.setURIHandlers([InMemoryURIHandler(documents: [uri: data])])
        let resource = try await set.loadEcoreResource(uri: uri)
        let package = try #require(await resource.getRootObjects().first as? EPackage)
        return (resource, package)
    }

    /// The documentation of the class of a loaded package.
    private static func documentation(_ package: EPackage) -> String? {
        package.getEClass("Note")?.eAnnotations.first { $0.source == documentationSource }?.details["documentation"]
    }

    @Test("A document declared as ISO-8859-1 is read in that encoding")
    func latin1() async throws {
        let (resource, package) = try await Self.load(Self.ecore(declaring: "ISO-8859-1", value: Self.cafeLatin1))
        #expect(Self.documentation(package) == "Caf\u{E9}")
        #expect(await resource.loadDiagnostics.isEmpty)
    }

    @Test("A document declared as windows-1252 is read in that encoding")
    func windows1252() async throws {
        let (_, package) = try await Self.load(Self.ecore(declaring: "windows-1252", value: [0x93] + Array("Hi".utf8) + [0x94, 0x80]))
        #expect(Self.documentation(package) == "\u{201C}Hi\u{201D}\u{20AC}")
    }

    @Test("A document in UTF-16 is read whether or not it starts with a byte order mark")
    func utf16() async throws {
        let text = String(decoding: Self.ecore(declaring: "UTF-16", value: Array("Caf\u{E9}".utf8)), as: UTF8.self)
        let littleEndian = text.utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }
        let bigEndian = text.utf16.flatMap { [UInt8($0 >> 8), UInt8($0 & 0xFF)] }
        for bytes in [[0xFF, 0xFE] + littleEndian, [0xFE, 0xFF] + bigEndian, littleEndian, bigEndian] {
            let (_, package) = try await Self.load(Data(bytes))
            #expect(Self.documentation(package) == "Caf\u{E9}")
        }
    }

    @Test("A transcoded document is written back as UTF-8")
    func transcodedDeclaration() async throws {
        let (_, package) = try await Self.load(Self.ecore(declaring: "ISO-8859-1", value: Self.cafeLatin1))
        let written = XMISerializer().serialize(package)
        #expect(written.hasPrefix("<?xml version=\"1.0\" encoding=\"\(EcoreDocumentMetadata.defaultEncoding)\"?>"))
        #expect(written.contains("Caf\u{E9}"))
    }

    @Test("A UTF-8 document keeps its declared spelling, even when it names another encoding")
    func utf8DeclarationKept() async throws {
        let ascii = try await Self.load(Self.ecore(declaring: "ISO-8859-1", value: Array("Cafe".utf8)))
        #expect(XMISerializer().serialize(ascii.1).hasPrefix("<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?>"))
        let utf8 = try await Self.load(Self.ecore(declaring: "ISO-8859-1", value: Array("Caf\u{E9}".utf8)))
        #expect(Self.documentation(utf8.1) == "Caf\u{E9}")
        let lower = try await Self.load(Self.ecore(declaring: "utf-8", value: Array("Caf\u{E9}".utf8)))
        #expect(XMISerializer().serialize(lower.1).hasPrefix("<?xml version=\"1.0\" encoding=\"utf-8\"?>"))
    }

    @Test("A byte order mark in front of UTF-8 is handled as before")
    func utf8ByteOrderMark() async throws {
        let plain = Self.ecore(declaring: "UTF-8", value: Array("Caf\u{E9}".utf8))
        let (_, unmarked) = try await Self.load(plain)
        let (_, marked) = try await Self.load(Data([0xEF, 0xBB, 0xBF]) + plain)
        #expect(Self.documentation(marked) == "Caf\u{E9}")
        #expect(XMISerializer().serialize(marked) == XMISerializer().serialize(unmarked))
    }

    @Test("A document that is not UTF-8 and declares no other encoding is still rejected")
    func undeclared() async {
        for declared in [nil, "UTF-8"] {
            await #expect(throws: XMIError.self) {
                _ = try await Self.load(Self.ecore(declaring: declared, value: Self.cafeLatin1))
            }
            do {
                _ = try await XMIParser().parse(Self.ecore(declaring: declared, value: Self.cafeLatin1), uri: "memory:/notes.ecore")
                Issue.record("A document that is not UTF-8 was accepted")
            } catch XMIError.invalidEncoding {
            } catch {
                Issue.record("Unexpected error \(error)")
            }
        }
    }

    @Test("A document declaring an unsupported encoding is rejected")
    func unsupported() async {
        do {
            _ = try await XMIParser().parse(Self.ecore(declaring: "ISO-8859-15", value: Self.cafeLatin1), uri: "memory:/notes.ecore")
            Issue.record("A document in an unsupported encoding was accepted")
        } catch XMIError.invalidEncoding {
        } catch {
            Issue.record("Unexpected error \(error)")
        }
    }

    @Test("A model instance declared as ISO-8859-1 is read in that encoding")
    func instanceDocument() async throws {
        let text = """
        <?xml version="1.0" encoding="ISO-8859-1"?>
        <notes:Note xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI" xmlns:notes="urn:test:notes" title="
        """
        let data = Data(Array(text.utf8) + Self.cafeLatin1 + Array("\"/>\n".utf8))
        let resource = try await XMIParser().parse(data, uri: "memory:/note.xmi")
        let root = try #require(await resource.getRootObjects().first)
        #expect((root as? DynamicEObject)?.eGet("title") as? String == "Caf\u{E9}")
    }

    @Test("Model loading reads a declared encoding")
    func modelIO() async throws {
        let loaded = try await ModelIO.load(
            data: Self.ecore(declaring: "ISO-8859-1", value: Self.cafeLatin1), uri: "memory:/notes.ecore",
            format: .ecore, resourceSet: ResourceSet())
        #expect(loaded.packages.first.flatMap(Self.documentation) == "Caf\u{E9}")
    }
}
