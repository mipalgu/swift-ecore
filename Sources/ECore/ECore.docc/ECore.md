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
- **XMI serialisation**: Load and save models in XMI format using ``XMIParser`` and
  ``XMISerializer``
- **JSON serialisation**: Alternative JSON format with ``JSONParser``, which builds objects
  from the metamodels registered with a ``ResourceSet`` and resolves `$ref` references
- **Cross-resource references**: Support for models spanning multiple files via
  ``ResourceSet``
- **Command pattern**: Undoable operations with ``EMFCommand`` and ``CommandStack``
- **Reflective metamodel**: The Ecore metamodel itself as ``EcorePackage``, so metamodels can
  be navigated and edited like any other model
- **Faithful Ecore documents**: Operations, generic types and annotations are kept, and
  documents can be written in the layout of the Eclipse Modeling Framework
- **Any format**: ``ModelIO`` loads and saves XMI, JSON and Ecore documents, detecting the
  format with ``ModelFormat``
- **Validation**: ``ModelValidator`` checks models and ``EcoreValidator`` checks metamodels

### Interoperability

Models and metamodels are read and written as the Eclipse Modeling Framework reads and writes
them, including its fragments, date forms and multiplicity rules, and JSON metamodels follow
the emfjson conventions. The tests also cover example models of
[emf4cpp](https://github.com/catedrasaes-umu/emf4cpp) and
[pyecore](https://github.com/pyecore/pyecore). <doc:Compatibility> describes how behaviour
has changed since version 0.6.

The swift-ecore package also provides the OCL library for constraints and queries, the
GenModel library for generator models (`.genmodel`) and the ECoreEdit library for editing
metamodels as values.

### Quick Example

```swift
import ECore
import Foundation

// Load a metamodel from an .ecore file and register it
let resourceSet = ResourceSet()
let package = try await EPackage(url: URL(fileURLWithPath: "Company.ecore"))
await resourceSet.registerMetamodel(package, uri: package.nsURI)

// Find an EClass
guard let employeeClass = package.getEClass("Employee") else {
    fatalError("Employee class not found")
}

// Create a dynamic instance
var employee = DynamicEObject(eClass: employeeClass)
employee.eSet("name", value: "Alice")
employee.eSet("salary", value: 50000)

// Add it to a new resource and save that as XMI
let resource = await resourceSet.createResource(uri: "employees.xmi")
await resource.add(employee)
try await XMISerializer().serialize(resource, to: URL(fileURLWithPath: "employees.xmi"))
```

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:UnderstandingEcore>
- <doc:Compatibility>

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
- ``ContainerLookupScope``
- ``ModellingSemantics``
- ``ModellingSemanticsError``
- ``XMIParser``
- ``XMISerializer``
- ``XMISerializationOptions``
- ``XMIReferenceStyle``
- ``ConversionDiagnostics``
- ``ConversionWarning``
- ``JSONParser``
- ``JSONSerializer``
- ``JSONParseOptions``
- ``JSONFragments``
- ``JSONSyntax``
- ``ModelFormat``
- ``ModelFormatError``
- ``ModelIO``
- ``ModelIOError``
- ``BundledMetamodelCache``
- ``BundledMetamodelError``
- ``BundledResources``
- ``ResourceBundleName``

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

## See Also

- [Eclipse Modeling Framework (EMF)](https://eclipse.dev/emf/)
- [OMG MOF (Meta Object Facility)](https://www.omg.org/mof/)
- [OMG XMI (XML Metadata Interchange)](https://www.omg.org/spec/XMI/)
- [OMG OCL (Object Constraint Language)](https://www.omg.org/spec/OCL/)
