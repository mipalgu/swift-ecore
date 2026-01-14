# Understanding OCL

Learn the fundamental concepts of the Object Constraint Language.

## Overview

The Object Constraint Language
([OCL](https://www.omg.org/spec/OCL/))
is a declarative language for querying and constraining models. It
provides a precise, formal way to express constraints and queries
that cannot be expressed using UML diagrams alone.

OCL is based on the OMG OCL 2.4 specification
([OMG OCL 2.4](https://www.omg.org/spec/OCL/2.4/PDF))
and provides a side-effect-free expression language for navigating
models and specifying constraints.

## Core Characteristics

### Declarative

OCL is a declarative language. You specify *what* you want to
compute, not *how* to compute it. The OCL engine determines the
execution strategy.

### Side-Effect Free

OCL expressions cannot modify the model. They can only query the
current state. This ensures that evaluating an expression does not
change the system being queried.

### Typed

Every OCL expression has a type. The type system ensures that
operations are used correctly and helps catch errors at compile
time.

## OCL in Model-Driven Engineering

OCL plays a critical role in Model-Driven Engineering (MDE):

- **Constraints**: Express invariants that must hold for model
  instances
- **Queries**: Navigate and query model structures
- **Derivation Rules**: Compute derived attribute values
- **Guards**: Specify conditions for state transitions
- **Pre/Post Conditions**: Define operation contracts

## Relationship with AQL

AQL (Acceleo Query Language) is based on OCL but provides a
simplified, more accessible syntax. Many AQL operations directly
correspond to OCL operations. The swift-ecore ecosystem supports
both OCL and AQL.

## Operation Categories

### Collection Operations

Collection operations query and transform collections of elements.

| Operation | Description | Example |
|-----------|-------------|---------|
| `size()` | Number of elements | `col.size()` |
| `isEmpty()` | True if no elements | `col.isEmpty()` |
| `notEmpty()` | True if has elements | `col.notEmpty()` |
| `first()` | First element | `col.first()` |
| `last()` | Last element | `col.last()` |
| `at(index)` | Element at index | `col.at(0)` |

#### Filtering

| Operation | Description | Example |
|-----------|-------------|---------|
| `select(condition)` | Keep matching elements | `select(col) { $0 > 5 }` |
| `reject(condition)` | Remove matching elements | `reject(col) { $0 < 0 }` |

#### Transformation

| Operation | Description | Example |
|-----------|-------------|---------|
| `collect(expr)` | Map to new values | `collect(col) { $0 * 2 }` |
| `flatten()` | Flatten nested collections | `flatten(nested)` |

#### Testing

| Operation | Description | Example |
|-----------|-------------|---------|
| `forAll(condition)` | All elements match | `forAll(col) { $0 > 0 }` |
| `exists(condition)` | Any element matches | `exists(col) { $0 == 5 }` |
| `one(condition)` | Exactly one matches | `one(col) { $0 > 10 }` |
| `includes(elem)` | Contains element | `includes(col, 5)` |
| `excludes(elem)` | Doesn't contain | `excludes(col, 5)` |

#### Set Operations

| Operation | Description | Example |
|-----------|-------------|---------|
| `union(other)` | Combine collections | `union(col1, col2)` |
| `intersection(other)` | Common elements | `intersection(col1, col2)` |
| `excluding(elem)` | Remove specific element | `excluding(col, elem)` |
| `including(elem)` | Add element | `including(col, elem)` |

#### Iteration

| Operation | Description |
|-----------|-------------|
| `iterate(init, body)` | Custom iteration with accumulator |

### String Operations

String operations manipulate and query text.

| Operation | Description | Example |
|-----------|-------------|---------|
| `toUpperCase()` | Uppercase | `toUpperCase("hello")` |
| `toLowerCase()` | Lowercase | `toLowerCase("HELLO")` |
| `concat(str)` | Concatenate | `concat("Hello", " World")` |
| `substring(start, end)` | Extract portion | `substring("Hello", 0, 5)` |
| `indexOf(str)` | Find position | `indexOf("Hello", "ll")` |
| `contains(str)` | Contains substring | `contains("Hello", "ell")` |
| `startsWith(prefix)` | Check prefix | `startsWith("Hello", "He")` |
| `endsWith(suffix)` | Check suffix | `endsWith("Hello", "lo")` |
| `replaceAll(old, new)` | Replace all | `replaceAll("Hello", "l", "L")` |
| `trim()` | Remove whitespace | `trim("  hello  ")` |
| `at(index)` | Character at index | `at("Hello", 0)` |

### Numeric Operations

Numeric operations perform mathematical computations.

| Operation | Description | Example |
|-----------|-------------|---------|
| `abs()` | Absolute value | `abs(-42)` |
| `floor()` | Floor | `floor(3.7)` |
| `ceiling()` | Ceiling | `ceiling(3.2)` |
| `round()` | Round | `round(3.5)` |
| `max(other)` | Maximum value | `max(5, 3)` |
| `min(other)` | Minimum value | `min(5, 3)` |
| `power(exp)` | Exponentiation | `power(2, 8)` |

#### Arithmetic

| Operation | Description | Example |
|-----------|-------------|---------|
| `+` | Addition | `add(5, 3)` |
| `-` | Subtraction | `subtract(5, 3)` |
| `*` | Multiplication | `multiply(5, 3)` |
| `/` | Division | `divide(10, 2)` |
| `mod` | Modulo | `modulo(10, 3)` |

### Comparison Operations

Comparison operations compare values.

| Operation | Description | Example |
|-----------|-------------|---------|
| `=` | Equal | `equals(5, 5)` |
| `<>` | Not equal | `notEquals(5, 3)` |
| `<` | Less than | `lessThan(3, 5)` |
| `<=` | Less or equal | `lessThanOrEqual(3, 5)` |
| `>` | Greater than | `greaterThan(5, 3)` |
| `>=` | Greater or equal | `greaterThanOrEqual(5, 3)` |

### Logical Operations

Logical operations combine boolean values.

| Operation | Description | Example |
|-----------|-------------|---------|
| `and` | Logical AND | `and(true, false)` |
| `or` | Logical OR | `or(true, false)` |
| `not` | Logical NOT | `not(true)` |
| `implies` | Implication | `implies(true, false)` |

### Type Operations

Type operations check and cast types at runtime.

| Operation | Description | Example |
|-----------|-------------|---------|
| `oclIsTypeOf(Type)` | Exact type match | `oclIsTypeOf(obj, String.self)` |
| `oclIsKindOf(Type)` | Instance of type or subtype | `oclIsKindOf(obj, EClass.self)` |
| `oclAsType(Type)` | Cast to type | `oclAsType(obj, EClass.self)` |
| `oclTypeName()` | Get the type name | `oclTypeName(obj)` |
| `oclIsUndefined()` | Is null/undefined | `oclIsUndefined(obj)` |

## Example Patterns

### Filtering Model Elements

```swift
import ECore
import OCL

// Find all abstract classes in a package
let abstractClasses = try OCL.select(package.eClassifiers) { classifier in
    guard let eClass = classifier as? EClass else {
        return false
    }
    return eClass.abstract
}

// Find classes with specific attributes
let classesWithId = try OCL.select(package.eClassifiers) { classifier in
    guard let eClass = classifier as? EClass else {
        return false
    }
    return try OCL.exists(eClass.eAttributes) { $0.isID }
}
```

### Computing Derived Values

```swift
import ECore
import OCL

// Count total attributes across all classes
let totalAttributes = try OCL.collect(package.eClassifiers) { classifier in
    guard let eClass = classifier as? EClass else {
        return 0
    }
    return try OCL.size(eClass.eAttributes)
}.reduce(0, +)

// Collect all attribute names
let allAttributeNames = try OCL.collect(package.eClassifiers) { classifier in
    guard let eClass = classifier as? EClass else {
        return []
    }
    return try OCL.collect(eClass.eAttributes) { $0.name }
}.flatMap { $0 }
```

### Validation Constraints

```swift
import ECore
import OCL

// Check that all classes have unique names
let hasUniqueNames = try OCL.forAll(package.eClassifiers) { classifier1 in
    try OCL.one(package.eClassifiers) { classifier2 in
        classifier1.name == classifier2.name
    }
}

// Verify all references have opposites where required
let validReferences = try OCL.forAll(package.eClassifiers) { classifier in
    guard let eClass = classifier as? EClass else {
        return true
    }
    return try OCL.forAll(eClass.eReferences) { reference in
        !reference.eOpposite.oclIsUndefined() || !reference.containment
    }
}
```

## Error Handling

OCL operations throw ``OCLError`` when they encounter invalid
conditions:

```swift
do {
    let result = try OCL.first([])  // Empty collection
} catch OCLError.invalidOperation(let message) {
    print("Invalid operation: \(message)")
} catch OCLError.typeError(let message) {
    print("Type error: \(message)")
} catch {
    print("Unexpected error: \(error)")
}
```

## Best Practices

1. **Use meaningful predicates**: Write clear, readable conditions
   in select/reject operations

2. **Check for null**: Use `oclIsUndefined()` before navigating
   potentially null references

3. **Prefer declarative operations**: Use select/collect/forAll
   instead of manual iteration

4. **Handle errors appropriately**: Catch ``OCLError`` and provide
   meaningful error messages

5. **Keep expressions simple**: Break complex queries into smaller,
   reusable operations

## OCL vs AQL

OCL and AQL are closely related:

- **AQL** provides simplified syntax (`col->select(e | e > 5)`)
- **OCL** uses function-based syntax (`select(col) { $0 > 5 }`)
- Both provide the same semantic operations
- AQL is preferred for template-based code generation (MTL)
- OCL is preferred for programmatic model querying

## Next Steps

- Explore <doc:GettingStarted> for practical examples
- See ``OCLUnaryMethod``, ``OCLBinaryMethod``, and ``OCLTernaryMethod``
  for complete operation listings
- Review the OCL source files for detailed function documentation

## See Also

- [OMG OCL (Object Constraint Language)](https://www.omg.org/spec/OCL/)
- [OMG OCL 2.4 Specification](https://www.omg.org/spec/OCL/2.4/PDF)
- [The Ultimate OCL Tutorial](https://modeling-languages.com/ocl-tutorial/)
- [Eclipse OCL](https://projects.eclipse.org/projects/modeling.mdt.ocl)
