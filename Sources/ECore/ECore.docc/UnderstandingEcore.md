# Understanding Ecore

Learn the fundamental concepts of the Ecore metamodelling framework.

## Overview

Ecore is the metamodel at the heart of the
[Eclipse Modeling Framework (EMF)](https://eclipse.dev/emf/). It provides
a way to define the structure of models - what classes exist, what attributes they have,
and how they relate to each other.

Ecore is an implementation of the
[OMG MOF (Meta Object Facility)](https://www.omg.org/mof/) standard, which defines
the metamodelling architecture used in Model-Driven Engineering.

This article explains the core concepts you need to understand when working with ECore.

## The Metamodel Hierarchy

Ecore follows a layered architecture where models are instances of metamodels:

```
M3: Ecore (the metamodel of metamodels)
     |
M2: Your Metamodel (e.g., Company.ecore)
     |
M1: Your Model (e.g., acme-corp.xmi)
     |
M0: Runtime Objects (actual data)
```

When you define a metamodel in ECore, you're creating M2-level concepts (like "Employee"
or "Department"). When you create instances, you're working at M1 (actual employees
and departments).

## Core Metamodel Elements

### EPackage

``EPackage`` is the top-level container for a metamodel. It groups related classifiers
and can contain subpackages for organisation.

```swift
let package = EPackage(
    name: "company",
    nsURI: "http://example.com/company",
    nsPrefix: "company"
)
```

Key properties:
- **name**: The package name (used in code generation)
- **nsURI**: Namespace URI (unique identifier for the metamodel)
- **nsPrefix**: XML namespace prefix for serialisation

### EClass

``EClass`` defines a class in your metamodel. Classes can have attributes, references,
and operations. They support single and multiple inheritance.

```swift
let employeeClass = EClass(name: "Employee")
employeeClass.isAbstract = false

// Add to package
package.eClassifiers.append(employeeClass)
```

Key properties:
- **isAbstract**: Abstract classes cannot be instantiated directly
- **eSuperTypes**: Parent classes for inheritance
- **eStructuralFeatures**: Attributes and references

### EAttribute

``EAttribute`` defines a data-valued property of a class. Attributes hold primitive
values like strings, integers, or booleans.

```swift
let nameAttr = EAttribute(name: "name", eType: EcorePackage.eString)
nameAttr.lowerBound = 1  // Required
nameAttr.upperBound = 1  // Single-valued

employeeClass.eStructuralFeatures.append(nameAttr)
```

Key properties:
- **eType**: The data type (EString, EInt, EBoolean, etc.)
- **lowerBound**: Minimum cardinality (0 = optional, 1 = required)
- **upperBound**: Maximum cardinality (1 = single, -1 = unbounded)
- **defaultValue**: Default value for new instances

### EReference

``EReference`` defines a relationship between classes. References can be containment
(parent-child) or non-containment (associations).

```swift
let departmentRef = EReference(name: "department", eType: departmentClass)
departmentRef.containment = false
departmentRef.lowerBound = 0
departmentRef.upperBound = 1

employeeClass.eStructuralFeatures.append(departmentRef)
```

Key properties:
- **containment**: If true, the referenced object is contained (owned) by this object
- **eOpposite**: Bidirectional reference partner
- **resolveProxies**: Whether to resolve cross-resource references

### EDataType

``EDataType`` represents primitive or external types. ECore provides built-in types:

| Type | Swift Equivalent |
|------|------------------|
| EString | String |
| EInt | Int |
| EBoolean | Bool |
| EDouble | Double |
| EFloat | Float |
| EDate | Date |

### EEnum

``EEnum`` defines an enumeration type with literal values:

```swift
let statusEnum = EEnum(name: "EmploymentStatus")
statusEnum.eLiterals = [
    EEnumLiteral(name: "ACTIVE", value: 0),
    EEnumLiteral(name: "ON_LEAVE", value: 1),
    EEnumLiteral(name: "TERMINATED", value: 2)
]
```

## Containment and References

Understanding containment is crucial in ECore:

### Containment References

- Create a parent-child relationship
- A contained object can only have one container
- Deleting the container deletes all contained objects
- Used for structural composition (e.g., Company contains Departments)

```swift
let employeesRef = EReference(name: "employees", eType: employeeClass)
employeesRef.containment = true
employeesRef.upperBound = -1  // Unbounded
```

### Non-Containment References

- Create associations between objects
- Objects can be referenced from multiple places
- Deleting the referencing object doesn't delete the referenced object
- Used for associations (e.g., Employee has a manager)

```swift
let managerRef = EReference(name: "manager", eType: employeeClass)
managerRef.containment = false
```

## Bidirectional References

References can be paired with an opposite reference for automatic synchronisation:

```swift
// In Department: employees reference
let employeesRef = EReference(name: "employees", eType: employeeClass)
employeesRef.containment = true
employeesRef.upperBound = -1

// In Employee: department reference
let departmentRef = EReference(name: "department", eType: departmentClass)
departmentRef.containment = false

// Link them as opposites
employeesRef.eOpposite = departmentRef
departmentRef.eOpposite = employeesRef
```

When you add an employee to a department's employees list, the employee's department
reference is automatically set, and vice versa.

## Inheritance

ECore supports multiple inheritance through ``EClass/eSuperTypes``:

```swift
let personClass = EClass(name: "Person")
// Add name, age attributes...

let employeeClass = EClass(name: "Employee")
employeeClass.eSuperTypes = [personClass]
// Employee inherits all features from Person
```

## The EObject Protocol

All model objects conform to ``EObject``, which provides:

- **eClass**: The metaclass of the object
- **eGet(_:)**: Get a feature value
- **eSet(_:value:)**: Set a feature value
- **eContainer**: The containing object
- **eResource**: The resource containing this object

## Resources and Serialisation

Models are persisted through ``Resource`` objects:

- A Resource contains model objects
- Resources belong to a ``ResourceSet`` for cross-reference resolution
- XMI and JSON serialisation formats are supported

## Next Steps

- <doc:GettingStarted> - Practical examples
- ``EClass`` - API reference for class definition
- ``Resource`` - Working with model persistence

## See Also

- [Eclipse Modeling Framework (EMF)](https://eclipse.dev/emf/) - The reference EMF implementation
- [OMG MOF (Meta Object Facility)](https://www.omg.org/mof/) - The metamodelling standard
- [OMG XMI (XML Metadata Interchange)](https://www.omg.org/spec/XMI/) - The serialisation format
