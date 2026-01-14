# Getting Started with OCL

Learn how to use OCL operations in your Swift projects.

## Overview

The Object Constraint Language (OCL) is a declarative, side-effect
free language for querying and constraining models. This guide shows
you how to get started with OCL operations in Swift.

## Installation

Add the OCL package dependency to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/mipalgu/swift-ecore.git",
             branch: "main"),
]
```

Then add OCL to your target dependencies:

```swift
targets: [
    .target(
        name: "YourTarget",
        dependencies: [
            .product(name: "OCL",
                    package: "swift-ecore"),
        ]
    ),
]
```

## Your First OCL Expression

Import the OCL module and use its operations:

```swift
import OCL

// Filter a collection
let numbers = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
let evenNumbers = try OCL.select(numbers) { $0 % 2 == 0 }
print(evenNumbers)  // [2, 4, 6, 8, 10]

// Transform a collection
let doubled = try OCL.collect(numbers) { $0 * 2 }
print(doubled)  // [2, 4, 6, 8, 10, 12, 14, 16, 18, 20]

// Check conditions
let allPositive = try OCL.forAll(numbers) { $0 > 0 }
print(allPositive)  // true

let hasLarge = try OCL.exists(numbers) { $0 > 8 }
print(hasLarge)  // true
```

## Collection Operations

OCL provides rich collection query operations:

```swift
let data = [1, 2, 3, 4, 5]

// Filter elements
let filtered = try OCL.select(data) { $0 > 2 }
// Result: [3, 4, 5]

// Reject elements
let rejected = try OCL.reject(data) { $0 % 2 == 0 }
// Result: [1, 3, 5]

// Check size
let count = try OCL.size(data)
// Result: 5

// Get first and last
let first = try OCL.first(data)  // 1
let last = try OCL.last(data)    // 5
```

## String Operations

Manipulate strings with OCL's string library:

```swift
import OCL

let text = "Hello, World!"

// Convert case
let upper = try OCL.toUpperCase(text)
// Result: "HELLO, WORLD!"

let lower = try OCL.toLowerCase(text)
// Result: "hello, world!"

// Concatenation
let greeting = try OCL.concat("Hello", ", Swift!")
// Result: "Hello, Swift!"

// Substring
let sub = try OCL.substring("Hello", 0, 5)
// Result: "Hello"

// Pattern matching
let starts = try OCL.startsWith(text, "Hello")
// Result: true

let contains = try OCL.contains(text, "World")
// Result: true
```

## Numeric Operations

Perform mathematical operations:

```swift
import OCL

// Absolute value
let abs1 = try OCL.abs(-42)      // 42
let abs2 = try OCL.abs(-3.14)    // 3.14

// Rounding
let floor = try OCL.floor(3.7)    // 3
let ceil = try OCL.ceiling(3.2)   // 4
let round = try OCL.round(3.5)    // 4

// Min/Max
let min = try OCL.min(5, 3)      // 3
let max = try OCL.max(5, 3)      // 5

// Power
let power = try OCL.power(2, 8)  // 256
```

## Type Operations

Check and cast types at runtime:

```swift
import OCL
import ECore

let object: Any = "Hello"

// Check type
let isString = try OCL.oclIsTypeOf(object, String.self)
// Result: true

// Type name
let typeName = try OCL.oclTypeName(object)
// Result: "String"
```

## Error Handling

All OCL operations can throw ``OCLError`` exceptions. Handle them
appropriately:

```swift
do {
    let result = try OCL.first([])  // Empty collection
} catch OCLError.invalidOperation(let message) {
    print("Operation failed: \(message)")
} catch {
    print("Unexpected error: \(error)")
}
```

## Integration with ECore

OCL operations work seamlessly with ECore models:

```swift
import ECore
import OCL

// Filter EObjects by property
let classes = try OCL.select(package.eClassifiers) { classifier in
    guard let eClass = classifier as? EClass else {
        return false
    }
    return eClass.abstract
}

// Collect attribute names
let attributeNames = try OCL.collect(eClass.eAttributes) {
    $0.name
}
```

## Next Steps

- Explore <doc:UnderstandingOCL> for detailed operation categories
- See ``OCLUnaryMethod``, ``OCLBinaryMethod``, and ``OCLTernaryMethod``
  for available operations
- Review the OCL API reference for complete function documentation

## See Also

- <doc:UnderstandingOCL>
- ``OCLUnaryMethod``
- ``OCLBinaryMethod``
- ``OCLTernaryMethod``
- ``OCLError``
