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

### Native Ecore fidelity

Native Ecore documents retain type parameters, generic bounds and arguments, generic
supertypes and exceptions, reference keys, instance type names and enum data type flags.
Loading preserves all package roots in order. Save a single package with
`XMISerializer.serialize(_:)`, or pass `[EPackage]` to write a multi-root XMI document.
Comments, the XML encoding declaration and explicit `xmi:id` values follow model element
identity through edits and saving.

Editors can select `EcoreLoadOptions(unresolvedReferences: .keepAsProxies, tolerant: true)` when calling
`ResourceSet.loadEcoreResource(uri:options:)`
or `loadEcoreResource(text:uri:options:)`. Retained references keep their source spelling
when a target is unavailable. Missing required names and package attributes are reported in
`Resource.loadDiagnostics`; strict loading remains the default. `EcoreValidator` checks
keys, generic declaration names, scopes, bounds, arguments, inherited substitutions and
retained unresolved references. Each constraint can be disabled through validator options.

### Faithful `.ecore` Loading ✅

- [x] Multiple `eSuperTypes`, nested `eSubpackages`, `eOperations` with `eParameters`, `eType`, bounds, and `eExceptions`
- [x] Attribute and reference types resolve to the real `EEnum`, `EDataType`, or `EClass` (local, in nested packages, in other documents, or built into Ecore through `EcorePackage`)
- [x] Every feature flag (`transient`, `volatile`, `changeable`, `resolveProxies`, `unsettable`, `derived`, `ordered`, `unique`, `iD`), bounds, and `defaultValueLiteral`; `EReference.container`; `instanceClassName` of classes and data types; `serializable`
- [x] Native `EOperation` and `EParameter` values, reflective access, containment navigation, name-based fragments (`#//Class/op/param`), and serialisation
- [x] `eGenericType` children supply the type (the raw classifier); type arguments, type parameters, and bounds are not represented
- [x] Enumerations (`getAllInstancesOf`, `getAllObjectsIncludingContents`) are in document (containment) order and identical on every load
- [x] Nested packages: `EPackage(url:)` returns the root package with its `eSubpackages` attached, `allPackages` lists a package and every nested package depth first, and `getClassifier(_:includingSubpackages:)` searches them all
- [x] Registering a metamodel (`ResourceSet.registerMetamodel`, `loadEcoreResource`) also registers every nested package under its own `nsURI`, so instances whose objects are qualified by the namespace of a subpackage (`xmlns:kernel="http://example.org/root/kernel"`) get the classes of that subpackage; explicit registrations take precedence, and `getMetamodelURIs(includingSubpackages: true)` lists both
- [x] A class qualified by the namespace of an enclosing package (for example a subpackage class written as `root:Node`) is found in its nested packages

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
- [x] Metamodel-aware loading: with a `ResourceSet` that has the metamodel registered, `eClass`
  values (`"<nsURI>#//<Name>"` or a bare name) select the registered classes, attributes are
  converted by their data types, enumerations hold literal names, and `$ref` values
  (`//@authors.0`, `#/authors/0`, `other.json#//@authors.0`) resolve to objects or proxies
- [x] Metamodel-aware saving: package-qualified `eClass` values and `{"$ref": ...}` references
- [x] `JSONParseOptions.requiresMetamodel` turns an unknown class into an error instead of
  falling back to classes synthesised from the document
- [x] Nested objects take the class that their own `eClass` names (package-qualified, or a bare
  name looked up below the declared reference type first); the declared type is the fallback
- [x] Documents without a registered metamodel are read with classes synthesised from their keys,
  so that nested objects are registered with the resource and survive conversion to XMI
- [x] The container side of a containment is implied by nesting and not written
- [x] Documents written by earlier releases load, with or without a metamodel: unqualified
  `eClass` names, escaped slashes, inline nested objects, a single object or an array of roots,
  container-side `$ref` entries, and references written as bare identifiers (resolved through
  identifier attributes, otherwise kept and reported as `ConversionDiagnostics` warnings)
- [x] An empty resource is written as `[]` and read back as an empty resource
- [x] `JSONError` values describe themselves, naming the class or feature involved

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
- [x] `XMISerializationOptions.referenceStyle`: `.encoded` (the default) writes same-document
  references in attributes as `#//@entries.0`, `.plain` as `//@entries.0`; references into
  other documents and `href` elements keep their `#`
- [x] An empty resource is written as the `xmi:XMI` wrapper element alone, as EMF does, and read
  back as an empty resource
- [x] The legacy writer takes namespaces from the registered packages (or the metamodel snapshot of
  a released resource set); only classes of no known package get a namespace derived from their name
- [x] `ConversionDiagnostics`: `XMISerializer.serialize(_:diagnostics:)`,
  `JSONSerializer.serialize(_:diagnostics:)`, and the `diagnostics` of `XMIParser` and
  `JSONParser` report untyped classes, references without fragments, dropped values,
  unregistered contained objects, and unresolved references instead of losing them silently
- [x] Cross-document reference attributes - `ecoreFeature="ecore:EAttribute library.ecore#//Book/title"`, space-separated lists, and `href` child elements, for references declared by a registered metamodel
- [x] Name-based Ecore fragments - `#/`, `#//Book`, `#//Book/title`, `#//sub/Class`, `#//Enum/Literal`, operations and parameters (`FragmentNavigator`, `XPathResolver`)
- [x] Multi-root positional fragments - as in EMF, the only root of a resource is `#/` and its contents `#//@feature.index`, while root `n` of a resource with several roots is `#/n` and its contents `#/n/@feature.index` (`PositionalFragments`, `XPathResolver`); the container side of a containment is never written
- [x] Proxy resolution - `Resource.resolveProxies()`, `ResourceSet.resolveAllProxies()` and `Resource.eGetResolving(objectId:feature:)` load target resources on demand
- [x] Container lookup by identifier - `Resource.container(ofIdentifier:scope:)` and `ResourceSet.container(ofIdentifier:scope:)` find a container even when the contained object belongs to another resource, as do `Resource.eContainer(of:scope:)` and `eContainingFeature(of:scope:)` with the `.anyResource` scope of `ContainerLookupScope`; repeated lookups, including those of `eContainer(of:)` and `eContainingFeature(of:)`, are answered without rescanning the resource
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

### Model Formats and Loading ✅

- [x] `ModelFormat` (`.xmi`, `.json`, `.ecore`; the raw values are the file extensions) with
  `detect(url:)` by file extension, ignoring case, and `detect(data:)` and `detect(contentsOf:)`
  by the start of a document: `{` or `[` is JSON, an `EPackage` of the Ecore namespace (also
  inside an `xmi:XMI` wrapper) is Ecore, and any other XML is XMI
- [x] `ModelFormatError` describes a document whose format is unknown, listing the supported formats
- [x] `ModelIO.load(url:format:resourceSet:metamodels:options:)` registers the given metamodels
  (every root package, with its nested packages), detects the format unless it is given, and
  returns the resource, the format, the parser's `ConversionDiagnostics`, and the packages of an
  Ecore input, which is loaded natively and registered as a metamodel too
- [x] `ModelIO.LoadOptions` chooses how XMI references are read (`XMIReferenceParsing`) and whether
  JSON classes must come from a registered metamodel (by default, exactly when one is registered)
- [x] `ModelIO.save(_:to:format:xmiOptions:diagnostics:)` writes XMI with the given
  `XMISerializationOptions`, JSON, or an Ecore document for a resource of native packages, and
  `ModelIO.serialise(_:format:relativeTo:xmiOptions:diagnostics:)` returns the text instead

```swift
let resourceSet = ResourceSet()
let loaded = try await ModelIO.load(
    url: modelURL, resourceSet: resourceSet, metamodels: [metamodelURL])
var diagnostics = loaded.diagnostics
try await ModelIO.save(loaded.resource, to: jsonURL, diagnostics: &diagnostics)
for warning in diagnostics.warnings { print(warning) }
```

### Bundled Metamodels ✅

- [x] `EPackage.bundled(named:withExtension:subdirectory:in:bundleName:registeringIn:cache:)` loads
  an `.ecore` document that a target ships as a package resource, optionally registering it (with
  its nested packages) in a `ResourceSet`
- [x] `BundledMetamodelCache` loads each document once per location, so every caller gets the same
  package with the same element identifiers; `BundledMetamodelCache.shared` serves a whole program
- [x] `BundledResources` finds resources in `Bundle.module` or, where that bundle is not available
  (such as on WASI), in the `<package>_<target>.resources` directory (`ResourceBundleName`) beside
  the executable or in the current directory
  (on WASI the bundle is only evaluated when no bundle name is given)

```swift
let resourceSet = ResourceSet()
let package = try await EPackage.bundled(
    named: "Library", subdirectory: "Resources", in: .module,
    bundleName: ResourceBundleName(package: "swift-example", target: "Metamodels"),
    registeringIn: resourceSet)
```

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

## ECoreEdit

The `ECoreEdit` library product edits native metamodels (`EPackage` trees) as values, for
metamodel editors and diagram tools. It has no user interface and no dependency on Observation.

- `MetamodelDocument` holds the root packages and a `MetamodelIndex`. `apply(_:policy:)` applies a
  `MetamodelEdit` (`create`, `delete`, `move`, `set`, `setOpposite`, `setDetail`,
  `renameDetailKey`, `paste`, `compound`), refreshes the class snapshots by identifier, rebuilds the
  index, and returns a `MetamodelChangeSet` that lists what was added, removed, modified, and
  moved, which containers changed, and which labels may read differently. A refused edit throws a
  `MetamodelEditError` and leaves the document unchanged.
- Deleting elements cleans up every reference to them (supertypes, exceptions, opposites, annotation
  references). A feature whose type was deleted gets the Ecore built-in `EObject` (reference) or
  `EJavaObject` (attribute); an operation whose type was deleted has no type.
- `childDescriptors(for:)`, `siblingDescriptors(for:)`, `propertyDescriptors(for:)`, and
  `choices(for:feature:)` are derived reflectively from `EcorePackage`.
- `EcoreLabelProvider` gives labels, icons, and multiplicity decorations in the layout of the
  Eclipse Sample Ecore Editor; separators are defined once in `EcoreLabelSyntax`.
- `EditHistory` is a generic undo and redo history with a saved point, and
  `MetamodelEditingDomain` (main actor) combines a document with a history, closure observers, an
  `AsyncStream` of change sets, and an `EMFCommand` adapter for `CommandStack`.
- `EcoreClipboard` carries copied elements to any compatible container, in any document.

```swift
let domain = MetamodelEditingDomain(document: MetamodelDocument(roots: [package]))
let token = domain.observe { changes in refresh(changes.labelsAffected) }
try domain.perform(.set(classID, .name, "Book"))
domain.undo()
```

## Licence

See the details in the LICENCE file.

## Compatibility

Swift Modelling aims for 100% round-trip compatibility with:
- [emf4cpp](https://github.com/catedrasaes-umu/emf4cpp) - C++ EMF implementation
- [pyecore](https://github.com/pyecore/pyecore) - Python EMF implementation

### Compatibility with 0.6

Every API of version 0.6 is still available and behaves as it did in 0.6. Newer behaviour is
offered through additional API, whose default is the new behaviour:

- Container lookup for an object that belongs to another resource, or that has been removed
  from the resource of its container
  - New default: the container is found by `Resource.container(ofIdentifier:scope:)`,
    `ResourceSet.container(ofIdentifier:scope:)` (which follow a configured scope, else answer
    for any resource), and with `ContainerLookupScope()` or
    `ContainerLookupScope.standard` (`.anyResource`)
  - Option: the `scope:` argument of `Resource.eContainer(of:scope:)` and
    `Resource.eContainingFeature(of:scope:)`, or a scope configured for a resource with
    `Resource.setContainerLookupScope(_:)` or for every resource of a set with
    `ResourceSet.setDefaultContainerLookupScope(_:)` or
    `ResourceSet(defaultContainerLookupScope:)`; a resource's own scope takes precedence over
    the default of its set
  - 0.6 behaviour: `eContainer(of:)` and `eContainingFeature(of:)` without a scope, as before,
    while no scope is configured (`ContainerLookupScope.builtInDefault`), or
    `scope: .thisResource` (`ContainerLookupScope.legacy`); an object held by identifier is
    answered only while the resource can resolve it, and an object embedded as a value always is
- Choosing the semantics: `ModellingSemantics` (`.standard` or `.legacy`) names the two sets of
  behaviours of all the modelling languages, `ModellingSemantics.fromEnvironment()` reads a
  choice from the `SWIFT_MODELLING_SEMANTICS` environment variable, and
  `ContainerLookupScope(semantics:)` selects the matching scope

`EcoreValueArray` now records an `EcoreCollectionKind`. Arrays created with
`EcoreValueArray(_:)` are sequences, as before, and the kind takes no part in equality, hashing
or the textual form of an array.

## References

This implementation is based on the following standards and technologies:

- [Eclipse Modeling Framework (EMF)](https://eclipse.dev/emf/) - The reference EMF implementation
- [OMG MOF (Meta Object Facility)](https://www.omg.org/mof/) - The metamodelling standard
- [OMG XMI (XML Metadata Interchange)](https://www.omg.org/spec/XMI/) - The XML serialisation format
- [OMG OCL (Object Constraint Language)](https://www.omg.org/spec/OCL/) - The constraint and query language