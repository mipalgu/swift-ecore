# XMI Dialects, EMOF and UML

Read documents written by tools other than the Eclipse Modeling Framework, metamodels in
EMOF, and UML models.

## Overview

The Eclipse Modeling Framework (EMF) writes XMI 2.0 in a dialect of its own. Other tools, and
the Object Management Group (OMG) itself, write later versions of XMI, and describe metamodels
in EMOF or model in UML. ECore reads these documents into the same resources and packages as
its native formats, so that they can be inspected, queried, validated and written again.

### OMG XMI

``XMIParser`` reads documents in the XMI namespaces of XMI 2.1, 2.4, 2.4.1 and 2.5.1 as well as
EMF's own (see ``XMIVersion`` for the namespaces). In such a document:

- `xmi:XMI` may hold several root objects, and its `xmi:Documentation` and `xmi:Extension`
  elements are skipped wherever they occur;
- the class of an object may be named by `xmi:type` as well as by `xsi:type`;
- references may be written as identifiers in attributes (`type="_1"`), as child elements with
  an `xmi:idref` (`<type xmi:idref="_1"/>`), or as child elements with an `href` that names an
  identifier in another document (`<type href="types.xmi#_1"/>`);
- values may be written as child elements (`<name>Plant</name>`);
- the OMG UML namespaces are read with the Eclipse UML2 metamodel (see ``UMLNamespaces``).

Documents in EMF's dialect are read exactly as before. ``XMISerializer`` writes the namespace
and `xmi:version` of a later version, and `xmi:type`, when ``XMISerializationOptions/xmiVersion``
and ``XMISerializationOptions/typeAttribute`` ask for them.

Wherever a metamodel gives a feature another XML name in its extended metadata, as Eclipse
UML2 does for `Activity.ownedNode`, which it writes as `node`, the feature is read and written
under that name.

### EMOF

``EMOFFormat`` reads and writes metamodels in EMOF (`.emof`) as EMF does: the names of Ecore
are mapped onto those of EMOF, and whatever EMOF cannot express is kept in an Ecore
`xmi:Extension` (see ``EMOFSyntax`` for the mapping). A read returns native packages, which
are registered with the resource set, and a write returns the text of the document.

```swift
let read = try await EMOFFormat.read(url: emofURL, resourceSet: resourceSet)
let ecoreText = XMISerializer(options: .emf).serialize(read.packages)
let emofText = EMOFFormat.write(read.packages).text
```

CMOF documents, the complete MOF form in which the OMG publishes its own metamodels, are
recognised and refused with ``EMOFError/cmofNotSupported(_:)``.

### UML

The package ships the Eclipse UML2 5.x metamodel unchanged, under the Eclipse Public License
2.0, whose text and a notice of its origin accompany it among the resources of the module.
``UMLFormat`` reads a UML model (`.uml`) as instances of that metamodel, whichever Eclipse UML2
or OMG UML namespace it uses, and writes it in the layout of Eclipse UML2 5.x
(``XMISerializationOptions/uml``), keeping the `xmi:id` of every object.

```swift
let read = try await UMLFormat.read(url: modelURL, resourceSet: resourceSet)
for diagnostic in read.diagnostics { print(diagnostic.message) }
let classes = await read.resource.getAllObjects().filter { $0.eClass.name == "Class" }
```

A stereotype application is read as an instance of its stereotype if the profile is
registered, or is defined in the same document or in the document that the model's
`xsi:schemaLocation` names. Otherwise it is read as an object of a class made up from the
document, and a warning names the namespace of the missing profile.

A UML class model can also serve as a metamodel: ``UMLToEcore`` converts its packages into
native Ecore packages (see <doc:UMLClassModelsAsMetamodels>).

### Through ModelIO

EMOF and UML are formats of ``ModelFormatRegistry``, as ``ModelFormat/emof`` and
``ModelFormat/uml``, so ``ModelIO`` reads and writes them like any other format. An EMOF
document is a metamodel: its packages are registered, and it can be given among the
metamodels of a load. A UML model is written in the layout of Eclipse UML2. A UML class model
given among the metamodels of a load is converted into an Ecore metamodel (see
<doc:UMLClassModelsAsMetamodels>).

Both formats are recognised by their namespaces, before XMI. A file whose extension names a
generic format, such as `.xmi`, is therefore read as EMOF or UML when its contents are, while
every other XMI document is still read as XMI. Name the format explicitly to read such a file
as plain XMI.

```swift
let model = try await ModelIO.load(url: omgModelURL, resourceSet: ResourceSet())
// model.format == .uml for an `.xmi` file in an OMG UML namespace
let plain = try await ModelIO.load(url: omgModelURL, format: .xmi, resourceSet: ResourceSet())
```

## Topics

### XMI

- ``XMIVersion``
- ``XMITypeAttribute``
- ``XMISerializationOptions``

### EMOF

- ``EMOFFormat``
- ``EMOFSyntax``
- ``EMOFError``

### UML

- ``UMLFormat``
- ``UMLMetamodel``
- ``UMLNamespaces``

### Results

- ``ModelDocumentReadResult``
- ``ModelDocumentWriteResult``
- ``ModelDocumentDiagnostic``
