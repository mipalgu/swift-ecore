# UML Class Models as Metamodels

Convert UML class models into Ecore metamodels, as Eclipse UML2 converts them, and use them
as the metamodels of instance documents.

## Overview

A UML class model describes packages, classes, attributes, associations and operations, just
as an Ecore metamodel does. ``UMLToEcore`` converts the packages of a UML model that
``UMLFormat`` has read into native ``EPackage`` values, following the mapping and the options
of the Eclipse UML2 converter (`UMLUtil.UML2EcoreConverter`). The converted packages are
registered with the resource set, so instance documents can be read, validated and queried
with them like with any other metamodel.

```swift
let resourceSet = ResourceSet()
let model = try await UMLFormat.read(url: modelURL, resourceSet: resourceSet)
let metamodel = try await UMLToEcore.convert(model.resource)
for diagnostic in metamodel.diagnostics where diagnostic.severity != .information {
    print(diagnostic.message)
}
let instances = try await XMIParser(resourceSet: resourceSet).parse(instanceURL)
```

To read a `.uml` document directly in the role of a metamodel, use
``UMLToEcore/read(url:resourceSet:options:modelResourceSet:)``: the model is read into a
resource set of its own, and the metamodel takes the URI of the document in the given
resource set. ``UMLToEcore/translate(_:options:resourceSet:)`` returns the text of the Ecore
document without loading it.

``ModelIO`` converts a UML class model in the same way wherever it is given as a metamodel,
because the handler of the UML format is a ``MetamodelConvertingModelFormatHandler``:

```swift
let resourceSet = ResourceSet()
let model = try await ModelIO.load(url: instanceURL, resourceSet: resourceSet, metamodels: [classModelURL])
```

### Mapping

| UML | Ecore |
|---|---|
| Package, Model, Profile | `EPackage`; nested packages become subpackages |
| Class, structured DataType | `EClass` |
| Interface | abstract interface `EClass` |
| Enumeration, EnumerationLiteral | `EEnum`, `EEnumLiteral` |
| PrimitiveType | `EDataType` whose instance class name is its name |
| Generalization, InterfaceRealization | super types |
| Property typed by a class, data type or interface | `EReference` |
| Property typed by an enumeration or primitive type | `EAttribute` |
| Operation, Parameter | `EOperation`, `EParameter` |
| Template parameter | `ETypeParameter` |
| Comment | GenModel documentation |
| Constraint | invariant |

A reference is a containment if its property is composite or typed by a data type. The other
end of a binary association becomes the opposite of a reference if both ends are owned by
classifiers. Multiplicities, ordering and uniqueness carry over, with the defaults of UML
(exactly one, unordered, unique); a read-only property becomes a feature that cannot be
changed, and `isDerived`, `isID` and default values carry over too. An operation takes its
type and multiplicity from its return parameter.

A package takes its namespace URI from its `URI`. Without one, its namespace prefix is that
of its super package, a dot and its name, and its namespace URI is `http:///` followed by the
prefix, with dots replaced by slashes, and `.ecore`. The primitive types of UML become the
Ecore data types with the same instance classes (`Boolean` becomes `EBoolean`, `Integer` and
`UnlimitedNatural` become `EInt`, `Real` becomes `EDouble` and `String` becomes `EString`),
or the types of the Eclipse UML2 types package if ``UMLToEcore/Options/primitiveTypes`` says
so. The types of the Java, Ecore and XML primitive type libraries of Eclipse UML2 become Ecore
data types, and references to the UML or Ecore metamodels refer to the native metamodels.
Types of other documents are read through the resource set, and their packages are converted
as further root packages.

### The Ecore profile

Where the Ecore profile of Eclipse UML2 is applied, its tagged values refine the metamodel:
`nsURI`, `nsPrefix` and `packageName` of packages; `className`, `dataTypeName`, `enumName`
and `instanceClassName` of classifiers; `attributeName`, `referenceName`, `isID`,
`isTransient`, `isVolatile`, `isUnsettable`, `isResolveProxies` and `keys` of features;
`operationName`, `parameterName` and `enumLiteralName`; `xmlName`, `xmlNamespace`,
`xmlFeatureKind` and `xmlContentKind` as extended metadata; `visibility` as suppressed
GenModel visibility; `annotations` as annotations; and `bounds` of type parameters. A renamed
element records its UML name in an annotation (see ``UMLToEcore/Syntax/originalNameKey``). A
classifier with the `EGenericType` stereotype stands for the template it binds, with the
actual parameters as type arguments.

### Options

Every option of ``UMLToEcore/Options`` takes one of the choices of ``UMLToEcore/Choice``:
ignore, report, discard or process. The default options (``UMLToEcore/Options/standard``)
are those of the Eclipse UML2 "Convert to Ecore" dialog with three exceptions: names are kept
as they are, invariants become OCL constraints of their classifiers, and OCL expressions are
recorded for the delegates of Eclipse OCL Pivot (`http://www.eclipse.org/emf/2002/Ecore/OCL/Pivot`).
``UMLToEcore/Options/eclipseDialog`` and ``UMLToEcore/Options/eclipseAPI`` reproduce the dialog
and the programmatic defaults of Eclipse UML2.

With the default options:

- derived features and derived unions are transient and volatile, derived unions read-only
  with a `union` annotation;
- redefinitions and subsets are recorded in `redefines` and `subsets` annotations;
- features and operations that duplicate inherited ones are moved into a `duplicates`
  annotation of their class, and made to conform to the inherited ones;
- super classes are ordered by the number of their features;
- comments become GenModel documentation, as do the specifications of constraints;
- a named constraint of a classifier becomes a constraint in the `constraints` detail of an
  Ecore annotation, and its OCL body a detail of an annotation whose source is the OCL delegate
  URI, which the package lists as its validation delegate;
- OCL operation bodies and default value expressions become annotations for the invocation
  and setting delegates;
- properties without a type are reported as errors;
- navigable association ends that their associations own are reported, as Eclipse UML2 does
  not convert them (see ``UMLToEcore/Options/navigableAssociationOwnedEnds``).

What an option does or finds is reported as a diagnostic with one of the codes of
``UMLToEcore/Diagnostic``. The options `DUPLICATE_FEATURE_INHERITANCE` and
`DUPLICATE_OPERATION_INHERITANCE` are only implemented for the choice to ignore.

### Limits

The contents of the `duplicates` annotations are kept by the Ecore loader as generic objects
rather than as native features and operations. The converted elements keep the `xmi:id` of
their UML elements, which the Ecore writer repeats. A template binding of a classifier
without the `EGenericType` stereotype is converted as a class without type arguments, and
the `lowerBound` and `upperBound` tagged values of the `EGenericType` stereotype are not
applied. Classifiers that are not in a package cannot be converted.

## Topics

### Conversion

- ``UMLToEcore``
- ``UMLToEcore/Options``
- ``UMLToEcore/Choice``
- ``UMLToEcore/PrimitiveTypeMapping``
- ``UMLToEcore/Diagnostic``
- ``UMLToEcore/Syntax``
- ``UMLToEcoreError``
