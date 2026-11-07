//
// EmfaticReaderTests.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Testing

@testable import ECore

/// Tests that each Emfatic construct is read into the expected native Ecore element.
@Suite("Emfatic reader")
struct EmfaticReaderTests {
    // MARK: Packages

    /// The package declaration and `@namespace` set the name, URI and prefix.
    @Test func packageWithNamespace() throws {
        let result = parseCleanEmfatic("@namespace(uri=\"http://example.org/shop\", prefix=\"shop\")\npackage shop;")
        let package = try #require(result.package)
        #expect(package.name == "shop")
        #expect(package.nsURI == "http://example.org/shop")
        #expect(package.nsPrefix == "shop")
        #expect(package.eAnnotations.isEmpty)
    }

    /// Without `@namespace` the URI is the package name and the prefix is empty, as in Emfatic.
    @Test func packageDefaults() throws {
        let package = try #require(parseCleanEmfatic("package shop;").package)
        #expect(package.nsURI == "shop")
        #expect(package.nsPrefix == "")
    }

    /// A qualified package name is kept as one name.
    @Test func qualifiedPackageName() throws {
        let package = try #require(parseCleanEmfatic("package org.example.shop;").package)
        #expect(package.name == "org.example.shop")
    }

    /// The label and keys of `@namespace` are matched without regard to case.
    @Test func namespaceIsCaseInsensitive() throws {
        let package = try #require(parseCleanEmfatic("@NameSpace(URI=\"urn:a\", Prefix=\"a\") package a;").package)
        #expect(package.nsURI == "urn:a")
        #expect(package.nsPrefix == "a")
    }

    /// Unknown keys of `@namespace` are reported and ignored.
    @Test func namespaceUnknownKey() {
        let result = EmfaticReader.parse("@namespace(uri=\"urn:a\", colour=\"red\") package a;")
        #expect(result.reports(.unsupportedConstruct))
        #expect(result.errors.isEmpty)
    }

    /// Nested packages become subpackages with their own namespace.
    @Test func subpackages() throws {
        let result = parseCleanEmfatic("""
            package shop;
            class Order { ref stock.Item[*] items; }
            @namespace(uri="urn:stock", prefix="st")
            package stock {
                class Item { ref Order order; }
                package detail { class Part { ref Item item; ref Order order; } }
            }
            """)
        let package = try #require(result.package)
        let stock = try #require(package.getSubpackage("stock"))
        #expect(stock.nsURI == "urn:stock")
        #expect(stock.nsPrefix == "st")
        let detail = try #require(stock.getSubpackage("detail"))
        #expect(detail.nsURI == "detail")
        let part = try #require(detail.getEClass("Part"))
        #expect(part.eStructuralFeatures.map { $0.name } == ["item", "order"])
        let items = try #require(result.reference("Order", "items"))
        #expect(items.eType.id == stock.getEClass("Item")?.id)
        let partItem = try #require(part.eStructuralFeatures.first as? EReference)
        #expect(partItem.eType.id == stock.getEClass("Item")?.id)
    }

    /// Imports are accepted; an unknown type is then a placeholder with a warning.
    @Test func importsMakeUnknownTypesWarnings() throws {
        let result = EmfaticReader.parse("""
            package shop;
            import "platform:/resource/other/model/other.ecore";
            import other.model;
            class Order { ref other.Customer customer; }
            """)
        #expect(result.errors.isEmpty)
        #expect(result.reports(.unresolvedType))
        #expect(result.reports(.unsupportedConstruct))
        let customer = try #require(result.reference("Order", "customer"))
        #expect(customer.eType.name == "other.Customer")
        let written = EmfaticWriter.write(result.packages)
        #expect(written.diagnostics.contains { $0.message.contains("'other.Customer' is not declared") })
        #expect(written.text.contains("ref other.Customer customer;"))
    }

    /// Without imports an unknown type is an error with its position.
    @Test func unresolvedTypeIsError() throws {
        let result = EmfaticReader.parse("package shop;\nclass Order { ref Customer customer; }")
        let error = try #require(result.errors.first)
        #expect(error.code == EmfaticDiagnosticCode.unresolvedType.rawValue)
        #expect(error.range?.start.line == 2)
        #expect(error.range?.start.column == 19)
        #expect(result.reference("Order", "customer")?.eType is EClass)
    }

    // MARK: Annotations

    /// Predefined labels map to their source URIs and details keep their order.
    @Test func annotations() throws {
        let result = parseCleanEmfatic("""
            @GenModel(documentation="Shop model", prefix="Shop")
            @ecore(constraints="valid")
            @ExtendedMetaData(name="shop")
            @"http://example.org/notes"(note="first", "key with space"="second")
            @gmf.node(label=name)
            @simple
            @EmfaticAnnotationMap(sticky="http://example.org/sticky")
            @Sticky(colour="yellow")
            package shop;
            """)
        let annotations = try #require(result.package?.eAnnotations)
        #expect(annotations.map(\.source) == [
            AnnotationSource.genModel, AnnotationSource.ecore, AnnotationSource.extendedMetaData,
            "http://example.org/notes", "gmf.node", "simple", EmfaticLanguage.annotationMapSource,
            "http://example.org/sticky",
        ])
        #expect(Array(annotations[0].details.keys) == ["documentation", "prefix"])
        #expect(annotations[3].details["key with space"] == "second")
        #expect(annotations[4].details["label"] == "name")
        #expect(annotations[5].details.isEmpty)
        #expect(annotations[7].details["colour"] == "yellow")
    }

    /// Annotation values keep escapes as written, apart from an escaped quote.
    @Test func annotationEscapes() throws {
        let result = parseCleanEmfatic(#"@GenModel(documentation="Say \"hi\"\nnow") package shop;"#)
        #expect(result.package?.eAnnotations.first?.details["documentation"] == #"Say "hi"\nnow"#)
    }

    /// A value without a key gets an implicit key, declared or `value`.
    @Test func implicitAnnotationKeys() throws {
        let result = EmfaticReader.parse("""
            @EmfaticAnnotationMap("pin(colour, size)"="urn:pin")
            @pin("red", "large", "extra")
            @other("lonely")
            package shop;
            """)
        let annotations = try #require(result.package?.eAnnotations)
        #expect(annotations[1].source == "urn:pin")
        #expect(annotations[1].details["colour"] == "red")
        #expect(annotations[1].details["size"] == "large")
        #expect(annotations[1].details["value"] == "extra")
        #expect(annotations[2].details["value"] == "lonely")
        #expect(result.warnings.count == 2)
    }

    /// Annotations attach to classes, features, operations, parameters and literals.
    @Test func annotationTargets() throws {
        let result = parseCleanEmfatic("""
            package shop;
            @GenModel(documentation="An order")
            class Order {
                @GenModel(documentation="The total")
                attr int total;
                @GenModel(body="return 0;")
                op int count(@GenModel(documentation="before") int limit @GenModel(documentation="after"));
            }
            enum Status { @GenModel(documentation="open") open = 0 @Ecore(x="y"); }
            """)
        #expect(result.eClass("Order")?.eAnnotations.first?.details["documentation"] == "An order")
        #expect(result.attribute("Order", "total")?.eAnnotations.count == 1)
        let operation = try #require(result.operation("Order", "count"))
        #expect(operation.eAnnotations.first?.details["body"] == "return 0;")
        #expect(operation.eParameters.first?.eAnnotations.count == 2)
        let status = try #require(result.package?.getEEnum("Status"))
        #expect(status.literals.first?.eAnnotations.count == 2)
    }

    // MARK: Classes

    /// Class kinds, supertypes and instance class names.
    @Test func classes() throws {
        let result = parseCleanEmfatic("""
            package shop;
            abstract class Named {}
            interface Priced {}
            abstract interface Taxed {}
            class Product extends Named, Priced : org.example.Product {}
            class Entry : java.util.Map$Entry {}
            class Raw : "int[]" {}
            """)
        #expect(result.eClass("Named")?.isAbstract == true)
        #expect(result.eClass("Priced")?.isInterface == true)
        #expect(result.eClass("Priced")?.isAbstract == false)
        #expect(result.eClass("Taxed")?.isInterface == true)
        #expect(result.eClass("Taxed")?.isAbstract == true)
        let product = try #require(result.eClass("Product"))
        #expect(product.eSuperTypes.map(\.name) == ["Named", "Priced"])
        #expect(product.instanceClassName == "org.example.Product")
        #expect(result.eClass("Entry")?.instanceClassName == "java.util.Map$Entry")
        #expect(result.eClass("Raw")?.instanceClassName == "int[]")
    }

    /// Type parameters, bounds and generic supertypes.
    @Test func generics() throws {
        let result = parseCleanEmfatic("""
            package shop;
            class Named {}
            class Comparable<T> {}
            class Box<T extends Named & Comparable<T>, U> extends Comparable<Box<T, U>> {
                ref T[*] contents;
                attr U label;
                ref Comparable<? extends Named> loose;
                ref Comparable<? super T> lower;
                ref Comparable<?> any;
            }
            """)
        let box = try #require(result.eClass("Box"))
        #expect(box.eTypeParameters.map(\.name) == ["T", "U"])
        #expect(box.eTypeParameters[0].eBounds.count == 2)
        #expect(box.eGenericSuperTypes.first?.eTypeArguments.first?.eTypeArguments.count == 2)
        #expect(box.eSuperTypes.first?.name == "Comparable")
        let contents = try #require(result.reference("Box", "contents"))
        #expect(contents.eGenericType?.eTypeParameter == box.eTypeParameters[0].id)
        #expect(contents.eType.name == "Named")
        let label = try #require(result.attribute("Box", "label"))
        #expect(label.eType.name == EcoreDataType.eJavaObject.rawValue)
        let loose = try #require(result.reference("Box", "loose"))
        #expect(loose.eGenericType?.eTypeArguments.first?.eUpperBound?.eClassifier?.name == "Named")
        let lower = try #require(result.reference("Box", "lower"))
        #expect(lower.eGenericType?.eTypeArguments.first?.eLowerBound?.eTypeParameter == box.eTypeParameters[0].id)
        let any = try #require(result.reference("Box", "any"))
        #expect(any.eGenericType?.eTypeArguments.first?.isWildcard == true)
    }

    /// A supertype that is not a class is reported.
    @Test func dataTypeSupertypeIsError() {
        let result = EmfaticReader.parse("package shop; datatype Money : java.math.BigDecimal; class Price extends Money {}")
        #expect(result.reports(.unresolvedType))
    }

    // MARK: Features

    /// Attribute types use basic type names, Ecore names and the `ecore.` prefix.
    @Test func builtinTypes() throws {
        let result = parseCleanEmfatic("""
            package shop;
            class Sample {
                attr String a; attr boolean b; attr Boolean c; attr int d; attr Integer e; attr long f;
                attr double g; attr float h; attr char i; attr byte j; attr short k; attr Date l;
                attr Object m; attr Class n; attr EString o; attr EBigDecimal p; attr ecore.EByteArray q;
                ref EObject r; ref EClass s; ref ecore.EOperation t;
            }
            """)
        let names = try #require(result.eClass("Sample")).eStructuralFeatures.compactMap { feature -> String? in
            (feature as? EAttribute)?.eType.name ?? (feature as? EReference)?.eType.name
        }
        #expect(names == [
            "EString", "EBoolean", "EBooleanObject", "EInt", "EIntegerObject", "ELong", "EDouble", "EFloat", "EChar",
            "EByte", "EShort", "EDate", "EJavaObject", "EJavaClass", "EString", "EBigDecimal", "EByteArray",
            "EObject", "EClass", "EOperation",
        ])
        let string = try #require(result.attribute("Sample", "a"))
        #expect(string.eType.id == EcorePackage.dataType(.eString)?.id)
    }

    /// A declared classifier hides a basic type name of the same name.
    @Test func localClassifierHidesBasicType() throws {
        let result = parseCleanEmfatic("package shop; class Date {} class Order { ref Date placed; }")
        #expect(result.reference("Order", "placed")?.eType.id == result.eClass("Date")?.id)
    }

    /// Every multiplicity form gives the documented bounds.
    @Test(arguments: [
        ("", 0, 1), ("[?]", 0, 1), ("[]", 0, -1), ("[*]", 0, -1), ("[+]", 1, -1), ("[1]", 1, 1), ("[3]", 3, 3),
        ("[0..1]", 0, 1), ("[1..4]", 1, 4), ("[2..*]", 2, -1), ("[2..+]", 2, -1), ("[2..?]", 2, -2),
    ])
    func multiplicities(written: String, lower: Int, upper: Int) throws {
        let result = parseCleanEmfatic("package shop; class Sample { attr String\(written) value; }")
        let attribute = try #require(result.attribute("Sample", "value"))
        #expect(attribute.lowerBound == lower)
        #expect(attribute.upperBound == upper)
    }

    /// Modifiers and their negations set the feature flags.
    @Test func modifiers() throws {
        let result = parseCleanEmfatic("""
            package shop;
            class Sample {
                readonly volatile transient unsettable derived !unique !ordered id attr String[*] code;
                !resolve ref Sample other;
                unique ordered resolve ref Sample[*] plain;
            }
            """)
        let code = try #require(result.attribute("Sample", "code"))
        #expect(!code.changeable && code.volatile && code.transient && code.unsettable && code.derived)
        #expect(!code.unique && !code.ordered && code.isID)
        #expect(result.reference("Sample", "other")?.resolveProxies == false)
        let plain = try #require(result.reference("Sample", "plain"))
        #expect(plain.unique && plain.ordered && plain.resolveProxies)
    }

    /// A modifier that does not apply to a kind of element is reported and ignored.
    @Test func misplacedModifiers() throws {
        let result = EmfaticReader.parse("""
            package shop;
            class Sample { resolve attr String a; id ref Sample b; readonly op void c(transient int d); }
            """)
        #expect(result.errors.isEmpty)
        #expect(result.warnings.filter { $0.code == EmfaticDiagnosticCode.unsupportedConstruct.rawValue }.count == 4)
    }

    /// Default values of every literal kind are kept as text.
    @Test func defaultValues() throws {
        let result = parseCleanEmfatic("""
            package shop;
            class Sample {
                attr boolean a = true; attr int b = -42; attr int c = 7; attr String d = "text";
                attr char e = 'x'; attr String f = some.Name; attr String g = "say \\"hi\\"";
            }
            """)
        #expect(result.attribute("Sample", "a")?.defaultValueLiteral == "true")
        #expect(result.attribute("Sample", "b")?.defaultValueLiteral == "-42")
        #expect(result.attribute("Sample", "c")?.defaultValueLiteral == "7")
        #expect(result.attribute("Sample", "d")?.defaultValueLiteral == "text")
        #expect(result.attribute("Sample", "e")?.defaultValueLiteral == "x")
        #expect(result.attribute("Sample", "f")?.defaultValueLiteral == "some.Name")
        #expect(result.attribute("Sample", "g")?.defaultValueLiteral == #"say "hi""#)
    }

    /// `val` is containment, `#` names the opposite, and the container side is derived.
    @Test func referencesAndOpposites() throws {
        let result = parseCleanEmfatic("""
            package shop;
            class Order { val Line[*]#order lines; ref Customer#orders customer; }
            class Line { ref Order#lines order; }
            class Customer { ref Order[*]#customer orders; }
            """)
        let lines = try #require(result.reference("Order", "lines"))
        let order = try #require(result.reference("Line", "order"))
        #expect(lines.containment)
        #expect(lines.opposite == order.id)
        #expect(order.opposite == lines.id)
        #expect(order.container)
        #expect(!lines.container)
        #expect(result.reference("Customer", "orders")?.opposite == result.reference("Order", "customer")?.id)
    }

    /// An opposite inherited from a supertype is found.
    @Test func inheritedOpposite() throws {
        let result = parseCleanEmfatic("""
            package shop;
            abstract class Owned { ref Owner#owned owner; }
            class Thing extends Owned {}
            class Owner { ref Thing[*]#owner owned; }
            """)
        #expect(result.reference("Owner", "owned")?.opposite == result.reference("Owned", "owner")?.id)
    }

    /// An opposite that does not exist is reported at its name.
    @Test func unresolvedOpposite() throws {
        let result = EmfaticReader.parse("package shop;\nclass Order { ref Order#missing next; }")
        let error = try #require(result.errors.first)
        #expect(error.code == EmfaticDiagnosticCode.unresolvedOpposite.rawValue)
        #expect(error.range?.start.line == 2)
        #expect(error.range?.start.column == 25)
    }

    // MARK: Operations

    /// Operations with void results, multiplicities, parameters, exceptions and type parameters.
    @Test func operations() throws {
        let result = parseCleanEmfatic("""
            package shop;
            class Failure {}
            class Order {
                op void clear();
                !unique !ordered op String[1..*] notes(!ordered int[*] indices, String[?] prefix) throws Failure, Failure;
                op <T extends Order> T[*] similar(T example, Class<T> kind);
            }
            """)
        let clear = try #require(result.operation("Order", "clear"))
        #expect(clear.eType == nil)
        let notes = try #require(result.operation("Order", "notes"))
        #expect(notes.eType?.name == "EString")
        #expect(notes.lowerBound == 1 && notes.upperBound == -1)
        #expect(!notes.unique && !notes.ordered)
        #expect(notes.eParameters.map(\.name) == ["indices", "prefix"])
        #expect(notes.eParameters[0].upperBound == -1 && !notes.eParameters[0].ordered)
        #expect(notes.eExceptions.map(\.name) == ["Failure", "Failure"])
        let similar = try #require(result.operation("Order", "similar"))
        #expect(similar.eTypeParameters.map(\.name) == ["T"])
        #expect(similar.eGenericType?.eTypeParameter == similar.eTypeParameters[0].id)
        #expect(similar.eType?.name == "Order")
        #expect(similar.eParameters[1].eGenericType?.eTypeArguments.first?.eTypeParameter == similar.eTypeParameters[0].id)
    }

    /// Duplicate parameter names are reported.
    @Test func duplicateParameters() {
        let result = EmfaticReader.parse("package shop; class Order { op void f(int a, int a); }")
        #expect(result.reports(.duplicateName))
    }

    // MARK: Data types, enumerations and map entries

    /// Data types with instance class names, quoted names and `transient`.
    @Test func dataTypes() throws {
        let result = parseCleanEmfatic("""
            package shop;
            datatype Money : java.math.BigDecimal;
            transient datatype Blob : "byte[]";
            datatype Listing : java.util.List<java.lang.String>;
            """)
        let package = try #require(result.package)
        #expect(package.getEDataType("Money")?.instanceClassName == "java.math.BigDecimal")
        #expect(package.getEDataType("Money")?.serialisable == true)
        #expect(package.getEDataType("Blob")?.instanceClassName == "byte[]")
        #expect(package.getEDataType("Blob")?.serialisable == false)
        #expect(package.getEDataType("Listing")?.instanceClassName == "java.util.List")
        #expect(package.getEDataType("Listing")?.instanceTypeName == "java.util.List<java.lang.String>")
    }

    /// Enumeration values count on from the previous literal.
    @Test func enumerations() throws {
        let result = parseCleanEmfatic("package shop; enum Size { small; medium; large = 10; huge; }")
        let size = try #require(result.package?.getEEnum("Size"))
        #expect(size.literals.map(\.name) == ["small", "medium", "large", "huge"])
        #expect(size.literals.map(\.value) == [0, 1, 10, 11])
        #expect(size.literals.map(\.literal) == ["small", "medium", "large", "huge"])
    }

    /// A map entry becomes a class with key and value features.
    @Test func mapEntries() throws {
        let result = parseCleanEmfatic("""
            package shop;
            class Item {}
            mapentry Stock : String -> Item[*];
            mapentry Counts : String[1] -> int;
            """)
        let stock = try #require(result.eClass("Stock"))
        #expect(stock.instanceClassName == EmfaticLanguage.mapEntryInstanceClassName)
        #expect(stock.eStructuralFeatures.map(\.name) == ["key", "value"])
        #expect(stock.eStructuralFeatures[0] is EAttribute)
        let value = try #require(stock.eStructuralFeatures[1] as? EReference)
        #expect(value.upperBound == -1)
        let counts = try #require(result.eClass("Counts"))
        #expect(counts.eStructuralFeatures.allSatisfy { $0 is EAttribute })
        #expect((counts.eStructuralFeatures[0] as? EAttribute)?.lowerBound == 1)
    }

    // MARK: Names

    /// Keywords escaped with `~` are names, and unescaped keywords as names are errors.
    @Test func escapedKeywords() throws {
        let result = parseCleanEmfatic("package shop; class ~class { attr String ~id; ref ~class ~ref; }")
        let eClass = try #require(result.eClass("class"))
        #expect(eClass.eStructuralFeatures.map(\.name) == ["id", "ref"])
        let bad = EmfaticReader.parse("package shop; class Item { attr String package; }")
        #expect(bad.reports(.unexpectedToken))
        #expect(bad.attribute("Item", "package") != nil)
    }

    /// Duplicate classifiers and features are reported and the duplicate is skipped.
    @Test func duplicates() throws {
        let result = EmfaticReader.parse("package shop; class A { attr int x; attr int x; } class A {} enum E { a; a; }")
        #expect(result.errors.filter { $0.code == EmfaticDiagnosticCode.duplicateName.rawValue }.count == 3)
        #expect(result.package?.eClassifiers.count == 2)
        #expect(result.eClass("A")?.eStructuralFeatures.count == 1)
    }

    /// The source name is attached to every diagnostic.
    @Test func sourceName() {
        let result = EmfaticReader.parse("package shop; class A { ref B b; }", sourceName: "shop.emf")
        #expect(result.diagnostics.allSatisfy { $0.document == "shop.emf" })
        #expect(!result.diagnostics.isEmpty)
    }

    /// Every diagnostic code has the Emfatic namespace.
    @Test func diagnosticCodes() {
        for code in EmfaticDiagnosticCode.allCases {
            #expect(code.rawValue.hasPrefix(EmfaticLanguage.diagnosticNamespace + "."))
        }
    }

    /// The fixture reads without errors and resolves every reference.
    @Test func libraryFixture() throws {
        let result = parseCleanEmfatic(EmfaticFixtures.library)
        #expect(result.diagnostics.isEmpty)
        let package = try #require(result.package)
        #expect(package.eClassifiers.count == 13)
        #expect(package.eSubpackages.count == 1)
        #expect(result.reference("Book", "authors")?.opposite == result.reference("Author", "books")?.id)
    }
}
