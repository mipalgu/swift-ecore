//
// XcoreReaderTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Testing

@testable import ECore

/// Tests that each structural Xcore construct is read into the expected native Ecore element.
@Suite("Xcore reader")
struct XcoreReaderTests {
    // MARK: Packages

    /// A qualified package name gives the last segment, the base package and defaults.
    @Test func qualifiedPackage() throws {
        let package = try #require(parseCleanXcore("package org.example.shop").package)
        #expect(package.name == "shop")
        #expect(package.nsURI == "org.example.shop")
        #expect(package.nsPrefix == "shop")
        #expect(package.getEAnnotationDetail(source: AnnotationSource.genModel, key: XcoreLanguage.basePackageKey)
            == "org.example")
    }

    /// A simple package name has no base package, and an `xml` prefix is escaped.
    @Test func simplePackageDefaults() throws {
        let package = try #require(parseCleanXcore("package xmlTools").package)
        #expect(package.eAnnotations.isEmpty)
        #expect(package.nsURI == "xmlTools")
        #expect(package.nsPrefix == "_xmlTools")
    }

    /// `@Ecore` sets the namespace and is not kept as an annotation when nothing else remains.
    @Test func ecoreNamespace() throws {
        let package = try #require(parseCleanXcore("""
            @Ecore(nsURI="http://example.org/shop", nsPrefix="sh")
            @Ecore(constraints="valid")
            package shop
            """).package)
        #expect(package.nsURI == "http://example.org/shop")
        #expect(package.nsPrefix == "sh")
        #expect(package.eAnnotations.count == 1)
        #expect(package.eAnnotations.first?.details["constraints"] == "valid")
    }

    /// Annotations with predefined aliases merge per element; directives define other aliases.
    @Test func annotationsAndDirectives() throws {
        let result = parseCleanXcore("""
            @GenModel(prefix="Shop")
            @Notes(audience="staff")
            @GenModel(documentation="Shop model", prefix="Store")
            @xcore.lang.ExtendedMetaData(name="shop")
            package shop
            annotation "http://example.org/notes" as Notes
            annotation "Plain" as Plain
            @Plain class Item {}
            """)
        let annotations = try #require(result.package?.eAnnotations)
        #expect(annotations.map(\.source) == [
            AnnotationSource.genModel, "http://example.org/notes", AnnotationSource.extendedMetaData,
            XcoreLanguage.namespaceURI,
        ])
        #expect(Array(annotations[0].details.keys) == ["prefix", "documentation"])
        #expect(annotations[0].details["prefix"] == "Store")
        #expect(Array(annotations[3].details.keys) == ["Notes", "Plain"])
        #expect(result.eClass("Item")?.eAnnotations.first?.source == "Plain")
    }

    /// An annotation with an undeclared alias is reported.
    @Test func undeclaredAlias() {
        let result = XcoreReader.parse("package shop\n@Missing class Item {}")
        #expect(result.reports(.unresolvedAnnotation))
        #expect(result.errors.first?.range?.start.line == 2)
    }

    /// A block comment before an element becomes its GenModel documentation.
    @Test func documentationComments() throws {
        let result = parseCleanXcore("""
            package shop
            /*
             * An item for sale.
             *
             * Items have prices.
             */
            @GenModel(prefix="It")
            class Item {
                // not documentation
                /* The price. */
                int price
            }
            """)
        let item = try #require(result.eClass("Item"))
        #expect(item.eAnnotations.count == 1)
        #expect(item.eAnnotations.first?.details["documentation"] == "An item for sale.\n\nItems have prices.")
        #expect(item.eAnnotations.first?.details["prefix"] == "It")
        #expect(result.attribute("Item", "price")?.eAnnotations.first?.details["documentation"] == " The price.")
    }

    // MARK: Types

    /// Java names stand for the Ecore data types; Ecore names need an import.
    @Test func typeNames() throws {
        let result = parseCleanXcore("""
            package shop
            import org.eclipse.emf.ecore.EObject
            import org.eclipse.emf.ecore.*
            class Sample {
                String a  int b  Integer c  boolean d  Boolean e  long f  Long g  double h  Double i
                float j  Float k  char l  Character m  byte n  Byte o  short p  Short q  Date r
                BigDecimal s  BigInteger t  Object u  java.lang.String v  EByteArray w
                refers EObject x
                refers org.eclipse.emf.ecore.EClass y
            }
            """)
        let names = try #require(result.eClass("Sample")).eStructuralFeatures.map { feature in
            (feature as? EAttribute)?.eType.name ?? (feature as? EReference)?.eType.name ?? ""
        }
        #expect(names == [
            "EString", "EInt", "EIntegerObject", "EBoolean", "EBooleanObject", "ELong", "ELongObject", "EDouble",
            "EDoubleObject", "EFloat", "EFloatObject", "EChar", "ECharacterObject", "EByte", "EByteObject", "EShort",
            "EShortObject", "EDate", "EBigDecimal", "EBigInteger", "EJavaObject", "EString", "EByteArray", "EObject",
            "EClass",
        ])
    }

    /// An Ecore name without an import is an error.
    @Test func ecoreNameNeedsImport() {
        let result = XcoreReader.parse("package shop class Sample { refers EObject x }")
        #expect(result.reports(.unresolvedType))
        #expect(!result.warnings.contains { $0.code == XcoreDiagnosticCode.unresolvedType.rawValue })
    }

    /// A type that only an external import provides is a placeholder with a warning.
    @Test func externalImport() throws {
        let result = XcoreReader.parse("package shop import org.other.Customer class Order { refers Customer customer }")
        #expect(result.errors.isEmpty)
        #expect(result.warnings.contains { $0.code == XcoreDiagnosticCode.unresolvedType.rawValue })
        #expect(result.reference("Order", "customer")?.eType.name == "org.other.Customer")
        let written = XcoreWriter.write(result.packages)
        #expect(written.diagnostics.isEmpty)
        #expect(written.text.contains("import org.other.Customer"))
        let again = XcoreReader.parse(written.text)
        #expect(again.errors.isEmpty)
        #expect(again.reference("Order", "customer")?.eType.name == "org.other.Customer")
        let unqualified = EPackage(name: "p", eClassifiers: [
            EClass(name: "C", eStructuralFeatures: [EReference(name: "r", eType: EClass(name: "Elsewhere"))]),
        ])
        #expect(XcoreWriter.write([unqualified]).diagnostics.contains { $0.message.contains("'Elsewhere'") })
    }

    /// Classes in the same package can be named by their qualified name.
    @Test func qualifiedLocalNames() throws {
        let result = parseCleanXcore("package org.shop class Item {} class Order { refers org.shop.Item item }")
        #expect(result.reference("Order", "item")?.eType.id == result.eClass("Item")?.id)
    }

    // MARK: Classes

    /// Class kinds, supertypes, wrapped types and generics.
    @Test func classes() throws {
        let result = parseCleanXcore("""
            package shop
            abstract class Named {}
            interface Priced {}
            class Comparable<T> {}
            class Product extends Named, Priced, Comparable<Product> wraps org.example.Product {}
            class Entry wraps java.util.Map$Entry {}
            class Box<T extends Named & Priced, U> {
                refers T[] contents
                U label
                refers Comparable<? extends Named> loose
                refers Comparable<? super T> lower
                refers Comparable<?> any
            }
            """)
        #expect(result.eClass("Named")?.isAbstract == true)
        let priced = try #require(result.eClass("Priced"))
        #expect(priced.isInterface && priced.isAbstract)
        let product = try #require(result.eClass("Product"))
        #expect(product.eSuperTypes.map(\.name) == ["Named", "Priced", "Comparable"])
        #expect(product.eGenericSuperTypes.count == 3)
        #expect(product.instanceClassName == "org.example.Product")
        #expect(result.eClass("Entry")?.instanceClassName == "java.util.Map$Entry")
        let box = try #require(result.eClass("Box"))
        #expect(box.eTypeParameters.map(\.name) == ["T", "U"])
        #expect(box.eTypeParameters[0].eBounds.count == 2)
        #expect(result.reference("Box", "contents")?.eGenericType?.eTypeParameter == box.eTypeParameters[0].id)
        #expect(result.attribute("Box", "label")?.eType.name == "EJavaObject")
        #expect(result.reference("Box", "loose")?.eGenericType?.eTypeArguments.first?.eUpperBound != nil)
        #expect(result.reference("Box", "lower")?.eGenericType?.eTypeArguments.first?.eLowerBound != nil)
        #expect(result.reference("Box", "any")?.eGenericType?.eTypeArguments.first?.isWildcard == true)
    }

    /// `@Ecore` details that name attributes of an element set them.
    @Test func ecoreAttributes() throws {
        let result = parseCleanXcore("""
            package shop
            @Ecore(^abstract="false") interface Loose {}
            @Ecore(serializable="false", instanceTypeName="java.util.List<String>") type Listing wraps Object
            class Sample {
                @Ecore(^unique="false", resolveProxies="false") refers Sample[] others
                @Ecore(iD="true", lowerBound="2", upperBound="5", ordered="false") String code
                @Ecore(changeable="true", ^transient="false", defaultValueLiteral="x", name="renamed") String original
                @Ecore(unknown="kept") String other
            }
            """)
        #expect(result.eClass("Loose")?.isAbstract == false)
        let listing = try #require(result.package?.getEDataType("Listing"))
        #expect(!listing.serialisable)
        #expect(listing.instanceTypeName == "java.util.List<String>")
        #expect(listing.instanceClassName == "java.util.List")
        let others = try #require(result.reference("Sample", "others"))
        #expect(!others.unique && !others.resolveProxies)
        let code = try #require(result.attribute("Sample", "code"))
        #expect(code.isID && code.lowerBound == 2 && code.upperBound == 5 && !code.ordered)
        let renamed = try #require(result.attribute("Sample", "renamed"))
        #expect(renamed.defaultValueLiteral == "x")
        #expect(result.attribute("Sample", "other")?.eAnnotations.first?.details["unknown"] == "kept")
    }

    // MARK: Features

    /// Every multiplicity form gives the documented bounds.
    @Test(arguments: [
        ("", 0, 1), ("[?]", 0, 1), ("[]", 0, -1), ("[*]", 0, -1), ("[+]", 1, -1), ("[1]", 1, 1), ("[3]", 3, 3),
        ("[0..1]", 0, 1), ("[1..4]", 1, 4), ("[2..*]", 2, -1), ("[2..?]", 2, -2),
    ])
    func multiplicities(written: String, lower: Int, upper: Int) throws {
        let attribute = try #require(parseCleanXcore("package shop class Sample { String\(written) value }").attribute("Sample", "value"))
        #expect(attribute.lowerBound == lower)
        #expect(attribute.upperBound == upper)
    }

    /// Attribute modifiers and the Xcore default of non-unique attributes.
    @Test func attributeModifiers() throws {
        let result = parseCleanXcore("""
            package shop
            class Sample {
                String[] plain
                unordered unique readonly transient volatile unsettable derived id String[] all
                String text = "hello \\"world\\""
                int count = "3"
            }
            """)
        let plain = try #require(result.attribute("Sample", "plain"))
        #expect(!plain.unique && plain.ordered && plain.changeable)
        let all = try #require(result.attribute("Sample", "all"))
        #expect(all.unique && !all.ordered && !all.changeable && all.transient && all.volatile && all.unsettable)
        #expect(all.derived && all.isID)
        #expect(result.attribute("Sample", "text")?.defaultValueLiteral == "hello \"world\"")
        #expect(result.attribute("Sample", "count")?.defaultValueLiteral == "3")
    }

    /// Reference kinds set containment and proxy resolution as Xcore does.
    @Test func referenceKinds() throws {
        let result = parseCleanXcore("""
            package shop
            class Order {
                contains Line[] lines opposite order
                contains resolving Line[] resolved
                resolving contains Line[] alsoResolved
                refers Order next
                local refers Order previous
                refers local Order alsoLocal
                refers Line[] keyed keys code, name
            }
            class Line {
                container Order order opposite lines
                String code
                String name
            }
            """)
        let lines = try #require(result.reference("Order", "lines"))
        #expect(lines.containment && !lines.resolveProxies && lines.unique)
        #expect(result.reference("Order", "resolved")?.resolveProxies == true)
        #expect(result.reference("Order", "alsoResolved")?.resolveProxies == true)
        #expect(result.reference("Order", "next")?.resolveProxies == true)
        #expect(result.reference("Order", "previous")?.resolveProxies == false)
        #expect(result.reference("Order", "alsoLocal")?.resolveProxies == false)
        let order = try #require(result.reference("Line", "order"))
        #expect(order.container && !order.containment)
        #expect(order.opposite == lines.id)
        #expect(lines.opposite == order.id)
        let keyed = try #require(result.reference("Order", "keyed"))
        #expect(keyed.eKeys == [result.attribute("Line", "code")?.id, result.attribute("Line", "name")?.id].compactMap { $0 })
    }

    /// Unknown opposites and keys are reported at their names.
    @Test func unresolvedOppositeAndKeys() {
        let result = XcoreReader.parse("package shop\nclass Order { refers Order next opposite missing keys absent }")
        #expect(result.reports(.unresolvedOpposite))
        #expect(result.reports(.unresolvedKey))
        #expect(result.errors.allSatisfy { $0.range?.start.line == 2 })
    }

    /// A modifier that does not apply is reported.
    @Test func misplacedModifier() {
        let result = XcoreReader.parse("package shop class Order { id refers Order next local String name }")
        #expect(result.warnings.filter { $0.code == XcoreDiagnosticCode.unsupportedConstruct.rawValue }.count == 2)
    }

    // MARK: Bodies

    /// Feature accessors are kept verbatim and imply the derived flags.
    @Test func featureBodies() throws {
        let result = XcoreReader.parse("""
            package shop
            class Order {
                int total get { lines.size } set { } isSet { true } unset { }
                int count get {
                    if (true) { 1 } else { 2 }
                }
            }
            """)
        #expect(result.errors.isEmpty)
        #expect(result.warnings.filter { $0.code == XcoreDiagnosticCode.bodyNotExecuted.rawValue }.count == 5)
        let total = try #require(result.attribute("Order", "total"))
        #expect(body(total.eAnnotations, .get) == "{ lines.size }")
        #expect(body(total.eAnnotations, .set) == "{ }")
        #expect(body(total.eAnnotations, .isSet) == "{ true }")
        #expect(body(total.eAnnotations, .unset) == "{ }")
        #expect(total.transient && total.volatile && total.derived && total.changeable)
        let count = try #require(result.attribute("Order", "count"))
        #expect(!count.changeable)
        #expect(body(count.eAnnotations, .get) == "{\n        if (true) { 1 } else { 2 }\n    }")
    }

    /// Each warning about a body that is not executed names the kind of body in plain words.
    @Test func bodyWarningsNameTheKindOfBody() throws {
        let result = XcoreReader.parse("""
            package shop
            class Order {
                int total get { 1 } set { } isSet { true } unset { }
                op int twice() { 2 }
            }
            type Money wraps java.math.BigDecimal create { null } convert { null }
            """)
        let messages = result.warnings.filter { $0.code == XcoreDiagnosticCode.bodyNotExecuted.rawValue }.map(\.message)
        #expect(messages == [
            "The Xbase getter of the feature is kept as text but not executed",
            "The Xbase setter of the feature is kept as text but not executed",
            "The Xbase is-set body of the feature is kept as text but not executed",
            "The Xbase unset body of the feature is kept as text but not executed",
            "The Xbase body of the operation is kept as text but not executed",
            "The Xbase creation body of the data type is kept as text but not executed",
            "The Xbase conversion body of the data type is kept as text but not executed",
        ])
    }

    /// Operation bodies and data type bodies are kept verbatim; their lexical problems are ignored.
    @Test func operationAndDataTypeBodies() throws {
        let result = XcoreReader.parse("""
            package shop
            class Order {
                op String describe() { '''Order «name»''' + "}" + 0x1F#L }
            }
            type Money wraps java.math.BigDecimal create { new java.math.BigDecimal(it) } convert { it.toString }
            """)
        #expect(result.errors.isEmpty, "\(result.errors.map(\.message))")
        let describe = try #require(result.operation("Order", "describe"))
        #expect(body(describe.eAnnotations, .body)?.hasPrefix("{ '''Order") == true)
        #expect(body(describe.eAnnotations, .body)?.hasSuffix("0x1F#L }") == true)
        let money = try #require(result.package?.getEDataType("Money"))
        #expect(body(money.eAnnotations, .create) == "{ new java.math.BigDecimal(it) }")
        #expect(body(money.eAnnotations, .convert) == "{ it.toString }")
        #expect(money.serialisable)
    }

    // MARK: Operations

    /// Operations with modifiers, type parameters, multiplicities, parameters and exceptions.
    @Test func operations() throws {
        let result = parseCleanXcore("""
            package shop
            class Failure {}
            class Order {
                op void clear()
                op unordered unique String[1..*] notes(unique int[] indices, unordered String[] prefix) throws Failure
                op <T extends Order> T[] similar(T example, Class<T> kind)
                op int plain(int value)
            }
            """)
        #expect(result.operation("Order", "clear")?.eType == nil)
        let notes = try #require(result.operation("Order", "notes"))
        #expect(notes.unique && !notes.ordered && notes.lowerBound == 1 && notes.upperBound == -1)
        #expect(notes.eParameters[0].unique && notes.eParameters[0].ordered)
        #expect(!notes.eParameters[1].unique && !notes.eParameters[1].ordered)
        #expect(notes.eExceptions.map(\.name) == ["Failure"])
        let similar = try #require(result.operation("Order", "similar"))
        #expect(similar.eGenericType?.eTypeParameter == similar.eTypeParameters.first?.id)
        let plain = try #require(result.operation("Order", "plain"))
        #expect(!plain.unique && !plain.eParameters[0].unique)
    }

    // MARK: Data types and enumerations

    /// Data types wrap Java types, including arrays and generics.
    @Test func dataTypes() throws {
        let package = try #require(parseCleanXcore("""
            package shop
            type Money wraps java.math.BigDecimal
            type Blob wraps byte[]
            type Listing<T> wraps java.util.List<T>
            """).package)
        #expect(package.getEDataType("Money")?.instanceClassName == "java.math.BigDecimal")
        #expect(package.getEDataType("Blob")?.instanceClassName == "byte[]")
        let listing = try #require(package.getEDataType("Listing"))
        #expect(listing.eTypeParameters.map(\.name) == ["T"])
        #expect(listing.instanceTypeName == "java.util.List<T>")
    }

    /// Enumeration literals take values and literal texts; omitted values are zero, as in EMF.
    @Test func enumerations() throws {
        let size = try #require(parseCleanXcore("""
            package shop
            enum Size { small, medium = 1 large as "LARGE" = 10, huge as 'HUGE', negative = -1 }
            """).package?.getEEnum("Size"))
        #expect(size.literals.map(\.name) == ["small", "medium", "large", "huge", "negative"])
        #expect(size.literals.map(\.value) == [0, 1, 10, 0, -1])
        #expect(size.literals.map(\.literal) == ["small", "medium", "LARGE", "HUGE", "negative"])
    }

    // MARK: Names and diagnostics

    /// Keywords escaped with `^` are names; accessor keywords may be names unescaped.
    @Test func escapedKeywords() throws {
        let result = parseCleanXcore("package shop class ^class { String ^id String get refers ^class ^contains }")
        let eClass = try #require(result.eClass("class"))
        #expect(eClass.eStructuralFeatures.map(\.name) == ["id", "get", "contains"])
        #expect(XcoreReader.parse("package shop class Item { String type }").reports(.unexpectedToken))
    }

    /// The source name is attached to every diagnostic, and codes have the Xcore namespace.
    @Test func diagnosticsCarrySourceName() {
        let result = XcoreReader.parse("package shop class A { refers B b }", sourceName: "shop.xcore")
        #expect(!result.diagnostics.isEmpty)
        #expect(result.diagnostics.allSatisfy { $0.document == "shop.xcore" })
        for code in XcoreDiagnosticCode.allCases {
            #expect(code.rawValue.hasPrefix(XcoreLanguage.diagnosticNamespace + "."))
        }
    }

    /// The fixture reads with only the body warnings.
    @Test func libraryFixture() throws {
        let result = XcoreReader.parse(XcoreFixtures.library)
        #expect(result.diagnostics.allSatisfy { $0.code == XcoreDiagnosticCode.bodyNotExecuted.rawValue })
        #expect(result.diagnostics.count == 2)
        #expect(result.package?.eClassifiers.count == 13)
        #expect(result.reference("Member", "loans")?.eKeys.count == 1)
    }
}
