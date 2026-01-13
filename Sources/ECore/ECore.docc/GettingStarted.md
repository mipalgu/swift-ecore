# Getting Started with ECore

Learn how to add ECore to your project and create your first metamodel.

## Overview

This guide walks you through adding ECore to your Swift project and demonstrates
the fundamental concepts of metamodelling with ECore.

## Adding ECore to Your Project

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

## Loading a Metamodel

ECore metamodels are typically stored in `.ecore` files using XMI format. Load
a metamodel using ``XMIParser``:

```swift
import ECore

let parser = XMIParser()
let resource = try await parser.parse(URL(fileURLWithPath: "Company.ecore"))

// Access the root package
guard let package = resource.rootObjects.first as? EPackage else {
    fatalError("No package found in metamodel")
}

print("Loaded package: \(package.name)")
```

## Exploring a Metamodel

Once loaded, explore the metamodel structure:

```swift
// List all classifiers (EClass, EDataType, EEnum)
for classifier in package.eClassifiers {
    print("Classifier: \(classifier.name)")

    if let eClass = classifier as? EClass {
        // List structural features
        for feature in eClass.eStructuralFeatures {
            if let attr = feature as? EAttribute {
                print("  Attribute: \(attr.name) : \(attr.eType?.name ?? "unknown")")
            } else if let ref = feature as? EReference {
                print("  Reference: \(ref.name) -> \(ref.eType?.name ?? "unknown")")
            }
        }
    }
}
```

## Creating Model Instances

Create dynamic instances of metamodel classes using ``DynamicEObject``:

```swift
// Find the Employee class
guard let employeeClass = package.eClassifiers.first(where: { $0.name == "Employee" }) as? EClass else {
    fatalError("Employee class not found")
}

// Create an instance
let employee = DynamicEObject(eClass: employeeClass)

// Set attribute values
employee.eSet("name", value: "Alice Smith")
employee.eSet("employeeId", value: 12345)
employee.eSet("department", value: "Engineering")

// Read values back
let name: String? = employee.eGet("name") as? String
print("Employee name: \(name ?? "unknown")")
```

## Working with References

ECore supports both single-valued and multi-valued references:

```swift
// Create a company and employees
let companyClass = package.eClassifiers.first { $0.name == "Company" } as! EClass
let company = DynamicEObject(eClass: companyClass)
company.eSet("name", value: "Acme Corp")

// Add employees (assuming 'employees' is a multi-valued containment reference)
let alice = DynamicEObject(eClass: employeeClass)
alice.eSet("name", value: "Alice")

let bob = DynamicEObject(eClass: employeeClass)
bob.eSet("name", value: "Bob")

// Get the employees reference
if let employeesRef = companyClass.eStructuralFeatures.first(where: { $0.name == "employees" }) as? EReference {
    company.eAdd(employeesRef, value: alice)
    company.eAdd(employeesRef, value: bob)
}
```

## Saving Models

Save model instances to XMI format:

```swift
// Create a resource and add the root object
let outputResource = Resource(uri: "file:///path/to/output.xmi")
outputResource.add(company)

// Serialise to XMI
let serialiser = XMISerializer()
try serialiser.save(resource: outputResource, to: URL(fileURLWithPath: "output.xmi"))
```

## Using ResourceSet for Cross-References

When working with models that reference objects in other files, use ``ResourceSet``:

```swift
let resourceSet = ResourceSet()

// Load multiple resources
let metamodelResource = try await resourceSet.loadResource(from: URL(fileURLWithPath: "Company.ecore"))
let modelResource = try await resourceSet.loadResource(from: URL(fileURLWithPath: "company-data.xmi"))

// Cross-resource references are automatically resolved
```

## Next Steps

- <doc:UnderstandingEcore> - Learn about the core concepts
- ``EClass`` - Defining classes in your metamodel
- ``EReference`` - Modelling relationships between classes
- ``Resource`` - Managing model persistence
