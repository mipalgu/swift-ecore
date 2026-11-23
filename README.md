# Swift ECore

[![CI](https://github.com/mipalgu/swift-ecore/actions/workflows/ci.yml/badge.svg)](https://github.com/mipalgu/swift-ecore/actions/workflows/ci.yml)
[![Documentation](https://github.com/mipalgu/swift-ecore/actions/workflows/documentation.yml/badge.svg)](https://github.com/mipalgu/swift-ecore/actions/workflows/documentation.yml)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fmipalgu%2Fswift-ecore%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/mipalgu/swift-ecore)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fmipalgu%2Fswift-ecore%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/mipalgu/swift-ecore)

A pure Swift implementation of the Eclipse Modelling Framework (EMF) Ecore metamodel for
macOS, Linux, Windows and WebAssembly.

## Features

- **Pure Swift**: no Java or EMF dependencies, with strict concurrency and `Sendable` values
- **Complete metamodel**: packages, classes, data types, enumerations, attributes, references,
  operations, generic types and annotations, with the Ecore metamodel itself available
  reflectively
- **Faithful Ecore documents**: `.ecore` files load with every construct intact and can be
  written back in the layout that EMF writes
- **XMI and JSON**: models and metamodels in either format, with cross-document references,
  proxies and the fragment forms of EMF; a metamodel is recognised by its contents, so one
  saved as `.xmi` loads back as packages; JSON metamodels follow the emfjson conventions
- **UML class models as metamodels**: converted into Ecore as Eclipse UML2 converts them
- **EMF semantics**: dates, identifiers, many-valued attributes and validation of
  multiplicities and data values behave as in EMF, and `EObject` is the implicit supertype
  of every class, so asking for all instances of `EObject` returns every object
- **Libraries for tools**: OCL constraints and queries, generator models (`.genmodel`), and
  value-based metamodel editing with undo and redo
- **Incremental evaluation**: change observers and dependency records for incremental engines
- **Multi-level modelling**: deep models with potency, in the MetaDepth notation

## Requirements

- Swift 6.0 or later
- macOS 15 or later, iOS 18 or later, Linux, Windows, or WebAssembly (WASI)

## Installation

Add swift-ecore to the dependencies of your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/mipalgu/swift-ecore.git", from: "0.8.0"),
]
```

Then add the libraries you need to your target:

```swift
.target(
    name: "MyTool",
    dependencies: [
        .product(name: "ECore", package: "swift-ecore"),
    ]
)
```

| Library | Purpose |
|--|--|
| `ECore` | Metamodels, models, resources, and XMI and JSON serialisation |
| `OCL` | The OCL standard library for constraints and queries |
| `GenModel` | The generator model metamodel, loader and a facade for code generators |
| `ECoreEdit` | Editing metamodels as values, for metamodel editors and diagram tools |
| `MultiLevel` | Multi-level models, the MetaDepth notation, and Ecore views of their levels |
| `EMFBase` | Primitive Ecore types and diagnostics shared by the other libraries |

## Building

```bash
# Build the library
swift build

# Run the tests
swift test
```

## Usage

Load a metamodel and a model, then save the model as JSON:

```swift
import ECore
import Foundation

let resourceSet = ResourceSet()
let loaded = try await ModelIO.load(
    url: URL(fileURLWithPath: "library.xmi"),
    resourceSet: resourceSet,
    metamodels: [URL(fileURLWithPath: "library.ecore")])

let diagnostics = try await ModelIO.save(
    loaded.resource, to: URL(fileURLWithPath: "library.json"))
for warning in diagnostics.warnings {
    print(warning)
}
```

`ModelIO.save` writes a copy and leaves the URI of the resource unchanged. To move a model to a
new document, as "save as" does in EMF, use `ModelIO.saveAs`, which writes the document and
then gives the resource its URI, so that other models in the same resource set refer to the
new location when they are saved:

```swift
var saveDiagnostics = ConversionDiagnostics()
try await ModelIO.saveAs(
    loaded.resource, to: URL(fileURLWithPath: "archive/library.xmi"), diagnostics: &saveDiagnostics)
```

Explore a metamodel directly:

```swift
let package = try await EPackage(url: URL(fileURLWithPath: "library.ecore"))
if let book = package.getEClass("Book") {
    print(book.eSuperTypes.map(\.name), book.eOperations.map(\.name))
}
```

For working with models from the command line, the `swift-ecore` tool of
[Swift Modelling](https://mipalgu.github.io/swift-modelling/) validates, converts, queries and
generates code from Ecore metamodels and models.

## Documentation

The [swift-ecore documentation](https://mipalgu.github.io/swift-ecore/) covers every library:

- [ECore](https://mipalgu.github.io/swift-ecore/documentation/ecore/), with
  [Getting Started](https://mipalgu.github.io/swift-ecore/documentation/ecore/gettingstarted/),
  [Understanding Ecore](https://mipalgu.github.io/swift-ecore/documentation/ecore/understandingecore/)
  and [Compatibility](https://mipalgu.github.io/swift-ecore/documentation/ecore/compatibility/),
  which describes the changes since version 0.6
- [OCL](https://mipalgu.github.io/swift-ecore/documentation/ocl/)
- [GenModel](https://mipalgu.github.io/swift-ecore/documentation/genmodel/)
- [ECoreEdit](https://mipalgu.github.io/swift-ecore/documentation/ecoreedit/)
- [MultiLevel](https://mipalgu.github.io/swift-ecore/documentation/multilevel/)
- [EMFBase](https://mipalgu.github.io/swift-ecore/documentation/emfbase/)

The `swift-ecore` command-line tool of [swift-modelling](https://mipalgu.github.io/swift-modelling/) is described in
[swift-ecore](https://mipalgu.github.io/swift-modelling/documentation/swift_ecore/index.html), and the
[Ecore tutorials](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/01-first-metamodel/index.html)
introduce it step by step (see all [tutorials](https://mipalgu.github.io/swift-modelling/tutorials/tutorials/index.html)).

### Tutorials

**Ecore Metamodelling**

- [Creating Your First Ecore Metamodel](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/01-first-metamodel/index.html)
- [Working with Model Instances](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/02-model-instances/index.html)
- [Metamodel Relationships](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/03-metamodel-relationships/index.html)
- [Advanced Metamodel Features](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/04-advanced-features/index.html)
- [JSON and XMI Formats](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/05-xmi-json-conversion/index.html)
- [Querying Models with AQL](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/06-querying-models/index.html)
- [Cross-Resource References](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/07-cross-resource-refs/index.html)

**OCL Constraints**

- [OCL Constraints and Validation](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/ocl-01-constraints/index.html)
- [Constraints in OCLinEcore and Complete OCL](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/formats-04-ocl-languages/index.html)

**Metamodel Languages and Formats**

- [Metamodels in KM3](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/formats-01-km3/index.html)
- [EMOF Metamodels and UML Models](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/formats-02-uml-emof/index.html)
- [Textual Metamodels with Emfatic and Xcore](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/formats-03-emfatic-xcore/index.html)
- [Constraints in OCLinEcore and Complete OCL](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/formats-04-ocl-languages/index.html)

**From Grammars to Metamodels**

- [Importing Abstract Syntax](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/grammar-01-abstract-syntax/index.html)
- [Importing Grammars](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/grammar-02-concrete-syntax/index.html)

**Formal Verification Exports**

- [Checking a Metamodel with Alloy](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/verification-01-alloy/index.html)

**Java Code Generation**

- [From Ecore to a Generator Model](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/java-01-ecore-to-genmodel/index.html)
- [From a Generator Model to Java](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/java-02-genmodel-to-java/index.html)

**Multi-Level Modelling**

- [Multi-Level Modelling with Potency](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/multilevel-01-deep-modelling/index.html)

**Integrated Workflows**

- [Complete MDE Workflow: From Metamodel to Code](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/01-complete-mde-workflow/index.html)
- [Model Refactoring Pipeline](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/02-model-refactoring-pipeline/index.html)
- [Cross-Format Integration](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/03-cross-format-integration/index.html)

## Related Packages

- [swift-aql](https://mipalgu.github.io/swift-aql/) - AQL model queries ([GitHub](https://github.com/mipalgu/swift-aql))
- [swift-mtl](https://mipalgu.github.io/swift-mtl/) - MTL model-to-text generation ([GitHub](https://github.com/mipalgu/swift-mtl))
- [swift-atl](https://mipalgu.github.io/swift-atl/) - ATL model transformations ([GitHub](https://github.com/mipalgu/swift-atl))
- [swift-henshin](https://mipalgu.github.io/swift-henshin/) - Henshin graph transformation, critical pair analysis and state-space exploration ([GitHub](https://github.com/mipalgu/swift-henshin))
- [swift-epsilon](https://mipalgu.github.io/swift-epsilon/) - Epsilon model management languages (EOL, EVL, ETL and EGL) ([GitHub](https://github.com/mipalgu/swift-epsilon))
- [swift-xtend](https://mipalgu.github.io/swift-xtend/) - Xtend generators and transformations ([GitHub](https://github.com/mipalgu/swift-xtend))
- [swift-modelling](https://mipalgu.github.io/swift-modelling/) - Command-line tools, code generators and tutorials for the whole toolkit ([GitHub](https://github.com/mipalgu/swift-modelling))

## Licence

See the details in the LICENCE file. The bundled Eclipse UML2 metamodels are under the
Eclipse Public License 2.0; see `Sources/ECore/Resources/UML/NOTICE`.

## References

This implementation is based on the following standards and technologies:

- [Eclipse Modeling Framework (EMF)](https://eclipse.dev/emf/): the reference EMF implementation
- [OMG MOF (Meta Object Facility)](https://www.omg.org/mof/): the metamodelling standard
- [OMG XMI (XML Metadata Interchange)](https://www.omg.org/spec/XMI/): the XML serialisation format
- [OMG OCL (Object Constraint Language)](https://www.omg.org/spec/OCL/): the constraint and query language
