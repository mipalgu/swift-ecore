# Swift ECore - EMF/Ecore for Swift

The [swift-ecore](https://github.com/mipalgu/swift-ecore) package
aims to provide a pure Swift implementation of the
[Eclipse Modeling Framework (EMF)](https://eclipse.dev/emf/) Ecore metamodelling system for
Model-Driven Engineering (MDE).

## Overview

Swift ECore enables building model-driven applications in Swift, providing:

- **ECore metamodelling**: Define metamodels using EClass, EAttribute, EReference, and EPackage
- **Dynamic model instances**: Create and manipulate model instances at runtime
- **XMI serialisation**: Load and save models in XMI format (compatible with Eclipse EMF)
- **JSON serialisation**: Alternative JSON format for model persistence
- **OCL support**: [Object Constraint Language (OCL)](https://www.omg.org/spec/OCL/) operations for model querying
- **Cross-resource references**: Support for models spanning multiple files

## Installation

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

### Available Products

The package provides three library products:

| Product | Description |
|---------|-------------|
| **ECore** | Core metamodelling framework with XMI/JSON serialisation |
| **EMFBase** | Base types and protocols (EcoreValue, EUUID, etc.) |
| **OCL** | Object Constraint Language operations |

## Quick Start

```swift
import ECore

// Load a metamodel
let parser = XMIParser()
let resource = try await parser.parse(URL(fileURLWithPath: "MyMetamodel.ecore"))

// Access the package
guard let package = resource.rootObjects.first as? EPackage else {
    fatalError("No package found")
}

// Find an EClass
let personClass = package.eClassifiers.first { $0.name == "Person" } as? EClass

// Create a dynamic instance
let person = DynamicEObject(eClass: personClass!)
person.eSet("name", value: "Alice")
```

## Documentation

Detailed documentation is available in the generated DocC documentation:

- **Getting Started**: Installation and first steps
- **Understanding Ecore**: Core concepts and architecture
- **API Reference**: Complete API documentation

## Requirements

- macOS 15.0+
- Swift 6.0+

## References

This implementation is based on the following standards and technologies:

- [Eclipse Modeling Framework (EMF)](https://eclipse.dev/emf/) - The reference implementation
- [OMG MOF (Meta Object Facility)](https://www.omg.org/mof/) - The metamodelling standard
- [OMG OCL (Object Constraint Language)](https://www.omg.org/spec/OCL/) - Query and constraint language
- [OMG XMI (XML Metadata Interchange)](https://www.omg.org/spec/XMI/) - Model serialisation format

## Related Packages

- [swift-atl](https://github.com/mipalgu/swift-atl) - ATL model transformations
- [swift-mtl](https://github.com/mipalgu/swift-mtl) - MTL code generation
- [swift-aql](https://github.com/mipalgu/swift-aql) - AQL model queries
- [swift-modelling](https://github.com/mipalgu/swift-modelling) - Unified MDE toolkit
