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
- **Any format**: ``ModelIO`` loads and saves XMI, JSON, Ecore, EMOF, UML, KM3, Emfatic,
  Xcore, OCLinEcore and ASDL documents and reads Langium, Xtext and SDF3 grammars, detecting
  the format with ``ModelFormat``, and further formats registered with ``ModelFormatRegistry``
- **Textual metamodels**: ``KM3Reader``, ``EmfaticReader`` and ``XcoreReader`` and their
  writers read and write the textual metamodel notations of ATL, Emfatic and Xcore, with
  tokens for editors
- **Grammar importers**: ``ASDLReader``, ``LangiumReader``, ``XtextReader`` and ``SDF3Reader``
  derive metamodels from ASDL descriptions, Langium and Xtext grammars and SDF3 syntax
  definitions, and ``ASDLWriter`` writes ASDL
- **OCL constraints**: ``OCLinEcoreReader`` and ``OCLinEcoreWriter`` read and write metamodels
  with embedded OCL, and ``ModelIO/applyCompleteOCL(at:to:in:options:)`` adds the constraints
  of a Complete OCL document to loaded metamodels
- **Validation**: ``ModelValidator`` checks models and ``EcoreValidator`` checks metamodels
- **Incremental evaluation**: Change observers, dependency records and their reverse index
  let query and transformation engines redo only what changes affect; see
  <doc:IncrementalEvaluation>

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
- <doc:IncrementalEvaluation>

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
- ``ModelFormatRegistry``
- ``ModelFormatHandler``
- ``WritableModelFormatHandler``
- ``MetamodelConvertingModelFormatHandler``
- ``ModelFormatReadRequest``
- ``ModelFormatReadResult``
- ``ModelFormatRole``
- ``ModelFormatPriority``
- ``BundledMetamodelCache``
- ``BundledMetamodelError``
- ``BundledResources``
- ``ResourceBundleName``

### KM3

- ``KM3Reader``
- ``KM3ReadOptions``
- ``KM3ParseResult``
- ``KM3Writer``
- ``KM3Syntax``
- ``KM3PrimitiveTypeMapping``
- ``KM3PrimitiveTypes``
- ``KM3PrimitiveType``
- ``KM3Format``
- ``KM3Keyword``
- ``KM3Symbol``
- ``KM3Directive``
- ``KM3OutlineKind``
- ``KM3DiagnosticCode``

### Emfatic and Xcore

- ``EmfaticReader``
- ``EmfaticWriter``
- ``EmfaticSyntax``
- ``EmfaticLanguage``
- ``EmfaticParseResult``
- ``EmfaticDiagnosticCode``
- ``XcoreReader``
- ``XcoreWriter``
- ``XcoreSyntax``
- ``XcoreLanguage``
- ``XcoreParseResult``
- ``XcoreDiagnosticCode``

### Grammar Importers

- ``ASDLReader``
- ``ASDLWriter``
- ``ASDLSyntax``
- ``ASDLParseResult``
- ``ASDLImportOptions``
- ``ASDLEnumerationStyle``
- ``ASDLDiagnosticCode``
- ``ASDLOutlineKind``
- ``LangiumReader``
- ``LangiumSyntax``
- ``LangiumParseResult``
- ``LangiumImportOptions``
- ``LangiumTypeMode``
- ``LangiumDiagnosticCode``
- ``LangiumOutlineKind``
- ``XtextReader``
- ``XtextSyntax``
- ``XtextParseResult``
- ``XtextImportOptions``
- ``XtextDiagnosticCode``
- ``XtextOutlineKind``
- ``SDF3Reader``
- ``SDF3Syntax``
- ``SDF3ParseResult``
- ``SDF3ImportOptions``
- ``SDF3DiagnosticCode``
- ``SDF3OutlineKind``

### OCLinEcore and Complete OCL

- ``OCLinEcoreReader``
- ``OCLinEcoreWriter``
- ``OCLinEcoreSyntax``
- ``OCLinEcoreParseResult``
- ``OCLinEcoreImport``
- ``OCLinEcoreOutlineKind``
- ``CompleteOCLReader``
- ``CompleteOCLApplier``
- ``CompleteOCLApplication``
- ``CompleteOCLParseResult``
- ``CompleteOCLDocument``
- ``CompleteOCLSyntax``
- ``CompleteOCLOutlineKind``
- ``CompleteOCLImport``
- ``CompleteOCLPackageDeclaration``
- ``CompleteOCLClassifierContext``
- ``CompleteOCLOperationContext``
- ``CompleteOCLPropertyContext``
- ``CompleteOCLConstraint``
- ``CompleteOCLDefinition``
- ``CompleteOCLParameter``
- ``OCLConstraintAnnotations``
- ``OCLConstraintText``
- ``OCLAnnotation``
- ``OCLTypeResolver``
- ``OCLResolvedType``

### XMI Dialects, EMOF and UML

- <doc:DialectsEMOFAndUML>
- ``XMIVersion``
- ``XMITypeAttribute``
- ``EMOFFormat``
- ``EMOFSyntax``
- ``EMOFError``
- ``UMLFormat``
- ``UMLMetamodel``
- ``UMLNamespaces``
- <doc:UMLClassModelsAsMetamodels>
- ``UMLToEcore``
- ``UMLToEcoreError``
- ``ModelDocumentReadResult``
- ``ModelDocumentWriteResult``
- ``ModelDocumentDiagnostic``

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
