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