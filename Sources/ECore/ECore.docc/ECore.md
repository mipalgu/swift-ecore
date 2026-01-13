# ``ECore``

@Metadata {
    @DisplayName("ECore")
}

A pure Swift implementation of [EMF/Ecore](https://eclipse.dev/emf/) for Model-Driven Engineering.

## Overview

ECore provides a complete implementation of the
[Eclipse Modeling Framework (EMF)](https://eclipse.dev/emf/) Ecore
metamodelling system in pure Swift. Use it to define metamodels, create model instances,
and serialise models to XMI or JSON format.

The framework follows the EMF/Ecore specification based on the
[OMG MOF (Meta Object Facility)](https://www.omg.org/mof/) standard, providing familiar
concepts for developers experienced with Eclipse-based modelling tools whilst offering
a modern, type-safe Swift API.

### Key Features

- **Metamodelling**: Define metamodels using ``EClass``, ``EAttribute``, ``EReference``,
  and ``EPackage``
- **Dynamic instances**: Create model instances at runtime with ``DynamicEObject``
- **XMI serialisation**: Load and save models in XMI format using ``XMIParser``
- **JSON serialisation**: Alternative JSON format with ``JSONParser``
- **Cross-resource references**: Support for models spanning multiple files via
  ``ResourceSet``
- **Command pattern**: Undoable operations with ``EMFCommand`` and ``CommandStack``

### Quick Example

```swift
import ECore

// Load a metamodel from XMI
let parser = XMIParser()
let resource = try await parser.parse(URL(fileURLWithPath: "Company.ecore"))
let package = resource.rootObjects.first as! EPackage

// Find an EClass
let employeeClass = package.eClassifiers.first { $0.name == "Employee" } as! EClass

// Create a dynamic instance
let employee = DynamicEObject(eClass: employeeClass)
employee.eSet("name", value: "Alice")
employee.eSet("salary", value: 50000)

// Save to a new resource
let outputResource = Resource()
outputResource.add(employee)
let serialiser = XMISerializer()
try serialiser.save(resource: outputResource, to: URL(fileURLWithPath: "employees.xmi"))
```

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:UnderstandingEcore>

### Core Types

- ``EObject``
- ``DynamicEObject``
- ``EClass``
- ``EPackage``

### Structural Features

- ``EStructuralFeature``
- ``EAttribute``
- ``EReference``

### Classifiers

- ``EClassifier``
- ``EDataType``
- ``EEnum``
- ``EEnumLiteral``

### Resources and Serialisation

- ``Resource``
- ``ResourceSet``
- ``XMIParser``
- ``XMISerializer``
- ``JSONParser``
- ``JSONSerializer``

### Commands and Editing

- ``EMFCommand``
- ``CommandStack``
- ``BasicEditingDomain``

### Query and Execution

- ``ECoreExecutionEngine``
- ``ECoreQuery``
- ``IModel``

### Supporting Types

- ``EFactory``
- ``EModelElement``
- ``ENamedElement``
- ``ETypedElement``

### References

- [Eclipse Modeling Framework (EMF)](https://eclipse.dev/emf/)
- [OMG MOF (Meta Object Facility)](https://www.omg.org/mof/)
- [OMG XMI (XML Metadata Interchange)](https://www.omg.org/spec/XMI/)
- [OMG OCL (Object Constraint Language)](https://www.omg.org/spec/OCL/)
