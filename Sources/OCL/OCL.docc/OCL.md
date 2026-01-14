# ``OCL``

@Metadata {
    @DisplayName("OCL")
}

A pure Swift implementation of the OMG Object Constraint Language
(OCL) for model querying and constraint specification.

## Overview

OCL provides a complete implementation of the Object Constraint
Language ([OCL](https://www.omg.org/spec/OCL/))
standard in pure Swift. Use it to query models, specify
constraints, and perform operations on collections, strings, and
numeric values in a declarative, side-effect-free manner.

The framework follows the OMG OCL 2.4 specification
([OMG OCL 2.4](https://www.omg.org/spec/OCL/2.4/PDF)),
providing familiar OCL operations for developers experienced with
Eclipse OCL ([Eclipse OCL](https://projects.eclipse.org/projects/modeling.mdt.ocl))
or other OCL implementations whilst offering a modern, type-safe
Swift API.

### Key Features

- **Standard Library**: Complete OCL standard library operations
- **Collection Operations**: Query and transform collections with
  select, reject, collect, forAll, exists, and iterate
- **String Manipulation**: Rich string operations including concat,
  substring, indexOf, and pattern matching
- **Numeric Operations**: Mathematical functions including abs, floor,
  ceiling, round, and power
- **Type Operations**: Runtime type checking and casting with
  oclIsTypeOf, oclIsKindOf, and oclAsType
- **Side-effect Free**: All operations are pure and do not modify
  the underlying model

### Quick Example

```swift
import OCL

// Collection operations
let numbers = [1, 2, 3, 4, 5]
let evenNumbers = try OCL.select(numbers) { $0 % 2 == 0 }
// Result: [2, 4]

// String operations
let text = "Hello, World!"
let upper = try OCL.toUpperCase(text)
// Result: "HELLO, WORLD!"

// Numeric operations
let value = -42.7
let absolute = try OCL.abs(value)
// Result: 42.7
```

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:UnderstandingOCL>

### Standard Library

- ``OCLUnaryMethod``
- ``OCLBinaryMethod``
- ``OCLTernaryMethod``

### Error Handling

- ``OCLError``

## See Also

- [OMG OCL (Object Constraint Language)](https://www.omg.org/spec/OCL/)
- [OMG OCL 2.4 Specification](https://www.omg.org/spec/OCL/2.4/PDF)
- [Eclipse OCL](https://projects.eclipse.org/projects/modeling.mdt.ocl)
- [The Ultimate OCL Tutorial](https://modeling-languages.com/ocl-tutorial/)
- [Eclipse Modeling Framework (EMF)](https://eclipse.dev/emf/)
- [OMG MOF (Meta Object Facility)](https://www.omg.org/mof/)
