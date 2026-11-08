//
// ASDLDiagnostics.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase

/// The stable codes of the diagnostics that reading and writing ASDL report.
///
/// Each code is a dotted identifier that tools can match on without depending
/// on the wording of a message.
public enum ASDLDiagnosticCode: String, Sendable, CaseIterable, Hashable {
    /// A token appears where the grammar of ASDL does not allow it.
    case unexpectedToken = "asdl.unexpectedToken"

    /// A character cannot start any token.
    case unexpectedCharacter = "asdl.unexpectedCharacter"

    /// A string literal has no closing quote.
    case unterminatedString = "asdl.unterminatedString"

    /// The text has no module declaration.
    case missingModule = "asdl.missingModule"

    /// A field names a type that is neither defined nor built in.
    case undefinedType = "asdl.undefinedType"

    /// A type is defined twice in a module; the later definition is ignored.
    case duplicateType = "asdl.duplicateType"

    /// A constructor is defined twice in a module; the later definition is ignored.
    case duplicateConstructor = "asdl.duplicateConstructor"

    /// A field list is empty, which the grammar of ASDL does not allow.
    case emptyFields = "asdl.emptyFields"

    /// A name breaks the convention that types start in lower case and constructors in upper case.
    case namingConvention = "asdl.namingConvention"

    /// A field type names another module that is not part of the text.
    case externalType = "asdl.externalType"

    /// A combination of quantifiers is approximated by the closest Ecore multiplicity.
    case approximatedQuantifier = "asdl.approximatedQuantifier"

    /// A module imports other modules, whose types are not resolved.
    case unresolvedImport = "asdl.unresolvedImport"

    /// Two classifiers of a package have the same name; the later one is dropped.
    case duplicateClassifier = "asdl.duplicateClassifier"

    /// A class declares two features with the same name; the later one is dropped.
    case duplicateFeature = "asdl.duplicateFeature"

    /// A type name resolves to no classifier.
    case unresolvedType = "asdl.unresolvedType"

    /// A supertype is not a class, or would make inheritance circular.
    case invalidSupertype = "asdl.invalidSupertype"

    /// A metamodel element has no ASDL counterpart and is not written.
    case unsupportedElement = "asdl.unsupportedElement"

    /// A metamodel element is written as the closest ASDL construct, losing information.
    case approximatedElement = "asdl.approximatedElement"
}

/// The kinds of node in the outline of an ASDL description.
///
/// The kinds are the values of ``OutlineNode/kind`` in the outline that
/// ``ASDLParseResult`` carries.
public enum ASDLOutlineKind {
    /// A module, which contains the definitions.
    public static let module = "module"

    /// A sum type, which contains its constructors and attributes.
    public static let sum = "sum"

    /// A product type, which contains its fields and attributes.
    public static let product = "product"

    /// A constructor of a sum type, which contains its fields.
    public static let constructor = "constructor"

    /// A field of a constructor or product type.
    public static let field = "field"

    /// An attribute shared by every constructor of a sum type, or added to a product type.
    public static let attribute = "attribute"
}

/// How sum types whose constructors all lack fields are represented.
public enum ASDLEnumerationStyle: String, Sendable, Hashable, CaseIterable {
    /// A sum type of constructors without fields and without attributes becomes an `EEnum`.
    ///
    /// This follows the
    /// [ASDL paper](https://www.usenix.org/conference/dsl-97/zephyr-abstract-syntax-description-language),
    /// which notes that such types are finite
    /// enumerations that tools should represent as enumerations, and CPython,
    /// whose generated C code represents such "simple" sums as enumerations.
    case allNullarySums

    /// Every sum type becomes an abstract class with one subclass per constructor.
    ///
    /// This matches the class-per-constructor representation of Python's `ast`
    /// module, where `Add` and `Load` are classes.
    case never
}

/// The settings that control how ASDL is read.
public struct ASDLImportOptions: Sendable, Hashable {
    /// The Ecore data types that the built-in ASDL types map to by default.
    ///
    /// | ASDL type | Ecore type | Rationale |
    /// |---|---|---|
    /// | `identifier` | `EString` | A symbol-like name (the paper likens it to Lisp symbols) |
    /// | `string` | `EString` | Text |
    /// | `int` | `EInt` | The paper's integers are unbounded; `EInt` is common practice, and `EBigInteger` can be chosen instead |
    /// | `constant` | `EJavaObject` | CPython's literal values of any Python type |
    /// | `object` | `EJavaObject` | Older CPython dialect for arbitrary objects |
    /// | `singleton` | `EJavaObject` | Older CPython dialect for `None`, `True` and `False` |
    /// | `bytes` | `EByteArray` | Older CPython dialect for byte strings |
    public static let defaultBuiltinTypes: [String: EcoreDataType] = [
        "identifier": .eString,
        "string": .eString,
        "int": .eInt,
        "constant": .eJavaObject,
        "object": .eJavaObject,
        "singleton": .eJavaObject,
        "bytes": .eByteArray,
    ]

    /// The package name to use for a module without a name; the module name takes precedence.
    public var packageName: String?

    /// The namespace URI to use, since ASDL modules declare none.
    ///
    /// With several modules in one text, each module's name is appended after a slash.
    /// Without a URI, each package gets `urn:asdl:` followed by its name.
    public var nsURI: String?

    /// The namespace prefix to use, since ASDL modules declare none.
    ///
    /// Without a prefix, each package's prefix is its name in lower case.
    public var nsPrefix: String?

    /// How sum types whose constructors all lack fields are represented.
    public var enumerations: ASDLEnumerationStyle

    /// The Ecore data types of the built-in ASDL types.
    public var builtinTypes: [String: EcoreDataType]

    /// Creates options.
    ///
    /// - Parameters:
    ///   - packageName: The package name for a module without a name.
    ///   - nsURI: The namespace URI to use.
    ///   - nsPrefix: The namespace prefix to use.
    ///   - enumerations: How sums of constructors without fields are represented.
    ///   - builtinTypes: The Ecore data types of the built-in ASDL types.
    public init(
        packageName: String? = nil, nsURI: String? = nil, nsPrefix: String? = nil,
        enumerations: ASDLEnumerationStyle = .allNullarySums,
        builtinTypes: [String: EcoreDataType] = ASDLImportOptions.defaultBuiltinTypes
    ) {
        self.packageName = packageName
        self.nsURI = nsURI
        self.nsPrefix = nsPrefix
        self.enumerations = enumerations
        self.builtinTypes = builtinTypes
    }
}

/// The result of reading an ASDL description.
///
/// Reading recovers from errors, so the packages hold every definition that
/// was read correctly, and the diagnostics describe each one that was not.
public struct ASDLParseResult: Sendable {
    /// The packages, one per module, in source order.
    public var packages: [EPackage]

    /// The problems found, in source order.
    public var diagnostics: [SourceDiagnostic]

    /// The lexical tokens of the text, including comments.
    public var tokens: [SourceToken]

    /// The outline of the text: one node per module, containing its definitions.
    public var outline: [OutlineNode]

    /// Creates a result.
    ///
    /// - Parameters:
    ///   - packages: The packages, one per module.
    ///   - diagnostics: The problems found.
    ///   - tokens: The lexical tokens of the text.
    ///   - outline: The outline of the text.
    public init(packages: [EPackage], diagnostics: [SourceDiagnostic], tokens: [SourceToken], outline: [OutlineNode]) {
        self.packages = packages
        self.diagnostics = diagnostics
        self.tokens = tokens
        self.outline = outline
    }
}
