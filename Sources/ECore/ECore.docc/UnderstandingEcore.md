# Understanding Ecore

Learn the fundamental concepts of the Ecore metamodelling framework.

## Overview

Ecore is the metamodel at the heart of the Eclipse Modeling
Framework ([EMF](https://eclipse.dev/emf/)). It provides
a way to define the structure of models - what classes exist, what attributes they have,
and how they relate to each other.

Ecore is an implementation of the OMG MOF (Meta Object Facility)
([OMG MOF](https://www.omg.org/mof/)) standard, which defines
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
var package = EPackage(
    name: "company",
    nsURI: "http://example.com/company",
    nsPrefix: "company"
)
```

Key properties:
- **name**: The package name (used in code generation)
- **nsURI**: Namespace URI (unique identifier for the metamodel)
- **nsPrefix**: XML namespace prefix for serialisation

Metamodel elements are values, so a class, feature or literal that is added to its container
is a copy: complete an element, or change it through its container, before relying on the
container's copy.

### EClass

``EClass`` defines a class in your metamodel. Classes can have attributes, references,
and operations. They support single and multiple inheritance.

```swift
var employeeClass = EClass(name: "Employee")
employeeClass.isAbstract = false
```

Key properties:
- **isAbstract**: Abstract classes cannot be instantiated directly
- **eSuperTypes**: Parent classes for inheritance
- **eStructuralFeatures**: Attributes and references

### EAttribute

``EAttribute`` defines a data-valued property of a class. Attributes hold primitive
values like strings, integers, or booleans.

```swift
var nameAttr = EAttribute(name: "name", eType: EDataType(name: "EString"))
nameAttr.lowerBound = 1  // Required
nameAttr.upperBound = 1  // Single-valued

employeeClass.eStructuralFeatures.append(nameAttr)
```

Key properties:
- **eType**: The data type (EString, EInt, EBoolean, etc.)
- **lowerBound**: Minimum cardinality (0 = optional, 1 = required)
- **upperBound**: Maximum cardinality (1 = single, -1 = unbounded)
- **defaultValueLiteral**: The default value, as text, of an attribute that is not set

### EReference

``EReference`` defines a relationship between classes. References can be containment
(parent-child) or non-containment (associations).

```swift
var departmentRef = EReference(name: "department", eType: departmentClass)
departmentRef.containment = false
departmentRef.lowerBound = 0
departmentRef.upperBound = 1

employeeClass.eStructuralFeatures.append(departmentRef)
package.eClassifiers.append(employeeClass)
```

Key properties:
- **containment**: If true, the referenced object is contained (owned) by this object
- **opposite**: The identifier of the bidirectional reference partner
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
var statusEnum = EEnum(name: "EmploymentStatus")
statusEnum.literals = [
    EEnumLiteral(name: "ACTIVE", value: 0),
    EEnumLiteral(name: "ON_LEAVE", value: 1),
    EEnumLiteral(name: "TERMINATED", value: 2)
]
```

### EOperation and EParameter

``EOperation`` declares an operation of a class, with its ``EParameter`` values, return type,
bounds and exceptions. Operations and parameters are native values: they can be read
reflectively, navigated through their containers, addressed by name-based fragments such as
`#//Book/borrow/days`, and written back to `.ecore` documents.

### Generic Types

Classifiers and operations can declare type parameters (``ETypeParameter``), and the types of
features, operations, parameters, supertypes and exceptions can be generic types
(``EGenericType``) with type arguments, bounds and wildcards. ``EGenericType/eRawType`` is the
classifier that a generic type erases to.

## Containment and References

Understanding containment is crucial in ECore:

### Containment References

- Create a parent-child relationship
- A contained object can only have one container
- Deleting the container deletes all contained objects
- Used for structural composition (e.g., Company contains Departments)

```swift
var employeesRef = EReference(name: "employees", eType: employeeClass)
employeesRef.containment = true
employeesRef.upperBound = -1  // Unbounded
```

### Non-Containment References

- Create associations between objects
- Objects can be referenced from multiple places
- Deleting the referencing object doesn't delete the referenced object
- Used for associations (e.g., Employee has a manager)

```swift
let managerRef = EReference(name: "manager", eType: employeeClass, containment: false)
```

## Bidirectional References

References can be paired with an opposite reference, which each names by its identifier,
for automatic synchronisation. The reference that leads back to a containing object is
marked as its `container`:

```swift
// In Department: the employees it contains
var employeesRef = EReference(name: "employees", eType: employeeClass)
employeesRef.containment = true
employeesRef.upperBound = -1

// In Employee: the department that contains it
var departmentRef = EReference(name: "department", eType: departmentClass)
departmentRef.container = true

// Link them as opposites
employeesRef.opposite = departmentRef.id
departmentRef.opposite = employeesRef.id
```

When you add an employee to a department's employees through
``Resource/eSet(objectId:feature:value:)``, the resource sets the employee's department
reference, and vice versa.

## Inheritance

ECore supports multiple inheritance through ``EClass/eSuperTypes``:

```swift
let personClass = EClass(name: "Person")
// Add name, age attributes...

var employeeClass = EClass(name: "Employee")
employeeClass.eSuperTypes = [personClass]
// Employee inherits all features from Person
```

## Annotations

Every model element can carry ``EAnnotation`` values: packages, classifiers, features,
operations, parameters, enumeration literals and annotations themselves. An annotation has a
`source` URI, `details` (key and value entries, kept in document order), `references` to
other elements, in the same document or in others, and `contents`.
``EModelElement/getEAnnotation(source:)`` finds an annotation by its source, and
``EModelElement/getEAnnotationDetail(source:key:)`` reads a single detail. The common sources
and keys are listed in ``AnnotationSource``:

```swift
let package = try await EPackage(url: libraryURL)
let documentation = package.getEClass("Book")?.getEAnnotationDetail(
    source: AnnotationSource.genModel, key: AnnotationSource.GenModelKey.documentation)
```

## The EObject Protocol

All model objects conform to ``EObject``, which provides:

- **id**: The identifier by which references and resources refer to the object
- **eClass**: The metaclass of the object
- **eGet(_:)**: Get a feature value
- **eSet(_:_:)**: Set a feature value
- **eIsSet(_:)** and **eUnset(_:)**: Check whether a feature is set, and unset it

Objects are values that refer to each other by identifier. A ``Resource`` holds the objects
of a model: ``Resource/eContainer(of:scope:)`` finds the container of an object, and
``Resource/eSet(objectId:feature:value:)`` changes a feature and keeps opposite references
in step.

## The Ecore Metamodel

Ecore describes itself. ``EcorePackage`` provides the Ecore metamodel as an ``EPackage``,
with the namespace URI `http://www.eclipse.org/emf/2002/Ecore`, and every native metamodel
element reports its metaclass from that package through `eClass`. The meta features, such as
`eClassifiers`, `eStructuralFeatures`, `eAllSuperTypes`, `eType`, `eOpposite`, the bounds and
the flags, can be read and written reflectively, and the containers (`ePackage`,
`eContainingClass`, `eEnum`, `eSuperPackage`) can be navigated like those of any other model.
Tools that work on models, such as queries and transformations, can therefore work on
metamodels too:

```swift
let ecore = EcorePackage.instance
let attributeClass = EcorePackage.metaClass(.eAttribute)
let engine = ECoreExecutionEngine(models: [:])
await engine.registerResource(resource, alias: "MM")  // a resource that holds an EPackage
let classes = try await engine.navigate(from: package, property: "eClassifiers")
```

## Resources and Serialisation

Models are persisted through ``Resource`` objects:

- A Resource contains model objects
- Resources belong to a ``ResourceSet`` for cross-reference resolution
- XMI and JSON serialisation formats are supported

### Fragments

A reference to an object names its resource and a fragment that identifies the object within
it, as in the Eclipse Modeling Framework:

- **Name-based fragments** address metamodel elements by name: `#/` is the package,
  `#//Book` a class, `#//Book/title` a feature, `#//sub/Class` a class of a subpackage and
  `#//Colour/RED` an enumeration literal. ``FragmentNavigator`` resolves them.
- **Positional fragments** address objects of a model by their containment: the only root of
  a resource is `#/` and its contents `#//@feature.index`, whereas root `n` of a resource
  with several roots is `#/n` and its contents `#/n/@feature.index` (``PositionalFragments``).
- **Identifier fragments**, which do not start with `/`, name the object with that `xmi:id`
  or, failing that, with that value of its class's ID attribute.

### Proxies and Containers

A reference to an object of another document is held as a ``ResourceProxy`` until it is
resolved. ``Resource/resolveProxies()`` and ``ResourceSet/resolveAllProxies()`` load the
target documents on demand and replace proxies by direct references, and
``Resource/eGetResolving(objectId:feature:)`` resolves the value of a single feature.

The container of an object can be looked up even when the object belongs to another
resource; <doc:Compatibility> describes how the scope of that lookup is chosen.

### Conversion Diagnostics

Whatever a parser or serialiser cannot represent, such as an untyped class, a reference
without a fragment, a dropped value or an unresolved reference, is reported as a
``ConversionWarning`` in ``ConversionDiagnostics`` instead of being lost silently.

## Next Steps

- <doc:GettingStarted> - Practical examples
- ``EClass`` - API reference for class definition
- ``Resource`` - Working with model persistence

## See Also

- [Eclipse Modeling Framework (EMF)](https://eclipse.dev/emf/)
- [OMG MOF (Meta Object Facility)](https://www.omg.org/mof/)
- [OMG XMI (XML Metadata Interchange)](https://www.omg.org/spec/XMI/)
