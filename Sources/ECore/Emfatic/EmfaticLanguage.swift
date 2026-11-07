//
// EmfaticLanguage.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//

/// The vocabulary of the Emfatic notation for Ecore metamodels.
///
/// Emfatic is a compact, Java-like textual notation for Ecore metamodels. This type is the
/// single authoritative place for its file extension, keywords, punctuation, annotation
/// labels and built-in type names.
public enum EmfaticLanguage {
    /// The file extension of Emfatic documents, without the leading full stop.
    public static let fileExtension = "emf"

    /// The namespace of the diagnostic codes that Emfatic reading and writing report.
    public static let diagnosticNamespace = "emfatic"

    /// The keywords of Emfatic.
    ///
    /// A keyword is reserved: to use one as a name, write it with the escape character
    /// ``escapeCharacter`` in front, as in `~abstract`.
    public enum Keyword: String, CaseIterable, Sendable {
        /// Declares a package or subpackage.
        case package
        /// Imports another metamodel.
        case `import`
        /// Marks a class as abstract.
        case abstract
        /// Declares a class.
        case `class`
        /// Declares an interface.
        case interface
        /// Introduces supertypes or a type bound.
        case extends
        /// Introduces the lower bound of a wildcard.
        case `super`
        /// Declares an attribute.
        case attr
        /// Declares a non-containment reference.
        case ref
        /// Declares a containment reference.
        case val
        /// Declares an operation.
        case op
        /// Stands for the absence of a return type.
        case void
        /// Declares a data type.
        case datatype
        /// Declares an enumeration.
        case `enum`
        /// Declares a map entry class.
        case mapentry
        /// Introduces the exceptions of an operation.
        case `throws`
        /// Makes a feature unchangeable.
        case readonly
        /// Makes a feature volatile.
        case volatile
        /// Makes a feature transient, or a data type not serialisable.
        case transient
        /// Makes a feature unsettable.
        case unsettable
        /// Makes a feature derived.
        case derived
        /// Makes a many-valued element unique; `!unique` makes it non-unique.
        case unique
        /// Makes a many-valued element ordered; `!ordered` makes it unordered.
        case ordered
        /// Makes a reference resolve proxies; `!resolve` stops it.
        case resolve
        /// Makes an attribute the identifier of its class.
        case id
        /// The Boolean literal true.
        case `true`
        /// The Boolean literal false.
        case `false`
    }

    /// The set of keyword spellings.
    static let keywords: Set<String> = Set(Keyword.allCases.map(\.rawValue))

    /// The modifiers that may precede a feature, operation or parameter.
    static let modifiers: Set<String> = [
        Keyword.readonly, .volatile, .transient, .unsettable, .derived, .unique, .ordered, .resolve, .id,
    ].reduce(into: []) { $0.insert($1.rawValue) }

    /// The character that escapes a keyword used as a name.
    public static let escapeCharacter: Character = "~"

    /// The character that negates a modifier, as in `!unique`.
    static let negation = "!"

    /// The punctuation and operator symbols of Emfatic.
    static let punctuation = [
        "{", "}", "[", "]", "(", ")", ".", ",", ":", ";", "*", "+", "-", "=", "?", "!", "$", "#", "@", "..",
        "->", "&", "<", ">",
    ]

    /// The symbols shown as operators by token classification.
    static let operators: Set<String> = ["=", "#", "->", "..", "&", "!", "-", "$"]

    /// The lexical conventions of Emfatic.
    ///
    /// Emfatic keeps the escape sequences of its literals as written, apart from `\"` in
    /// annotation values.
    static let lexicalConfiguration = LexicalConfiguration(
        identifierEscape: escapeCharacter, punctuation: punctuation, stringDelimiters: ["\""],
        characterDelimiter: "'", decodesEscapes: false)

    /// The qualified-name separators: a full stop, and `$` for nested Java classes.
    static let nameSeparators: Set<String> = [".", "$"]

    /// The instance class name of a map entry class.
    public static let mapEntryInstanceClassName = "java.util.Map$Entry"

    /// The names of the two features of a map entry class.
    public enum MapEntryFeature: String, CaseIterable, Sendable {
        /// The key of a map entry.
        case key
        /// The value of a map entry.
        case value
    }

    // MARK: Annotations

    /// The annotation label that sets the namespace of a package.
    public static let namespaceLabel = "namespace"

    /// The keys of the namespace annotation.
    public enum NamespaceKey: String, CaseIterable, Sendable {
        /// The namespace URI of the package.
        case uri
        /// The namespace prefix of the package.
        case prefix
    }

    /// The source URI of the annotation that defines further annotation labels.
    public static let annotationMapSource = "http://www.eclipse.org/emf/2004/EmfaticAnnotationMap"

    /// The predefined annotation labels and their source URIs, in canonical spelling.
    ///
    /// Labels are matched without regard to case.
    public static let annotationLabels: [(label: String, source: String)] = [
        ("Ecore", AnnotationSource.ecore),
        ("GenModel", AnnotationSource.genModel),
        ("ExtendedMetaData", AnnotationSource.extendedMetaData),
        ("EmfaticAnnotationMap", annotationMapSource),
    ]

    /// The key given to an annotation value written without a key.
    static let implicitKey = "value"

    // MARK: Types

    /// The prefix that names any built-in classifier of Ecore, as in `ecore.EOperation`.
    public static let ecorePrefix = "ecore."

    /// The basic type names of Emfatic and the Ecore classifiers they stand for.
    ///
    /// The first name listed for a classifier is the one the writer prefers.
    public static let basicTypes: [(name: String, classifier: String)] = [
        ("String", EcoreDataType.eString.rawValue),
        ("boolean", EcoreDataType.eBoolean.rawValue),
        ("Boolean", EcoreDataType.eBooleanObject.rawValue),
        ("byte", EcoreDataType.eByte.rawValue),
        ("Byte", EcoreDataType.eByteObject.rawValue),
        ("char", EcoreDataType.eChar.rawValue),
        ("Character", EcoreDataType.eCharacterObject.rawValue),
        ("double", EcoreDataType.eDouble.rawValue),
        ("Double", EcoreDataType.eDoubleObject.rawValue),
        ("float", EcoreDataType.eFloat.rawValue),
        ("Float", EcoreDataType.eFloatObject.rawValue),
        ("int", EcoreDataType.eInt.rawValue),
        ("Integer", EcoreDataType.eIntegerObject.rawValue),
        ("long", EcoreDataType.eLong.rawValue),
        ("Long", EcoreDataType.eLongObject.rawValue),
        ("short", EcoreDataType.eShort.rawValue),
        ("Short", EcoreDataType.eShortObject.rawValue),
        ("Date", EcoreDataType.eDate.rawValue),
        ("Object", EcoreDataType.eJavaObject.rawValue),
        ("Class", EcoreDataType.eJavaClass.rawValue),
        ("EObject", EcoreClassifier.eObject.rawValue),
        ("EClass", EcoreClassifier.eClass.rawValue),
    ]

    /// The Ecore classifiers that Emfatic accepts by their Ecore name without a prefix.
    public static let unprefixedEcoreNames: Set<String> = [
        EcoreDataType.eBoolean, .eByte, .eChar, .eDouble, .eFloat, .eInt, .eLong, .eShort, .eBooleanObject,
        .eByteObject, .eCharacterObject, .eDoubleObject, .eFloatObject, .eIntegerObject, .eLongObject,
        .eShortObject, .eDate, .eString, .eJavaClass, .eBigInteger, .eBigDecimal, .eResource, .eResourceSet,
        .eEnumerator, .eEList, .eTreeIterator, .eJavaObject,
    ].reduce(into: []) { $0.insert($1.rawValue) }

    /// The Ecore classifiers that the writer names by their Ecore name, not a basic type name.
    static let preferredEcoreNames: Set<String> = [
        EcoreDataType.eDate.rawValue, EcoreDataType.eJavaObject.rawValue,
    ]

    /// The classifier that a name stands for when the document does not declare it.
    ///
    /// - Parameter name: The name as written.
    /// - Returns: The Ecore classifier, or `nil` if Emfatic knows no such name.
    static func builtinClassifier(_ name: String) -> (any EClassifier)? {
        if let basic = basicTypes.first(where: { $0.name == name }) {
            return EcorePackage.classifier(named: basic.classifier)
        }
        if unprefixedEcoreNames.contains(name) { return EcorePackage.classifier(named: name) }
        if name.hasPrefix(ecorePrefix) { return EcorePackage.classifier(named: String(name.dropFirst(ecorePrefix.count))) }
        return nil
    }

    /// The spellings of a built-in Ecore classifier, preferred first.
    ///
    /// - Parameter name: The Ecore name of the classifier.
    /// - Returns: The basic type name, the unprefixed Ecore name and the prefixed name, as available.
    static func builtinSpellings(of name: String) -> [String] {
        var result: [String] = []
        let basic = basicTypes.filter { $0.classifier == name }.map(\.name)
        if preferredEcoreNames.contains(name) {
            result.append(name)
            result += basic
        } else {
            result += basic
            if unprefixedEcoreNames.contains(name) { result.append(name) }
        }
        result.append(ecorePrefix + name)
        var seen: Set<String> = []
        return result.filter { seen.insert($0).inserted }
    }
}
