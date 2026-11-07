# Getting Started with ECore

Learn how to add ECore to your project and create your first metamodel.

## Overview

This guide walks you through adding ECore to your Swift project and demonstrates
the fundamental concepts of metamodelling with ECore.

## Adding ECore to Your Project

Add swift-ecore as a dependency in your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/mipalgu/swift-ecore.git", branch: "main"),
]
```

Then add the product dependency to your target:

```swift
.target(
    name: "MyApp",
    dependencies: [
        .product(name: "ECore", package: "swift-ecore"),
    ]
)
```

## Loading a Metamodel

ECore metamodels are typically stored in `.ecore` files using XMI format. Load a metamodel
with ``EPackage/init(url:enableDebugging:)`` and register it with a ``ResourceSet``, so that
models of the metamodel can be read and written:

```swift
import ECore
import Foundation

let package = try await EPackage(url: URL(fileURLWithPath: "Company.ecore"))
let resourceSet = ResourceSet()
await resourceSet.registerMetamodel(package, uri: package.nsURI)

print("Loaded package: \(package.name)")
```

## Exploring a Metamodel

Once loaded, explore the metamodel structure:

```swift
// List all classifiers (EClass, EDataType, EEnum)
for classifier in package.eClassifiers {
    print("Classifier: \(classifier.name)")

    if let eClass = classifier as? EClass {
        // List structural features
        for feature in eClass.eStructuralFeatures {
            if let attr = feature as? EAttribute {
                print("  Attribute: \(attr.name) : \(attr.eType.name)")
            } else if let ref = feature as? EReference {
                print("  Reference: \(ref.name) -> \(ref.eType.name)")
            }
        }
    }
}
```

## Creating Model Instances

Create dynamic instances of metamodel classes using ``DynamicEObject``. Instances are values,
so declare them with `var` to set their features:

```swift
// Find the Employee class
guard let employeeClass = package.getEClass("Employee") else {
    fatalError("Employee class not found")
}

// Create an instance
var employee = DynamicEObject(eClass: employeeClass)

// Set attribute values
employee.eSet("name", value: "Alice Smith")
employee.eSet("employeeId", value: 12345)
employee.eSet("department", value: "Engineering")

// Read values back
let name = employee.eGet("name") as? String
print("Employee name: \(name ?? "unknown")")
```

## Working with References

ECore supports both single-valued and multi-valued references. An object refers to others by
their identifiers, which resolve once the objects belong to a ``Resource``:

```swift
// Create a company and employees
guard let companyClass = package.getEClass("Company") else {
    fatalError("Company class not found")
}
var company = DynamicEObject(eClass: companyClass)
company.eSet("name", value: "Acme Corp")

var alice = DynamicEObject(eClass: employeeClass)
alice.eSet("name", value: "Alice")

var bob = DynamicEObject(eClass: employeeClass)
bob.eSet("name", value: "Bob")

// Set the employees (assuming 'employees' is a multi-valued containment reference)
company.eSet("employees", value: [alice.id, bob.id])
```

## Saving Models

Add the objects to a resource and save it in XMI format:

```swift
// Create a resource and add the objects
let outputResource = await resourceSet.createResource(uri: "output.xmi")
for object in [company, alice, bob] {
    await outputResource.add(object)
}

// Serialise to XMI
try await XMISerializer().serialize(outputResource, to: URL(fileURLWithPath: "output.xmi"))
```

## Using ResourceSet for Cross-References

When working with models that reference objects in other files, load them into one
``ResourceSet``:

```swift
let resourceSet = ResourceSet()

// Load the metamodel and the models
let metamodelURI = URL(fileURLWithPath: "Company.ecore").absoluteString
let metamodelResource = try await resourceSet.loadEcoreResource(uri: metamodelURI)
let modelURI = URL(fileURLWithPath: "company-data.xmi").absoluteString
let modelResource = try await resourceSet.loadXMIResource(uri: modelURI)

// Resolve references to objects in other files
let report = await resourceSet.resolveAllProxies()
```

## Loading and Saving Models in Any Format

``ModelIO`` reads and writes XMI, JSON, Ecore, EMOF, UML, KM3, Emfatic, Xcore, OCLinEcore and
ASDL documents, and reads Langium, Xtext and SDF3 grammars, through one interface. It
registers the metamodels of a model with a ``ResourceSet`` before the model is read, detects
the format from the file name or the contents of the document unless it is given, and reports
whatever a conversion could not keep as ``ConversionDiagnostics``:

```swift
let resourceSet = ResourceSet()
let loaded = try await ModelIO.load(
    url: URL(fileURLWithPath: "company-data.xmi"),
    resourceSet: resourceSet,
    metamodels: [URL(fileURLWithPath: "Company.ecore")])

var diagnostics = loaded.diagnostics
try await ModelIO.save(
    loaded.resource, to: URL(fileURLWithPath: "company-data.json"), diagnostics: &diagnostics)
for warning in diagnostics.warnings {
    print(warning)
}
```

Registering a metamodel also registers each of its nested packages under its own namespace
URI, so documents whose objects are qualified by the namespace of a subpackage are read with
the classes of that subpackage. Explicit registrations take precedence, and
``ResourceSet/getMetamodelURIs(includingSubpackages:)`` lists both.

``ModelFormat`` detects the format of a document on its own: by the extension of its name,
ignoring case, or by the start of its contents, where `{` or `[` starts a JSON document, an
`EPackage` of the Ecore namespace (also inside an `xmi:XMI` wrapper) an Ecore document,
XML in an EMOF or UML namespace an EMOF metamodel or a UML model (see
<doc:DialectsEMOFAndUML>), any other XML an XMI document, and text that starts with
`package Name {` a KM3 document. When the extension names a generic format, such as `.xmi`,
contents in a more specific format take precedence. An Ecore, KM3 or EMOF input is loaded as native packages and registered as a metamodel too. ``ModelIO/LoadOptions`` chooses how XMI references are read and whether the
classes of a JSON document must come from a registered metamodel, and
``ModelIO/serialise(_:format:relativeTo:xmiOptions:registry:diagnostics:)`` returns the text
of a document instead of writing a file.

### Adding Formats

``ModelIO`` reads and writes every document through the ``ModelFormatHandler`` of its format,
which ``ModelFormatRegistry/shared`` provides. Registering a handler makes a further format
available: its file extensions are recognised by name, and a document without a known
extension is offered to the handlers whose ``ModelFormatHandler/priority`` is highest first,
so that a format with a distinctive start, such as a keyword, is recognised before the
generic XMI and JSON formats. A text metamodel format decodes its document as UTF-8 (or in
``ModelIO/LoadOptions/textEncoding``), and its packages are registered as an Ecore
document's are, with its syntax errors and warnings in ``Resource/loadDiagnostics``:

```swift
await ModelFormatRegistry.shared.register(NotationHandler())
let metamodel = try await ModelIO.load(url: URL(fileURLWithPath: "Shapes.notation"), resourceSet: resourceSet)
for diagnostic in await metamodel.resource.loadDiagnostics {
    print(diagnostic.message)
}
```

### Metamodels in KM3

KM3 (Kernel MetaMetaModel) is the textual metamodel language of the ATL tool chain. ``ModelIO``
reads and writes it like any other format, and accepts `.km3` documents as metamodels:

```swift
let resourceSet = ResourceSet()
let families = try await ModelIO.load(
    url: URL(fileURLWithPath: "families.xmi"),
    resourceSet: resourceSet,
    metamodels: [URL(fileURLWithPath: "Families.km3")])

let metamodel = try await ModelIO.load(url: URL(fileURLWithPath: "Families.km3"), resourceSet: ResourceSet())
try await ModelIO.save(metamodel.resource, to: URL(fileURLWithPath: "Families.ecore"))
```

The `-- @nsURI` and `-- @nsPrefix` comments before a package give its namespace. Many KM3
documents have none; as in the ATL tool chain, such a package is then registered with the
resource set under its name, so that a model can name it as its namespace, and a warning
with the code ``EcoreLoadDiagnostic/registeredUnderName`` is recorded in
``Resource/loadDiagnostics``. The primitive types that KM3 documents declare, such as `String`
and `Integer`, stand for the built-in Ecore data types; ``EcoreLoadOptions/km3Options`` set to
``KM3ReadOptions/declaredDataTypes`` keeps them as declared data types instead, as the KM32EMF
transformation of the ATL tool chain does. A document that is not valid UTF-8 is read as
ISO-8859-1 with a warning. ``KM3Reader`` and ``KM3Writer`` can also be used on their own,
and ``KM3Syntax`` classifies the tokens of KM3 text for editors.

### Metamodels in Emfatic and Xcore

Emfatic (`.emf`) and Xcore (`.xcore`) are further textual notations for Ecore metamodels.
``ModelIO`` reads and writes them as it does KM3, and recognises a document without a known
extension by its package declaration (`package library;` in Emfatic, `package org.example`
followed by its declarations in Xcore). A binary `.emf` file, such as a Windows metafile,
is refused with ``ModelFormatError/undetectableFormat(_:)`` rather than read as text.

```swift
let library = try await ModelIO.load(url: URL(fileURLWithPath: "library.emf"), resourceSet: resourceSet)
try await ModelIO.save(library.resource, to: URL(fileURLWithPath: "library.xcore"))
```

The bodies of Xcore operations and derived features are kept as text in annotations but are
not executed, and the metamodels that an Emfatic document imports are not loaded: their
types are kept as placeholders, with a warning. ``EmfaticReader``, ``XcoreReader`` and their writers can also be used on their
own, and ``EmfaticSyntax`` and ``XcoreSyntax`` classify tokens for editors.

### Metamodels with OCL Constraints

OCLinEcore (`.oclinecore`) is the textual notation of Eclipse OCL for metamodels with
embedded constraints. ``ModelIO`` reads and writes it like the other textual notations, and
its imports may name metamodels registered with the resource set. Invariants, operation
bodies, preconditions, postconditions, initial values and derivations are kept as the
annotations that Eclipse OCL writes (see ``OCLConstraintAnnotations``), so they survive
when the metamodel is saved as an Ecore document.

A Complete OCL document (`.ocl`) adds constraints to metamodels that are already loaded.
``ModelIO/applyCompleteOCL(at:to:in:options:)`` replaces the packages of the given
resources, and their registrations, with the constrained packages:

```swift
let resourceSet = ResourceSet()
let school = try await ModelIO.load(url: URL(fileURLWithPath: "School.ecore"), resourceSet: resourceSet)
let applied = try await ModelIO.applyCompleteOCL(
    at: URL(fileURLWithPath: "School.ocl"), to: [school.resource], in: resourceSet)
for diagnostic in applied.diagnostics { print(diagnostic.message) }
try await ModelIO.save(school.resource, to: URL(fileURLWithPath: "School.oclinecore"))
```

The expressions of the constraints are parsed to report syntax errors (see the
`OCLExpressionParser` of the `OCL` module) and kept as text.

### Metamodels from Grammars

A metamodel can be derived from the definition of a language's syntax: a Zephyr ASDL
description (`.asdl`, including the dialect of CPython), a Langium or Xtext grammar
(`.langium`, `.xtext`), or an SDF3 syntax definition or Stratego signature (`.sdf3`).
``ModelIO`` reads these like any metamodel format, recognising a document without a known
extension by its first declaration: `module Name {` is ASDL and `module Name` followed by a
section such as `context-free syntax` is SDF3; `grammar` with a qualified name or a
`generate` declaration is Xtext, and any other `grammar` is Langium. Only ASDL is written.

```swift
let python = try await ModelIO.load(url: URL(fileURLWithPath: "Python.asdl"), resourceSet: resourceSet)
try await ModelIO.save(python.resource, to: URL(fileURLWithPath: "Python.ecore"))
```

The readers recover from errors and build every definition they can read. Where a source
names no package, namespace URI or prefix, they are derived from its name, or taken from
``EcoreLoadOptions/asdlOptions``, ``EcoreLoadOptions/langiumOptions``,
``EcoreLoadOptions/xtextOptions`` and ``EcoreLoadOptions/sdf3Options``. The mapping of each
notation is described on its reader.

## Loading Ecore Documents

``EPackage/init(url:enableDebugging:)`` and ``ResourceSet/loadEcoreResource(uri:)`` load an
`.ecore` document as native ``EPackage``, ``EClass`` and related values, keeping every
construct of the document: supertypes, nested packages, operations and parameters, generic
types, annotations, every feature flag, bounds, default value literals, instance type names,
keys and opposites. Attribute and reference types resolve to the classifiers of the same
document, of other documents, or of Ecore itself through ``EcorePackage``:

```swift
let package = try await EPackage(url: libraryURL)
let book = package.getEClass("Book")
let borrow = book?.eOperations.first              // an EOperation with its EParameter values
let supertypes = book?.eSuperTypes.map(\.name)    // every supertype, in order
```

The package that ``EPackage/init(url:enableDebugging:)`` returns is the root package with its
subpackages attached. ``EPackage/allPackages`` lists a package and every nested package depth
first, and ``EPackage/getClassifier(_:includingSubpackages:)`` searches them all. A resource
keeps every root package of a document in order, and its contents are enumerated in document
order, the same on every load. ``EPackage/rootPackages(url:options:enableDebugging:)`` returns
all root packages of a document, with the references between them resolved:

```swift
let packages = try await EPackage.rootPackages(url: libraryURL)
```

As in EMF, a package need not declare a namespace URI or prefix. Such a package, typically one
that holds only data types for the other packages of its document, loads with empty values,
is not registered under a namespace, and is reported as a warning in
``Resource/loadDiagnostics``; the constraint `WellFormedNsURI` of ``EcoreValidator`` still
reports its missing URI.

A document is read in the encoding that its XML declaration names, such as `ISO-8859-1` or
`windows-1252`, unless its bytes are valid UTF-8; documents in UTF-16 are recognised by their
first bytes. A document read in another encoding is written back in UTF-8.

Loading is strict by default. Editors that must open incomplete documents can pass
``EcoreLoadOptions`` to ``ResourceSet/loadEcoreResource(uri:options:)``: references to
targets that are not available are then kept, with their original spelling, and missing
names are reported in ``Resource/loadDiagnostics``.
``EcoreValidator`` checks a loaded metamodel, including keys, generic types and retained
unresolved references, and each of its constraints can be disabled through its options:

```swift
let resource = try await resourceSet.loadEcoreResource(
    uri: URL(fileURLWithPath: "models/draft.ecore").absoluteString,
    options: EcoreLoadOptions(unresolvedReferences: .keepAsProxies, tolerant: true))
for diagnostic in await resource.loadDiagnostics {
    print(diagnostic)
}
```

## Writing Ecore Documents as EMF Does

``XMISerializer`` writes a package, including ``EcorePackage/instance``, as an `.ecore`
document with ``XMISerializer/serialize(_:)-(EPackage)``, and several root packages as one
document with ``XMISerializer/serialize(_:relativeTo:)-([EPackage],_)``.
Comments, the XML encoding declaration and explicit `xmi:id` values follow their elements
through edits and saving, and types and opposites in documents that cannot be loaded are
written back unchanged.

References to classifiers of other documents are written with URIs relative to the location
of the document and, as EMF does, the kind of the classifier, such as
`eType="ecore:EEnum shared.ecore#//Colour"`. Classifiers of Ecore itself are written with the
Ecore namespace URI.

``XMISerializationOptions`` controls the layout. ``XMISerializationOptions/emf`` writes model
documents as EMF does, with attribute-style references, type qualifiers, relative URIs,
name-based fragments, many-valued attributes as elements and without default values.
``XMISerializationOptions/emfWrapped`` also wraps long attribute lists at
``XMISerializationOptions/emfLineWidth`` columns, as the editors of EMF do, so that documents
saved by EMF round trip unchanged. EMF releases differ in how they wrap the root element:
``XMIRootLayout`` reproduces either layout, and ``XMIRootLayout/detect(in:)`` tells which one
a document uses. ``XMISerializationOptions/referenceStyle`` chooses whether references within
a document are written as `#//@entries.0` or `//@entries.0`.

Enumeration-typed attributes are read and written by literal text, and unsettable attributes
that are set to their default value are still written, as in EMF. An empty resource is
written as an `xmi:XMI` element alone, and read back as an empty resource.

## Following References Across Documents

References to objects in other documents, written as attributes such as
`ecoreFeature="ecore:EAttribute library.ecore#//Book/title"`, as space-separated lists, or as
`href` elements, are read as ``ResourceProxy`` values when the metamodel declares the
reference. The resource set loads their targets on demand:

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

`.ecore` documents reached through a proxy are loaded as dynamic objects;
``ResourceSet/loadEcoreResource(uri:)`` loads one as native packages instead.

## Models and Metamodels as JSON

``JSONParser`` builds objects from the metamodels registered with a ``ResourceSet``: `eClass`
values, such as `"http://example.org/library#//Book"` or a bare class name, select the
registered classes, attributes are converted by their data types, enumerations hold literal
names, and `$ref` values such as `//@authors.0`, `#/authors/0` or `other.json#//@authors.0`
resolve to objects or proxies. A nested object takes the class that its own `eClass` names,
and otherwise the type of the reference that contains it. ``JSONParseOptions/requiresMetamodel``
turns an unknown class into an error. Without a registered metamodel, classes are derived
from the keys of the document. ``JSONSerializer`` writes package-qualified `eClass` values and
`{"$ref": ...}` references, leaves out the container side of a containment, and writes an
empty resource as `[]`. Documents written by earlier releases still load.

Metamodels can be written and read as JSON too, following the emfjson conventions for Ecore
models. Every construct of an `.ecore` document is kept, and the same packages always give
the same text. Each object names its metaclass in `eClass`, contained elements are nested
under their containment feature, attributes are written only where they differ from their
defaults, and references are `$ref` objects with name-based fragments:

```json
{
  "eClass": "http://www.eclipse.org/emf/2002/Ecore#//EPackage",
  "name": "shop",
  "nsURI": "http://example.org/shop",
  "nsPrefix": "shop",
  "eClassifiers": [
    {
      "eClass": "http://www.eclipse.org/emf/2002/Ecore#//EClass",
      "name": "Order",
      "eStructuralFeatures": [
        {
          "eClass": "http://www.eclipse.org/emf/2002/Ecore#//EAttribute",
          "name": "total",
          "eType": {
            "eClass": "http://www.eclipse.org/emf/2002/Ecore#//EDataType",
            "$ref": "http://www.eclipse.org/emf/2002/Ecore#//EInt"
          }
        }
      ]
    }
  ]
}
```

``ModelIO`` converts between the two forms, and ``EPackage/init(url:enableDebugging:)`` and
``ResourceSet/loadEcoreResource(uri:)`` read either:

```swift
let resourceSet = ResourceSet()
let metamodel = try await ModelIO.load(url: ecoreURL, resourceSet: resourceSet)
try await ModelIO.save(metamodel.resource, to: jsonURL)             // .ecore to JSON
let fromJSON = try await ModelIO.load(url: jsonURL, resourceSet: ResourceSet())
try await ModelIO.save(fromJSON.resource, to: ecoreCopyURL)         // JSON to .ecore
```

Malformed documents, unknown metaclasses and references to missing elements are reported as
``JSONError`` values.

## Shipping a Metamodel with a Package

A package that ships an `.ecore` document as a resource of one of its targets loads it with
``EPackage/bundled(named:withExtension:subdirectory:in:bundleName:registeringIn:cache:)``.
The document is loaded once, through ``BundledMetamodelCache``, so every caller receives the
same package:

```swift
let package = try await EPackage.bundled(
    named: "Company", subdirectory: "Resources", in: .module,
    bundleName: ResourceBundleName(package: "swift-example", target: "Metamodels"),
    registeringIn: resourceSet)
```

The bundle name is used where `Bundle.module` is not available, such as on WASI, to find the
resource directory beside the executable. On WASI, `Bundle.module` stops the program when that
directory is not where the build placed it, so the bundle is evaluated there only when no bundle
name is given: code that runs on WASI should always pass one.

## Next Steps

- <doc:UnderstandingEcore> - Learn about the core concepts
- ``EClass`` - Defining classes in your metamodel
- ``EReference`` - Modelling relationships between classes
- ``Resource`` - Managing model persistence
