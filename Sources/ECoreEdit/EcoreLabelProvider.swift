//
// EcoreLabelProvider.swift
// ECoreEdit
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import ECore
public import EMFBase

/// The text that identifies an element in a tree or a list.
public struct EcoreLabel: Sendable, Hashable {
    /// The name of the element: the name of a named element, the key of a detail entry, and
    /// the shortened source of an annotation.
    public let name: String

    /// What follows the name, including its separator: ` -> Super1, Super2` for a class,
    /// ` : Type` for a feature, `(T1, T2) : R` for an operation, ` = 3` for a literal.
    public let detail: String

    /// Whether the label mentions a classifier that the document does not hold.
    public let isUnresolved: Bool

    /// The whole text: the name followed by the detail.
    public var text: String { name + detail }

    /// Creates a label.
    ///
    /// - Parameters:
    ///   - name: The name of the element.
    ///   - detail: What follows the name.
    ///   - isUnresolved: Whether the label mentions an unresolved classifier.
    public init(name: String, detail: String = "", isUnresolved: Bool = false) {
        self.name = name
        self.detail = detail
        self.isUnresolved = isUnresolved
    }
}

/// The picture that stands for an element.
public enum EcoreIcon: String, Sendable, Hashable, CaseIterable {
    /// A package.
    case ePackage
    /// A concrete class.
    case eClass
    /// An abstract class.
    case eAbstractClass
    /// An interface.
    case eInterface
    /// A data type.
    case eDataType
    /// An enumeration.
    case eEnum
    /// An enumeration literal.
    case eEnumLiteral
    /// An attribute.
    case eAttribute
    /// A reference that is not a containment.
    case eReference
    /// A containment reference.
    case eContainmentReference
    /// An operation.
    case eOperation
    /// A parameter.
    case eParameter
    /// An annotation.
    case eAnnotation
    /// A key and value entry of an annotation.
    case detailsEntry
    /// An element that the document does not hold.
    case unresolved
}

/// A decoration that shows the multiplicity of a feature, operation, or parameter.
public enum EcoreMultiplicityDecoration: Sendable, Hashable {
    /// Zero or one (`0..1`).
    case zeroToOne
    /// Exactly one (`1`).
    case one
    /// Any number (`0..*`).
    case zeroToMany
    /// At least one (`1..*`).
    case oneToMany
    /// Exactly the given number, other than one.
    case exact(Int)
    /// Between the bounds; an upper bound of `-1` is unbounded.
    case range(Int, Int)

    /// The text of the multiplicity, such as `0..1`, `1`, `0..*`, `3`, or `2..5`.
    public var text: String {
        let separator = EcoreLabelSyntax.multiplicityRangeSeparator
        let unbounded = EcoreLabelSyntax.multiplicityUnbounded
        switch self {
        case .zeroToOne: return "0\(separator)1"
        case .one: return "1"
        case .zeroToMany: return "0\(separator)\(unbounded)"
        case .oneToMany: return "1\(separator)\(unbounded)"
        case .exact(let count): return String(count)
        case .range(let lower, let upper): return "\(lower)\(separator)\(upper < 0 ? unbounded : String(upper))"
        }
    }

    /// The decoration for bounds.
    ///
    /// - Parameters:
    ///   - lower: The lower bound.
    ///   - upper: The upper bound; a negative value means unbounded.
    public init(lower: Int, upper: Int) {
        switch (lower, upper) {
        case (0, 1): self = .zeroToOne
        case (1, 1): self = .one
        case (0, ..<0): self = .zeroToMany
        case (1, ..<0): self = .oneToMany
        case _ where lower == upper: self = .exact(lower)
        default: self = .range(lower, upper < 0 ? EcoreEditDefaults.unbounded : upper)
        }
    }
}

/// Provides the labels, icons, and multiplicity decorations of metamodel elements.
///
/// Labels have the layout of the Eclipse Sample Ecore Editor:
///
/// | Element | Text |
/// | --- | --- |
/// | Package, enumeration | `Name` |
/// | Class | `Name -> Super1, Super2`, then ` [instanceClassName]` if set |
/// | Data type | `Name [instanceClassName]` |
/// | Attribute, reference, parameter | `name : Type` |
/// | Operation | `name(T1, T2) : R`, then ` throws E1, E2` |
/// | Enumeration literal | `NAME = value` |
/// | Annotation | the last segment of the source (the whole source inside another annotation) |
/// | Detail entry | `key -> value` |
///
/// The separators are defined by ``EcoreLabelSyntax``. Types are resolved by identifier through the
/// index, so a label never shows the name that a stale snapshot had.
public struct EcoreLabelProvider: Sendable {
    /// Creates a label provider.
    public init() {}

    /// The label of an element.
    ///
    /// - Parameters:
    ///   - identifier: The identifier of the element.
    ///   - index: The index of the document that holds the element.
    /// - Returns: The label; an unresolved label without text if the index does not know the element.
    public func label(for identifier: EUUID, in index: MetamodelIndex) -> EcoreLabel {
        guard let element = index.element(identifier) else { return EcoreLabel(name: "", isUnresolved: true) }
        var resolver = TypeNames(index: index)
        let name: String
        var detail = ""
        switch element {
        case .package(let value): name = value.name
        case .eEnum(let value): name = value.name + Self.typeParameterList(value.eTypeParameters)
        case .eClass(let value):
            name = value.name + Self.typeParameterList(value.eTypeParameters)
            if !value.eSuperTypes.isEmpty {
                detail += EcoreLabelSyntax.supertypeSeparator
                    + (value.eGenericSuperTypes.isEmpty
                        ? value.eSuperTypes.map { resolver.name(of: $0) }
                        : value.eGenericSuperTypes.map { resolver.name(of: $0) })
                    .joined(separator: EcoreLabelSyntax.listSeparator)
            }
            if let instance = value.instanceClassName { detail += Self.bracketed(instance) }
        case .dataType(let value):
            name = value.name + Self.typeParameterList(value.eTypeParameters)
            detail = Self.bracketed(value.instanceClassName ?? EcoreLabelSyntax.absentValue)
        case .literal(let value):
            name = value.name
            detail = EcoreLabelSyntax.literalSeparator + String(value.value)
        case .attribute(let value):
            name = value.name
            detail = EcoreLabelSyntax.typeSeparator + resolver.name(of: value.eGenericType, or: value.eType)
        case .reference(let value):
            name = value.name
            detail = EcoreLabelSyntax.typeSeparator + resolver.name(of: value.eGenericType, or: value.eType)
        case .parameter(let value):
            name = value.name
            if value.eGenericType != nil || value.eType != nil {
                detail = EcoreLabelSyntax.typeSeparator + resolver.name(of: value.eGenericType, or: value.eType)
            }
        case .typeParameter(let value):
            name = value.name
            if !value.eBounds.isEmpty {
                detail = EcoreLabelSyntax.upperBoundSeparator
                    + value.eBounds.map { resolver.name(of: $0) }.joined(separator: EcoreLabelSyntax.boundsSeparator)
            }
        case .operation(let value):
            name = value.name + Self.typeParameterList(value.eTypeParameters)
            detail = operationDetail(value, &resolver)
        case .annotation(let value):
            let nested: Bool
            if case .annotation? = index.container(of: identifier).flatMap({ index.element($0.container) }) {
                nested = true
            } else {
                nested = false
            }
            name = nested ? value.source : Self.lastSegment(of: value.source)
        case .detail(let value):
            name = value.key
            detail = EcoreLabelSyntax.detailSeparator + Self.cropped(value.value)
        }
        return EcoreLabel(name: name, detail: detail, isUnresolved: resolver.unresolved)
    }

    private func operationDetail(_ operation: EOperation, _ resolver: inout TypeNames) -> String {
        var detail = EcoreLabelSyntax.parametersOpening
        for (position, parameter) in operation.eParameters.enumerated() {
            guard parameter.eGenericType != nil || parameter.eType != nil else { continue }
            detail += resolver.name(of: parameter.eGenericType, or: parameter.eType)
            if position < operation.eParameters.count - 1 { detail += EcoreLabelSyntax.listSeparator }
        }
        detail += EcoreLabelSyntax.parametersClosing
        if operation.eGenericType != nil || operation.eType != nil {
            detail += EcoreLabelSyntax.typeSeparator + resolver.name(of: operation.eGenericType, or: operation.eType)
        }
        if !operation.eGenericExceptions.isEmpty {
            detail += EcoreLabelSyntax.exceptionsSeparator
                + operation.eGenericExceptions.map { resolver.name(of: $0) }.joined(separator: EcoreLabelSyntax.listSeparator)
        } else if !operation.eExceptions.isEmpty {
            detail += EcoreLabelSyntax.exceptionsSeparator
                + operation.eExceptions.map { resolver.name(of: $0) }.joined(separator: EcoreLabelSyntax.listSeparator)
        }
        return detail
    }

    /// The type parameters of a declaration as they follow its name: `<K, V>`, or nothing.
    private static func typeParameterList(_ parameters: [ETypeParameter]) -> String {
        guard !parameters.isEmpty else { return "" }
        return EcoreLabelSyntax.typeArgumentsOpening
            + parameters.map(\.name).joined(separator: EcoreLabelSyntax.listSeparator)
            + EcoreLabelSyntax.typeArgumentsClosing
    }

    private static func bracketed(_ text: String) -> String {
        EcoreLabelSyntax.instanceClassNameOpening + text + EcoreLabelSyntax.instanceClassNameClosing
    }

    private static func lastSegment(of source: String) -> String {
        guard let separator = source.lastIndex(of: EcoreLabelSyntax.sourceSeparator) else { return source }
        return String(source[source.index(after: separator)...])
    }

    /// Cuts a text at its first control character and marks the cut.
    private static func cropped(_ text: String) -> String {
        guard let cut = text.unicodeScalars.firstIndex(where: { $0.properties.generalCategory == .control }) else {
            return text
        }
        return String(text.unicodeScalars[..<cut]) + EcoreLabelSyntax.truncationSuffix
    }

    /// The icon of an element.
    ///
    /// - Parameters:
    ///   - identifier: The identifier of the element.
    ///   - index: The index of the document that holds the element.
    /// - Returns: The icon; ``EcoreIcon/unresolved`` if the index does not know the element.
    public func icon(for identifier: EUUID, in index: MetamodelIndex) -> EcoreIcon {
        guard let element = index.element(identifier) else { return .unresolved }
        switch element {
        case .package: return .ePackage
        case .eClass(let value): return value.isInterface ? .eInterface : value.isAbstract ? .eAbstractClass : .eClass
        case .dataType: return .eDataType
        case .eEnum: return .eEnum
        case .literal: return .eEnumLiteral
        case .attribute: return .eAttribute
        case .reference(let value): return value.containment ? .eContainmentReference : .eReference
        case .operation: return .eOperation
        case .parameter: return .eParameter
        case .annotation: return .eAnnotation
        case .detail: return .detailsEntry
        case .typeParameter: return .eParameter
        }
    }

    /// The multiplicity decoration of an element.
    ///
    /// - Parameters:
    ///   - identifier: The identifier of the element.
    ///   - index: The index of the document that holds the element.
    /// - Returns: The decoration of an attribute, reference, operation, or parameter; `nil` for
    ///   other elements and unknown identifiers.
    public func multiplicity(for identifier: EUUID, in index: MetamodelIndex) -> EcoreMultiplicityDecoration? {
        switch index.element(identifier) {
        case .attribute(let value): return EcoreMultiplicityDecoration(lower: value.lowerBound, upper: value.upperBound)
        case .reference(let value): return EcoreMultiplicityDecoration(lower: value.lowerBound, upper: value.upperBound)
        case .operation(let value): return EcoreMultiplicityDecoration(lower: value.lowerBound, upper: value.upperBound)
        case .parameter(let value): return EcoreMultiplicityDecoration(lower: value.lowerBound, upper: value.upperBound)
        default: return nil
        }
    }

    /// Resolves the names of classifiers by identifier.
    private struct TypeNames {
        let index: MetamodelIndex
        var unresolved = false

        init(index: MetamodelIndex) { self.index = index }

        /// The name of a classifier: that of the element with its identifier, or, if the
        /// document holds none, that of the Ecore built-in classifier, or, failing that, the
        /// name that the snapshot carries (which marks the label as unresolved).
        mutating func name(of type: EGenericType?, or classifier: (any EClassifier)?) -> String {
            if let type { return name(of: type) }
            return classifier.map { name(of: $0) } ?? ""
        }

        /// The text of a generic type: `EList<EString>`, `T`, or `? extends Car`.
        mutating func name(of type: EGenericType) -> String {
            var text: String
            if let classifier = type.eClassifier {
                text = name(of: classifier)
            } else if let parameter = type.eTypeParameter {
                if case .typeParameter(let value)? = index.element(parameter) {
                    text = value.name
                } else {
                    unresolved = true
                    text = EcoreLabelSyntax.wildcard
                }
            } else {
                text = EcoreLabelSyntax.wildcard
                if let bound = type.eUpperBound {
                    text += EcoreLabelSyntax.upperBoundSeparator + name(of: bound)
                } else if let bound = type.eLowerBound {
                    text += EcoreLabelSyntax.lowerBoundSeparator + name(of: bound)
                }
            }
            if !type.eTypeArguments.isEmpty {
                var arguments: [String] = []
                for argument in type.eTypeArguments { arguments.append(name(of: argument)) }
                text += EcoreLabelSyntax.typeArgumentsOpening
                    + arguments.joined(separator: EcoreLabelSyntax.listSeparator)
                    + EcoreLabelSyntax.typeArgumentsClosing
            }
            return text
        }

        mutating func name(of classifier: any EClassifier) -> String {
            if let element = index.element(classifier.id), let name = element.name { return name }
            if let builtIn = EcoreBuiltIns.classifiers[classifier.id] { return builtIn.name }
            unresolved = true
            return classifier.name
        }
    }
}

extension MetamodelDocument {
    /// The label of an element.
    ///
    /// - Parameter identifier: The identifier of the element.
    /// - Returns: The label provided by ``EcoreLabelProvider``.
    public func label(for identifier: EUUID) -> EcoreLabel {
        EcoreLabelProvider().label(for: identifier, in: index)
    }
}
