//
// XcoreLanguage.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//

/// The vocabulary of the structural subset of the Xcore notation for Ecore metamodels.
///
/// Xcore is a textual notation for Ecore metamodels that embeds Xbase expressions for
/// operation and feature bodies. This type is the single authoritative place for its file
/// extension, keywords, punctuation, annotation aliases, built-in type names and the
/// annotation keys under which bodies are preserved.
public enum XcoreLanguage {
    /// The file extension of Xcore documents, without the leading full stop.
    public static let fileExtension = "xcore"

    /// The namespace of the diagnostic codes that Xcore reading and writing report.
    public static let diagnosticNamespace = "xcore"

    /// The namespace URI of Xcore, used as the source of annotations that hold Xcore details.
    ///
    /// The annotation directives of a package are kept under this source, one detail per
    /// alias, as EMF keeps them. Bodies, which EMF does not keep in Ecore at all, are kept
    /// under this source too, with the keys of ``BodyKey``.
    public static let namespaceURI = "http://www.eclipse.org/emf/2011/Xcore"

    /// The structural keywords of Xcore.
    public enum Keyword: String, CaseIterable, Sendable {
        /// Declares the package.
        case package
        /// Imports a qualified name.
        case `import`
        /// Declares an annotation alias.
        case annotation
        /// Introduces an alias or a literal text.
        case `as`
        /// Declares a class.
        case `class`
        /// Declares an interface.
        case interface
        /// Marks a class as abstract.
        case abstract
        /// Introduces supertypes or a type bound.
        case extends
        /// Introduces the lower bound of a wildcard.
        case `super`
        /// Introduces an instance type.
        case wraps
        /// Declares a data type.
        case type
        /// Introduces the creation body of a data type.
        case create
        /// Introduces the conversion body of a data type.
        case convert
        /// Declares an enumeration.
        case `enum`
        /// Declares an operation.
        case op
        /// Stands for the absence of a return type.
        case void
        /// Introduces the exceptions of an operation.
        case `throws`
        /// Makes a many-valued element unordered.
        case unordered
        /// Makes a many-valued element unique.
        case unique
        /// Makes a feature unchangeable.
        case readonly
        /// Makes a feature transient.
        case transient
        /// Makes a feature volatile.
        case volatile
        /// Makes a feature unsettable.
        case unsettable
        /// Makes a feature derived.
        case derived
        /// Makes an attribute the identifier of its class.
        case id
        /// Declares a containment reference.
        case contains
        /// Declares the container side of a containment.
        case container
        /// Declares a non-containment reference.
        case refers
        /// Makes a containment reference resolve proxies.
        case resolving
        /// Stops a non-containment reference resolving proxies.
        case local
        /// Names the opposite of a reference.
        case opposite
        /// Names the keys of a reference.
        case keys
        /// Introduces a getter body.
        case get
        /// Introduces a setter body.
        case set
        /// Introduces an is-set body.
        case isSet
        /// Introduces an unset body.
        case unset
    }

    /// The keywords of the embedded Xbase expression language, reserved in Xcore names too.
    static let expressionKeywords: Set<String> = [
        "val", "var", "if", "else", "switch", "for", "while", "do", "new", "return", "try", "catch", "finally",
        "typeof", "instanceof", "this", "null", "true", "false", "static", "extension", "default", "case",
        "synchronized",
    ]

    /// Every reserved word, which must be escaped with ``escapeCharacter`` to be used as a name.
    static let keywords: Set<String> = Set(Keyword.allCases.map(\.rawValue)).union(expressionKeywords)

    /// The modifier keywords that may precede an attribute or reference.
    static let featureModifiers: Set<String> = [
        Keyword.unordered, .unique, .readonly, .transient, .volatile, .unsettable, .derived, .id, .contains,
        .container, .refers, .resolving, .local,
    ].reduce(into: []) { $0.insert($1.rawValue) }

    /// The keywords that introduce the bodies of a feature, in canonical order.
    static let accessorKeywords: [Keyword] = [.get, .set, .isSet, .unset]

    /// The character that escapes a keyword used as a name.
    public static let escapeCharacter: Character = "^"

    /// The punctuation and operator symbols of Xcore, including those of Xbase bodies.
    static let punctuation = [
        "{", "}", "[", "]", "(", ")", ".", ",", ":", ";", "*", "+", "-", "/", "%", "=", "?", "!", "#", "@", "&",
        "|", "<", ">", "..", "->", "=>", "::", "?.", "..<", "**", "+=", "-=", "*=", "/=", "%=", "++", "--", "==",
        "!=", "===", "!==", "<=", "&&", "||", "?:", "\\", "`", "~",
    ]

    /// The symbols shown as operators by token classification.
    static let operators: Set<String> = [
        "=", "&", "..", "->", "=>", "::", "?.", "+", "-", "/", "%", "!", "==", "!=", "===", "!==", "<=", "&&", "||",
        "+=", "-=", "*=", "/=", "%=", "++", "--", "**", "..<", "?:", "|",
    ]

    /// The lexical conventions of Xcore.
    static let lexicalConfiguration = LexicalConfiguration(
        identifierEscape: escapeCharacter, punctuation: punctuation, stringDelimiters: ["\"", "'"],
        extraIdentifierCharacters: ["$"], decodesEscapes: true)

    /// The suffix of a wildcard import, as in `import org.example.*`.
    static let wildcardSuffix = ".*"

    // MARK: Annotations

    /// The predefined annotation aliases and their source URIs.
    ///
    /// An annotation whose name ends in one of these aliases has the corresponding source,
    /// and all annotations of an element with the same predefined alias are merged into one.
    public static let annotationAliases: [(alias: String, source: String)] = [
        ("Ecore", AnnotationSource.ecore),
        ("GenModel", AnnotationSource.genModel),
        ("ExtendedMetaData", AnnotationSource.extendedMetaData),
    ]

    /// The alias of the Ecore annotation, whose details can set attributes of the element.
    static let ecoreAlias = "Ecore"

    /// The GenModel detail that holds the qualifying prefix of a package name.
    public static let basePackageKey = "basePackage"

    /// The GenModel detail that holds documentation.
    static let documentationKey = AnnotationSource.GenModelKey.documentation

    /// The keys under which the Xcore annotation preserves body text.
    public enum BodyKey: String, CaseIterable, Sendable {
        /// The body of an operation.
        case body
        /// The getter body of a feature.
        case get
        /// The setter body of a feature.
        case set
        /// The is-set body of a feature.
        case isSet
        /// The unset body of a feature.
        case unset
        /// The creation body of a data type.
        case create
        /// The conversion body of a data type.
        case convert
    }

    /// The Ecore attributes that the `@Ecore` annotation can set.
    enum EcoreAttribute: String, CaseIterable {
        /// The name of the element.
        case name
        /// The namespace URI of a package.
        case nsURI
        /// The namespace prefix of a package.
        case nsPrefix
        /// The instance class name of a classifier.
        case instanceClassName
        /// The instance type name of a classifier.
        case instanceTypeName
        /// Whether a class is abstract.
        case abstract
        /// Whether a class is an interface.
        case interface
        /// Whether a data type is serialisable.
        case serializable
        /// Whether a feature or parameter is ordered.
        case ordered
        /// Whether a feature or parameter is unique.
        case unique
        /// The lower bound of the multiplicity.
        case lowerBound
        /// The upper bound of the multiplicity.
        case upperBound
        /// Whether a feature is changeable.
        case changeable
        /// Whether a feature is volatile.
        case volatile
        /// Whether a feature is transient.
        case transient
        /// The default value literal of a feature.
        case defaultValueLiteral
        /// Whether a feature is unsettable.
        case unsettable
        /// Whether a feature is derived.
        case derived
        /// Whether an attribute is an identifier.
        case iD
        /// Whether a reference is a containment.
        case containment
        /// Whether a reference resolves proxies.
        case resolveProxies
        /// The numeric value of an enumeration literal.
        case value
        /// The literal text of an enumeration literal.
        case literal
    }

    /// The prefix that names the package of the built-in classifiers of Ecore.
    public static let ecorePackageName = "org.eclipse.emf.ecore"

    /// The prefix of names that are always visible because `java.lang` is imported.
    static let javaLangPackage = "java.lang"

    /// The Java names that Xcore resolves to Ecore data types, with their qualified forms.
    ///
    /// The first entry for a data type is the name that the writer prefers.
    public static let javaTypes: [(simple: String, qualified: String, classifier: String)] = [
        ("String", "java.lang.String", EcoreDataType.eString.rawValue),
        ("int", "int", EcoreDataType.eInt.rawValue),
        ("Integer", "java.lang.Integer", EcoreDataType.eIntegerObject.rawValue),
        ("boolean", "boolean", EcoreDataType.eBoolean.rawValue),
        ("Boolean", "java.lang.Boolean", EcoreDataType.eBooleanObject.rawValue),
        ("long", "long", EcoreDataType.eLong.rawValue),
        ("Long", "java.lang.Long", EcoreDataType.eLongObject.rawValue),
        ("double", "double", EcoreDataType.eDouble.rawValue),
        ("Double", "java.lang.Double", EcoreDataType.eDoubleObject.rawValue),
        ("float", "float", EcoreDataType.eFloat.rawValue),
        ("Float", "java.lang.Float", EcoreDataType.eFloatObject.rawValue),
        ("char", "char", EcoreDataType.eChar.rawValue),
        ("Character", "java.lang.Character", EcoreDataType.eCharacterObject.rawValue),
        ("byte", "byte", EcoreDataType.eByte.rawValue),
        ("Byte", "java.lang.Byte", EcoreDataType.eByteObject.rawValue),
        ("short", "short", EcoreDataType.eShort.rawValue),
        ("Short", "java.lang.Short", EcoreDataType.eShortObject.rawValue),
        ("Date", "java.util.Date", EcoreDataType.eDate.rawValue),
        ("BigDecimal", "java.math.BigDecimal", EcoreDataType.eBigDecimal.rawValue),
        ("BigInteger", "java.math.BigInteger", EcoreDataType.eBigInteger.rawValue),
        ("Object", "java.lang.Object", EcoreDataType.eJavaObject.rawValue),
        ("Class", "java.lang.Class", EcoreDataType.eJavaClass.rawValue),
    ]

    /// Resolves a type name that the document does not declare.
    ///
    /// - Parameters:
    ///   - name: The name as written, after explicit imports have been applied.
    ///   - wildcards: The packages imported with a wildcard.
    /// - Returns: The Ecore classifier, or `nil` if the name is unknown.
    static func builtinClassifier(_ name: String, wildcards: [String]) -> (any EClassifier)? {
        if let java = javaTypes.first(where: { $0.simple == name || $0.qualified == name }) {
            return EcorePackage.classifier(named: java.classifier)
        }
        let ecorePrefix = ecorePackageName + "."
        if name.hasPrefix(ecorePrefix) {
            return EcorePackage.classifier(named: String(name.dropFirst(ecorePrefix.count)))
        }
        if !name.contains("."), wildcards.contains(ecorePackageName) { return EcorePackage.classifier(named: name) }
        return nil
    }

    /// The Java name of a built-in Ecore classifier, if Xcore has one.
    ///
    /// - Parameter name: The Ecore name of the classifier.
    /// - Returns: The simple Java name, or `nil` if the classifier needs an import.
    static func javaName(of name: String) -> String? {
        javaTypes.first { $0.classifier == name }?.simple
    }

    /// The default namespace prefix of a package name, as Xcore derives it.
    ///
    /// - Parameter name: The simple name of the package.
    /// - Returns: The name, with `_` in front if it starts with `xml` in any case.
    static func defaultPrefix(for name: String) -> String {
        name.lowercased().hasPrefix("xml") ? "_" + name : name
    }
}
