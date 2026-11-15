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

- [swift-aql](https://mipalgu.github.io/swift-aql/) - AQL model queries ([GitHub](https://github.com/mipalgu/swift-aql))
- [swift-mtl](https://mipalgu.github.io/swift-mtl/) - MTL model-to-text generation ([GitHub](https://github.com/mipalgu/swift-mtl))
- [swift-atl](https://mipalgu.github.io/swift-atl/) - ATL model transformations ([GitHub](https://github.com/mipalgu/swift-atl))
- [swift-henshin](https://mipalgu.github.io/swift-henshin/) - Henshin graph transformation, critical pair analysis and state-space exploration ([GitHub](https://github.com/mipalgu/swift-henshin))
- [swift-epsilon](https://mipalgu.github.io/swift-epsilon/) - Epsilon model management languages (EOL, EVL, ETL and EGL) ([GitHub](https://github.com/mipalgu/swift-epsilon))
- [swift-xtend](https://mipalgu.github.io/swift-xtend/) - Xtend generators and transformations ([GitHub](https://github.com/mipalgu/swift-xtend))
- [swift-modelling](https://mipalgu.github.io/swift-modelling/) - Command-line tools, code generators and tutorials for the whole toolkit ([GitHub](https://github.com/mipalgu/swift-modelling))

## Documentation

The package provides the ECore metamodelling framework, OCL
operations, and EMFBase foundation types.
For ECore, see
[Getting Started](documentation/ecore/gettingstarted) and
[Understanding Ecore](documentation/ecore/understandingecore).
For OCL, see
[Getting Started](documentation/ocl/gettingstarted) and
[Understanding OCL](documentation/ocl/understandingocl).

The `swift-ecore` command-line tool of [swift-modelling](https://mipalgu.github.io/swift-modelling/) is described in
[swift-ecore](https://mipalgu.github.io/swift-modelling/documentation/swift_ecore/index.html), and the
[Ecore tutorials](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/01-first-metamodel/index.html)
introduce it step by step (see all [tutorials](https://mipalgu.github.io/swift-modelling/tutorials/tutorials/index.html)).

The module pages are [ECore](documentation/ecore/), [OCL](documentation/ocl/),
[GenModel](documentation/genmodel/), [ECoreEdit](documentation/ecoreedit/),
[MultiLevel](documentation/multilevel/) and [EMFBase](documentation/emfbase/).

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
