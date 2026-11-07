//
// MetaDepthTextTests.swift
// MultiLevelTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Testing

@testable import MultiLevel

/// Tests the MetaDepth reader and canonical writer.
@Suite("MetaDepth text")
struct MetaDepthTextTests {
    static let fixtures = [
        MultiLevelFixtures.products, MultiLevelFixtures.arcade, MultiLevelFixtures.process,
        MultiLevelFixtures.bicycles, MultiLevelFixtures.retail,
    ]

    @Test("every fixture reads without diagnostics", arguments: fixtures)
    func fixturesRead(text: String) {
        let result = MetaDepthReader.parse(text, sourceName: "fixture.mdepth")
        #expect(result.diagnostics.isEmpty, "\(result.diagnostics.map(\.message))")
        #expect(result.model != nil)
    }

    @Test("text reads into a model that writes back into equal text", arguments: fixtures)
    func roundTrip(text: String) throws {
        let model = try MultiLevelFixtures.model(text)
        let written = MetaDepthWriter.write(model)
        #expect(written.diagnostics.isEmpty)
        let reread = try MultiLevelFixtures.model(written.text)
        #expect(reread == model)
        #expect(MetaDepthWriter.write(reread).text == written.text)
    }

    @Test("the canonical text of the product fixture keeps declared potencies only")
    func canonicalText() throws {
        let model = try MultiLevelFixtures.model(MultiLevelFixtures.products)
        let text = MetaDepthWriter.write(model).text
        #expect(text.hasPrefix("Model Commerce@2 {\n  Node ProductType {\n    vat@1 : double = 7.5;\n"))
        #expect(text.contains("    authors : Author[*];\n"))
        #expect(text.contains("    authors = [gamma, helm];\n"))
        #expect(text.contains("    name = \"E. Gamma\";\n"))
        #expect(text.contains("  someProducts@2 : $ProductType.allInstances()->size() >= 1$\n"))
        #expect(text.contains("  Book draft {}\n"))
    }

    @Test("explicit potencies are written on request, as MetaDepth dumps models")
    func explicitPotencies() throws {
        let model = try MultiLevelFixtures.model(MultiLevelFixtures.products)
        let text = MetaDepthWriter.write(model, options: .init(explicitPotencies: true)).text
        #expect(text.contains("BookStore Shop@0 {"))
        #expect(text.contains("    price@2 : double = 10.0;"))
        #expect(text.contains("  Book patterns@0 {"))
        let reread = try MultiLevelFixtures.model(text)
        #expect(reread.levels.map(\.clabjects.count) == model.levels.map(\.clabjects.count))
    }

    @Test("leap potency, deep references, edges, modifiers and Melanee potency are written back")
    func notationDetails() throws {
        let arcade = MetaDepthWriter.write(try MultiLevelFixtures.model(MultiLevelFixtures.arcade)).text
        #expect(arcade.contains("  Node Tile@(2) {"))
        #expect(arcade.contains("    elements : ElementKind@0[*];"))
        #expect(arcade.contains("  abstract Node CharacterKind : ElementKind {}"))
        let process = MetaDepthWriter.write(try MultiLevelFixtures.model(MultiLevelFixtures.process)).text
        #expect(process.contains("    tests : Testing[1..*] {next};"))
        let bicycles = MetaDepthWriter.write(try MultiLevelFixtures.model(MultiLevelFixtures.bicycles)).text
        #expect(bicycles.contains("    alternative : BicycleType {level=1};"))
        #expect(bicycles.contains("    frame : FrameType[1];"))
        let retail = MetaDepthWriter.write(try MultiLevelFixtures.model(MultiLevelFixtures.retail)).text
        #expect(retail.hasPrefix("Model Retail@2 melanee {"))
        #expect(retail.contains("    vat@1/0 : double = 20.0;"))
        #expect(retail.contains("  Node Category@* {"))
    }

    /// A library language with an edge, a derived feature and data-typed defaults.
    static let edgeText = """
            strict Model Library@2 {
              Node Writer {
                books : Volume[*];
                /bookCount : int = $self.books->size()$;
              }
              Node Volume {
                writers : Writer[*];
                title : String = "A \\"quoted\\" title";
                ratio : double = -1.5;
                year : int = -12;
                lent : boolean = false;
              }
              Edge Writes(Writer.books, Volume.writers) {
                share : double = 1.0;
              }
            }
            Library Catalogue {
              Writer author {}
              Volume novel {}
              Writes credit(author, novel) {
                share = 0.5;
              }
            }
            """

    @Test("edges, derived features, strict models and escaped strings round-trip")
    func edgesAndDerivedFeatures() throws {
        let text = Self.edgeText
        let model = try MultiLevelFixtures.model(text)
        #expect(model.levels[0].isExtensible == false)
        let writes = try #require(model.clabject(named: "Writes"))
        #expect(writes.isEdge)
        #expect(try writes.ends?.source == EdgeEnd(clabject: model.id("Writer"), feature: "books"))
        let credit = try #require(model.clabject(named: "credit"))
        #expect(try credit.ends?.target == EdgeEnd(clabject: model.id("novel")))
        let derived = try #require(model.clabject(named: "Writer")?.feature(named: "bookCount"))
        #expect(derived.isDerived && derived.derivation == "self.books->size()")
        #expect(model.clabject(named: "Volume")?.feature(named: "title")?.defaultValues == [.string("A \"quoted\" title")])
        let written = MetaDepthWriter.write(model).text
        #expect(written.hasPrefix("strict Model Library@2 {"))
        #expect(written.contains("  Edge Writes(Writer.books, Volume.writers) {"))
        #expect(written.contains("  Writes credit(author, novel) {"))
        #expect(written.contains("    /bookCount : int = $self.books->size()$;"))
        #expect(try MultiLevelFixtures.model(written) == model)
    }

    // MARK: - Diagnostics

    @Test("embedded EOL blocks and EOL constraint bodies are rejected")
    func eolRejected() throws {
        let text = """
            Model M@1 {
              Node A {
                x : int;
                bad : $var y := self.x; y > 0$
              }
            }
            # EOL
            A.all.println();
            #
            """
        let result = MetaDepthReader.parse(text, sourceName: "eol.mdepth")
        let codes = result.diagnostics.map(\.code)
        #expect(codes.contains(MultiLevelDiagnosticCode.unsupported))
        #expect(codes.contains(MultiLevelDiagnosticCode.constraintLanguage))
        #expect(result.diagnostics.allSatisfy { $0.document == "eol.mdepth" && $0.range != nil })
        #expect(result.model?.clabject(named: "A") != nil)
    }

    @Test("imports, unknown names and duplicates are reported with positions")
    func nameDiagnostics() {
        let text = """
            Model M@2 {
              Node A { b : Missing; }
              Node A {}
              Node C : Nowhere {}
            }
            M N imports Other {
              Ghost g {}
            }
            """
        let result = MetaDepthReader.parse(text)
        let messages = result.diagnostics.map(\.message)
        #expect(messages.contains { $0.contains("imports") })
        #expect(messages.contains { $0.contains("'Missing'") })
        #expect(messages.contains { $0.contains("declared twice") })
        #expect(messages.contains { $0.contains("'Nowhere'") })
        #expect(messages.contains { $0.contains("'Ghost'") })
        #expect(result.diagnostics.allSatisfy { $0.range != nil })
    }

    @Test("structural problems of the model chain are reported")
    func chainDiagnostics() {
        #expect(MetaDepthReader.parse("Model M { }").hasErrors)
        #expect(MetaDepthReader.parse("A B { }").diagnostics.first?.code == MultiLevelDiagnosticCode.levelChain)
        let branched = MetaDepthReader.parse("Model M@1 { Node A {} }\nM X { }\nM Y { }")
        #expect(branched.diagnostics.contains { $0.code == MultiLevelDiagnosticCode.levelChain })
        #expect(branched.model?.levels.map(\.name) == ["M", "X"])
        #expect(MetaDepthReader.parse("Model M@1 dual { }").diagnostics.first?.code == MultiLevelDiagnosticCode.potency)
        #expect(MetaDepthReader.parse("Model M@1 { Node A { x@(2) : int; } }").hasErrors)
        #expect(MetaDepthReader.parse("Model M@1 { Node A { \"oops\" } }").hasErrors)
        #expect(MetaDepthReader.parse("Model M@1 { Node A { s = \"open } }").hasErrors)
        #expect(MetaDepthReader.parse("Model M@1 { Node A { c : $open } }").hasErrors)
        #expect(MetaDepthReader.parse("").model == nil)
    }

    @Test("a MetaDepth document is recognised by its start")
    func recognition() {
        #expect(MetaDepthReader.looksLikeMetaDepth(MultiLevelFixtures.products))
        #expect(MetaDepthReader.looksLikeMetaDepth("// comment\next Model M@1 {}"))
        #expect(!MetaDepthReader.looksLikeMetaDepth("Commerce Store { }"))
        #expect(!MetaDepthReader.looksLikeMetaDepth("<xml/>"))
        #expect(!MetaDepthReader.looksLikeMetaDepth("package p;"))
    }
}
