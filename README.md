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
  proxies and the fragment forms of EMF; JSON metamodels follow the emfjson conventions
- **EMF semantics**: dates, identifiers, many-valued attributes and validation of
  multiplicities and data values behave as in EMF
- **Libraries for tools**: OCL constraints and queries, generator models (`.genmodel`), and
  value-based metamodel editing with undo and redo

## Requirements

- Swift 6.0 or later
- macOS 15 or later, iOS 18 or later, Linux, Windows, or WebAssembly (WASI)

## Installation

Add swift-ecore to the dependencies of your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/mipalgu/swift-ecore.git", from: "0.7.0"),
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

Explore a metamodel directly:

```swift
let package = try await EPackage(url: URL(fileURLWithPath: "library.ecore"))
if let book = package.getEClass("Book") {
    print(book.eSuperTypes.map(\.name), book.eOperations.map(\.name))
}
```

For working with models from the command line, the `swift-ecore` tool of
[Swift Modelling](https://github.com/mipalgu/swift-modelling) validates, converts, queries and
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
- [EMFBase](https://mipalgu.github.io/swift-ecore/documentation/emfbase/)

## Licence

See the details in the LICENCE file. The bundled Eclipse UML2 metamodels are under the
Eclipse Public License 2.0; see `Sources/ECore/Resources/UML/NOTICE`.

## References

This implementation is based on the following standards and technologies:

- [Eclipse Modeling Framework (EMF)](https://eclipse.dev/emf/): the reference EMF implementation
- [OMG MOF (Meta Object Facility)](https://www.omg.org/mof/): the metamodelling standard
- [OMG XMI (XML Metadata Interchange)](https://www.omg.org/spec/XMI/): the XML serialisation format
- [OMG OCL (Object Constraint Language)](https://www.omg.org/spec/OCL/): the constraint and query language
