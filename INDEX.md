# Swift ECore

The [swift-ecore](https://github.com/mipalgu/swift-ecore) package
provides a pure Swift implementation of
[EMF/Ecore](https://eclipse.dev/emf/) for Model-Driven Engineering.

## Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/mipalgu/swift-ecore.git", branch: "main"),
]
```

## Requirements

- Swift 6.0 or later
- macOS 15.0+, Linux, or Windows

## References

- [Eclipse Modeling Framework (EMF)](https://eclipse.dev/emf/)
- [OMG MOF (Meta Object Facility)](https://www.omg.org/mof/)
- [OMG XMI (XML Metadata Interchange)](https://www.omg.org/spec/XMI/)
- [OMG OCL (Object Constraint Language)](https://www.omg.org/spec/OCL/)

## Related Packages

- [swift-atl](https://github.com/mipalgu/swift-atl) - ATL model transformations
- [swift-mtl](https://github.com/mipalgu/swift-mtl) - MTL code generation
- [swift-aql](https://github.com/mipalgu/swift-aql) - AQL model queries
- [swift-modelling](https://github.com/mipalgu/swift-modelling) - Unified MDE toolkit

## Documentation

The package provides the ECore metamodelling framework, OCL
operations, and EMFBase foundation types.
For ECore, see
[Getting Started](documentation/ecore/gettingstarted) and
[Understanding Ecore](documentation/ecore/understandingecore).
For OCL, see
[Getting Started](documentation/ocl/gettingstarted) and
[Understanding OCL](documentation/ocl/understandingocl).
