//
// EcoreEditConstants.swift
// ECoreEdit
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import ECore
public import EMFBase

/// The punctuation and keywords that make up the text of labels and multiplicity decorations.
///
/// Labels follow the layout of the Eclipse Sample Ecore Editor. Every separator that appears
/// in a label is defined here once, so that a change of layout touches this enumeration only.
public enum EcoreLabelSyntax {
    /// Introduces the supertypes of a class: `Name -> Super1, Super2`.
    public static let supertypeSeparator = " -> "

    /// Separates the items of a list in a label: supertypes, parameter types, and exceptions.
    public static let listSeparator = ", "

    /// Opens the instance class name of a class or data type.
    public static let instanceClassNameOpening = " ["

    /// Closes the instance class name of a class or data type.
    public static let instanceClassNameClosing = "]"

    /// Introduces the type of an attribute, reference, parameter, or operation.
    public static let typeSeparator = " : "

    /// Opens the parameter list of an operation.
    public static let parametersOpening = "("

    /// Closes the parameter list of an operation.
    public static let parametersClosing = ")"

    /// Introduces the exceptions of an operation.
    public static let exceptionsSeparator = " throws "

    /// Separates the name of an enumeration literal from its value.
    public static let literalSeparator = " = "

    /// Separates the key of a detail entry from its value.
    public static let detailSeparator = " -> "

    /// Separates the segments of the source of an annotation.
    public static let sourceSeparator: Character = "/"

    /// The text that stands for an absent instance class name of a data type.
    public static let absentValue = "null"

    /// Replaces the remainder of a detail value that contains a control character.
    public static let truncationSuffix = "..."

    /// Separates the bounds in the text of a multiplicity: `0..*`.
    public static let multiplicityRangeSeparator = ".."

    /// Stands for an unbounded upper bound in the text of a multiplicity.
    public static let multiplicityUnbounded = "*"
}

/// The values that edits fall back on and the codes of the diagnostics that they report.
public enum EcoreEditDefaults {
    /// The key of a detail entry that is created without a name; a number is appended when the
    /// key is already in use.
    public static let newDetailKey = "key"

    /// The upper bound that stands for an unbounded multiplicity.
    public static let unbounded = -1

    /// The diagnostic code reported when a supertype cycle is allowed by the edit policy.
    public static let supertypeCycleCode = "ecore.supertypeCycle"

    /// The kind of Ecore classifier that replaces a deleted class as the type of a reference.
    public static let replacementReferenceType = EcoreClassifier.eObject

    /// The built-in data type that replaces a deleted classifier as the type of an attribute.
    public static let replacementAttributeType = EcoreDataType.eJavaObject

    /// The built-in data type that new attributes have.
    public static let newAttributeType = EcoreDataType.eString
}

/// The labels that edits and their change sets carry, as shown by undo and redo menu items.
public enum EcoreEditLabels {
    /// The label of an edit that creates an element of a kind, followed by the kind.
    public static let create = "Create"
    /// The label of an edit that deletes elements.
    public static let delete = "Delete"
    /// The label of an edit that moves elements.
    public static let move = "Move"
    /// The label of an edit that sets a property, followed by the property.
    public static let set = "Set"
    /// The label of an edit that renames an element.
    public static let rename = "Rename"
    /// The label of an edit that pairs two references as opposites.
    public static let setOpposite = "Set Opposite"
    /// The label of an edit that sets the value of an annotation detail.
    public static let setDetail = "Set Detail"
    /// The label of an edit that renames the key of an annotation detail.
    public static let renameDetailKey = "Rename Detail Key"
    /// The label of an edit that pastes elements.
    public static let paste = "Paste"
}

/// The parts of the Ecore metamodel that the native metamodel types do not model.
enum EcoreEditSchema {
    /// The metaclasses of the elements that a native metamodel consists of.
    static let elementKinds: [EcoreClassifier] = [
        .ePackage, .eClass, .eDataType, .eEnum, .eEnumLiteral, .eAttribute, .eReference,
        .eOperation, .eParameter, .eAnnotation, .eStringToStringMapEntry,
    ]

    /// The features that the native metamodel types do not hold as editable properties, and
    /// the back references that follow from containment.
    static let unsupportedFeatures: Set<EcoreFeatureName> = [
        .eGenericType, .eTypeParameters, .eGenericSuperTypes, .eAllGenericSuperTypes,
        .eGenericExceptions, .eBounds, .instanceTypeName, .instanceClass, .defaultValue,
        .instance, .eFactoryInstance, .contents, .eKeys, .eContainingClass, .ePackage,
        .eSuperPackage, .eModelElement, .eEnum, .eOperation,
    ]
}
