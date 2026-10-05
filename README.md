# Swift ECore

[![CI](https://github.com/mipalgu/swift-ecore/actions/workflows/ci.yml/badge.svg)](https://github.com/mipalgu/swift-ecore/actions/workflows/ci.yml)
[![Documentation](https://github.com/mipalgu/swift-ecore/actions/workflows/documentation.yml/badge.svg)](https://github.com/mipalgu/swift-ecore/actions/workflows/documentation.yml)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fmipalgu%2Fswift-ecore%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/mipalgu/swift-ecore)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fmipalgu%2Fswift-ecore%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/mipalgu/swift-ecore)

A pure Swift implementation of the Eclipse Modelling Framework (EMF) Ecore metamodel for macOS, Linux, and Windows.

## Features

- **Pure Swift**: No Java/EMF dependencies, Swift 6.2+ with strict concurrency
- **Cross-Platform**: Full support for macOS and Linux
- **Value Types**: Sendable structs and enums for thread safety
- **BigInt Support**: Full arbitrary-precision integer support via swift-numerics
- **Complete Metamodel**: EClass, EAttribute, EReference, EPackage, EEnum, EDataType
- **Resource Infrastructure**: EMF-compliant object management and ID-based reference resolution
- **JSON Serialisation**: Load and save JSON models with full round-trip support
- **Bidirectional References**: Automatic opposite reference management across resources
- **XMI Parsing**: Load .ecore metamodels and .xmi instance files
- **Dynamic Attribute Parsing**: Arbitrary XML attributes with automatic type inference (Int, Double, Bool, String)
- **XPath Reference Resolution**: Same-resource references with XPath-style navigation (//@feature.index)
- **XMI Serialisation**: Write models to XMI format with full round-trip support

## Requirements

- Swift 6.0 or later
- macOS 15.0+ or Linux (macOS 15.0+ required for SwiftXML dependency)

## Building

```bash
# Build the library
swift build

# Run tests
swift test
```

## Usage

The library implements the core of the Eclipse Modelling Framework and
can be included in other libraries, tools, and utilities (see the documentation).
For practical use, the `swift-ecore` command-line tool from the
[swift-modelling](https://github.com/mipalgu/swift-modelling) repository
provides comprehensive Eclipse Modelling Framework functionality for Swift.

## Implementation Status

### Core Types ✅

- [x] SPM package structure
- [x] Primitive type mappings (EString, EInt, EBoolean, EBigInt, etc.)
- [x] BigInt support via swift-numerics
- [x] Type conversion utilities
- [x] 100% test coverage for primitive types

### Metamodel Core ✅

- [x] EObject protocol
- [x] EModelElement (annotations)
- [x] ENamedElement
- [x] EClassifier hierarchy (EDataType, EEnum, EEnumLiteral)
- [x] EClass with structural features
- [x] EStructuralFeature (EAttribute and EReference with ID-based opposites)
- [x] EPackage and EFactory
- [x] Resource and ResourceSet infrastructure

### Reflective Ecore Metamodel ✅

- [x] `EcorePackage`: the Ecore metamodel as an `EPackage` (nsURI `http://www.eclipse.org/emf/2002/Ecore`)
- [x] Native metamodel objects report the real descriptor from `eClass`
- [x] `eGet`/`eSet` for the meta features (`eClassifiers`, `eStructuralFeatures`, `eAllSuperTypes`, `eType`, `eOpposite`, bounds, flags, ...)
- [x] Container features (`ePackage`, `eContainingClass`, `eEnum`, `eSuperPackage`) and `eContainer`, `eContainingFeature`, `eContents`, `eAllContents` navigation
- [x] `Resource.getAllInstancesOf` enumerates the contents of metamodels held by a resource
- [x] `XMISerializer.serialize(_:)` writes an `EPackage` (including `EcorePackage.instance`) as an `.ecore` document

```swift
let ecore = EcorePackage.instance
let attributeClass = EcorePackage.metaClass(.eAttribute)
let engine = ECoreExecutionEngine(models: [:])
await engine.registerResource(resource, alias: "MM")  // resource holding an EPackage
let classes = try await engine.navigate(from: package, property: "eClassifiers")
```

### Faithful `.ecore` Loading ✅

- [x] Multiple `eSuperTypes`, nested `eSubpackages`, `eOperations` with `eParameters`, `eType`, bounds, and `eExceptions`
- [x] Attribute and reference types resolve to the real `EEnum`, `EDataType`, or `EClass` (local, in nested packages, in other documents, or built into Ecore through `EcorePackage`)
- [x] Every feature flag (`transient`, `volatile`, `changeable`, `resolveProxies`, `unsettable`, `derived`, `ordered`, `unique`, `iD`), bounds, and `defaultValueLiteral`; `EReference.container`; `instanceClassName` of classes and data types; `serializable`
- [x] Native `EOperation` and `EParameter` values, reflective access, containment navigation, name-based fragments (`#//Class/op/param`), and serialisation
- [x] `eGenericType` children supply the type (the raw classifier); type arguments, type parameters, and bounds are not represented
- [x] Enumerations (`getAllInstancesOf`, `getAllObjectsIncludingContents`) are in document (containment) order and identical on every load

```swift
let package = try await EPackage(url: libraryURL)       // also resolves types in other documents
let book = package.getEClass("Book")
let borrow = book?.eOperations.first                    // EOperation with EParameter values
let supertypes = book?.eSuperTypes.map(\.name)          // every supertype, in order
```

### Annotations ✅

- [x] `eAnnotations` on every model element of a `.ecore` file: packages, classifiers, features, operations, parameters, enumeration literals, and annotations nested in annotations
- [x] `source`, `details` (key and value entries in document order, with multi-line values and XML entities preserved), `references` (same document and other documents), and `contents`
- [x] Loaded by `EPackage(url:)`, `ResourceSet.loadEcoreResource(uri:)`, and the dynamic loader (`loadXMIResource`), and navigable reflectively (`eAnnotations`, `source`, `details`, `key`, `value`, `references`, `contents`)
- [x] `getEAnnotation(source:)` and `getEAnnotationDetail(source:key:)` on every model element; the common sources and keys are listed in `AnnotationSource`
- [x] `XMISerializer.serialize(_:)` writes annotations back, escaping attribute values as EMF does

```swift
let package = try await EPackage(url: libraryURL)
let book = package.getEClass("Book")
let documentation = book?.getEAnnotationDetail(
    source: AnnotationSource.genModel, key: AnnotationSource.GenModelKey.documentation)
```

### Writing `.ecore` Documents ✅

- [x] References to classifiers of other documents are written with relative URIs and, as EMF does for abstract declared types, the kind of the classifier: `eSuperTypes="shared.ecore#//Audited"`, `eType="ecore:EEnum shared.ecore#//Colour"`
- [x] Classifiers of Ecore itself are written with the Ecore namespace URI (`ecore:EDataType http://www.eclipse.org/emf/2002/Ecore#//EString`); loaded built-ins have the identity of the classifiers of `EcorePackage.instance`
- [x] `XMISerializer.serialize(_:relativeTo:)` and `serialize(_:to:)` compute relative URIs for the target location
- [x] `XMISerializationOptions(lineWidth: XMISerializationOptions.emfLineWidth)` wraps long attribute lists as EMF's editors do, so documents such as `shared.ecore` and `consumer.ecore` round-trip byte for byte
- [x] `XMISerializationOptions.emfWrapped` is `.emf` with that line width. Documents written by different EMF releases wrap the root element differently; `XMIRootLayout.standard` (declarations follow `xmi:version`) and `.versionFirst` (declarations start on the next line) reproduce both, and `XMIRootLayout.detect(in:)` tells which one a document uses
- [x] Types and opposites that lie in documents that cannot be loaded are kept and written back unchanged
- [x] Enumeration-typed attributes of model instances are read by literal text (the literal name is the fallback) and written as literal text, as EMF does; unsettable attributes that are set to their default value are still written

### In-Memory Model ✅

- [x] Binary tree containment tests (BinTree model)
- [x] Company cross-reference tests
- [x] Shared reference tests
- [x] Multi-level containment hierarchy tests

### JSON Serialisation ✅

- [x] JSON parser for model instances
- [x] JSON serialiser with sorted keys
- [x] Round-trip tests for all data types
- [x] Comprehensive error handling

### XMI Serialisation ✅

- [x] SwiftXML dependency added
- [x] XMI parser foundation (Step 4.1)
- [x] XMI metamodel deserialisation (Step 4.2) - EPackage, EClass, EEnum, EDataType, EAttribute, EReference
- [x] XMI instance deserialisation (Step 4.3) - Dynamic object creation from instance files
- [x] Dynamic attribute parsing with type inference - Arbitrary XML attributes parsed without hardcoding
- [x] XPath reference resolution (Step 4.4) - Same-resource references with XPath-style navigation
- [x] XMI serialiser (Step 4.5) - Full serialisation with attributes, containment, and cross-references
- [x] Round-trip tests - XMI → memory → XMI with in-memory verification at each step
- [x] Cross-resource references (Step 4.6)
- [x] Cross-document reference attributes - `ecoreFeature="ecore:EAttribute library.ecore#//Book/title"`, space-separated lists, and `href` child elements, for references declared by a registered metamodel
- [x] Name-based Ecore fragments - `#/`, `#//Book`, `#//Book/title`, `#//sub/Class`, `#//Enum/Literal`, operations and parameters (`FragmentNavigator`, `XPathResolver`)
- [x] Proxy resolution - `Resource.resolveProxies()`, `ResourceSet.resolveAllProxies()` and `Resource.eGetResolving(objectId:feature:)` load target resources on demand
- [x] EMF-style serialisation - `XMISerializer(options: .emf)` writes attribute-style references, type qualifiers, relative URIs, name-based fragments, omits defaults, and writes many-valued attributes as child elements

#### Cross-document references

```swift
let resourceSet = ResourceSet()
let mapping = try await EPackage(url: mappingMetamodelURL)
await resourceSet.registerMetamodel(mapping, uri: mapping.nsURI)

// References to other documents are parsed as ResourceProxy values
let resource = try await resourceSet.loadXMIResource(uri: instanceURI)

// Load targets on demand and replace proxies by direct references
let report = await resourceSet.resolveAllProxies()

// Write the document the way EMF does
let text = try await XMISerializer(options: .emf).serialize(resource)
```

`.ecore` files reached through a proxy are loaded as the dynamic object graph the parser builds;
`ResourceSet.loadEcoreResource(uri:)` loads one as native `EPackage`, `EClass`, and related values
instead.

### Generic JSON Serialisation ✅

- [x] JSON parser for model instances (Step 5.1)
- [x] JSON serialiser with sorted keys (Step 5.2)
- [x] Dynamic EClass creation from JSON - Type inference for attributes and references
- [x] Boolean type handling fix - Boolean detection from Foundation's JSONSerialisation
- [x] Multiple root objects support - Arrays of JSON root objects
- [x] Cross-format conversion - XMI ↔ JSON bidirectional conversion
- [x] Round-trip tests for all data types
- [x] PyEcore compatibility validation - minimal.json and intfloat.json patterns
- [x] Comprehensive error handling

## GenModel

The `GenModel` library product provides the generator model (`.genmodel`) metamodel,
a loader, and a language-neutral facade for code generators.

- `GenModelPackage.load()` returns the bundled generator metamodel (`GenModel.ecore`),
  namespace `http://www.eclipse.org/emf/2002/GenModel`. It is authored for this package and is
  structurally compatible with the published generator metamodel (class, feature and enumeration
  names, multiplicities, containment, defaults), so `.genmodel` files interoperate in both directions.
- `GenModelResource.load(url:resourceSet:resolution:)` loads a `.genmodel`, registers the
  metamodel, and loads the source models named by `foreignModel` relative to the file. With
  `.nameFragments` the `ecore*` references are resolved through the resource set to the native Ecore
  elements; with `.deferred` they stay as the text of the document.
- `GenModelResource.save(_:to:rootLayout:)` writes a generator model in the layout of the Eclipse
  Modeling Framework, including its wrapping of long attribute lists at 80 columns
  (attribute-style references such as `ecoreClass="library.ecore#//Book"`). Generator elements are
  identified by the names of their Ecore elements (`Ecore.genmodel#//ecore`,
  `#//library/Book/title`), through `FragmentSegmentRule`s registered by `GenModelFragments`.
  `GenModelDocument.rootLayout` records how the loaded file wrapped its root element, so a
  document can be written back in the layout it was read in; `serialised(_:for:rootLayout:)`
  returns the text instead of writing a file. Source models that are not Ecore documents (for
  example `.mdl` or `.xsd` files) are not loaded.
- `GenModelContext` snapshots the loaded models, and `GenElement` offers navigation, inherited
  feature order, feature and classifier numbering, label features, feature shortcuts and
  name formatting (`capName`, `uncapName`, `upperName`). Nothing in the target depends on a
  target language; language knowledge belongs in templates.

```swift
let resourceSet = ResourceSet()
_ = try await GenModelResource.load(
    url: genModelURL, resourceSet: resourceSet, resolution: .nameFragments)
let context = await GenModelContext.snapshot(of: resourceSet)
for genClass in context.genModels[0].genPackages[0].genClasses {
    print(genClass.name, genClass.featureCount)
}
```

## Licence

See the details in the LICENCE file.

## Compatibility

Swift Modelling aims for 100% round-trip compatibility with:
- [emf4cpp](https://github.com/catedrasaes-umu/emf4cpp) - C++ EMF implementation
- [pyecore](https://github.com/pyecore/pyecore) - Python EMF implementation

## References

This implementation is based on the following standards and technologies:

- [Eclipse Modeling Framework (EMF)](https://eclipse.dev/emf/) - The reference EMF implementation
- [OMG MOF (Meta Object Facility)](https://www.omg.org/mof/) - The metamodelling standard
- [OMG XMI (XML Metadata Interchange)](https://www.omg.org/spec/XMI/) - The XML serialisation format
- [OMG OCL (Object Constraint Language)](https://www.omg.org/spec/OCL/) - The constraint and query language