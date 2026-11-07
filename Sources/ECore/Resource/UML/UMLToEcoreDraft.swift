//
// UMLToEcoreDraft.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import OrderedCollections

/// An Ecore element that a conversion from UML is building.
///
/// Drafts are mutable and refer to each other, so that the conversion can build and then
/// rework the metamodel as Eclipse UML2 does before writing it as an Ecore document. They
/// live only for the duration of one conversion.
final class EcoreDraft {
    /// The kinds of Ecore elements that a draft can stand for.
    enum Kind: Equatable {
        /// An `EPackage`.
        case package
        /// An `EClass`.
        case eClass
        /// An `EDataType`.
        case eDataType
        /// An `EEnum`.
        case eEnum
        /// An `EEnumLiteral`.
        case literal
        /// An `EAttribute`.
        case attribute
        /// An `EReference`.
        case reference
        /// An `EOperation`.
        case operation
        /// An `EParameter`.
        case parameter
        /// An `ETypeParameter`.
        case typeParameter

        /// Whether the kind is a classifier.
        var isClassifier: Bool { self == .eClass || self == .eDataType || self == .eEnum }

        /// Whether the kind is a structural feature.
        var isFeature: Bool { self == .attribute || self == .reference }

        /// Whether the kind is a typed element.
        var isTyped: Bool { isFeature || self == .operation || self == .parameter }
    }

    /// What the draft stands for.
    let kind: Kind

    /// The identifier of the element in the Ecore document.
    var identifier = ""

    /// The name of the element.
    var name = ""

    /// The element that contains this one, or `nil` for a root package or a draft that was removed.
    weak var container: EcoreDraft?

    /// The annotations of the element, in order.
    var annotations: [EcoreDraftAnnotation] = []

    /// The UML element the draft was made from, if any.
    var source: EUUID?

    // MARK: Packages

    /// The namespace URI of a package.
    var nsURI = ""

    /// The namespace prefix of a package.
    var nsPrefix = ""

    /// The classifiers of a package.
    var classifiers: [EcoreDraft] = []

    /// The subpackages of a package.
    var subpackages: [EcoreDraft] = []

    // MARK: Classifiers

    /// Whether a class is abstract.
    var isAbstract = false

    /// Whether a class is an interface.
    var isInterface = false

    /// The instance class name of a classifier.
    var instanceClassName: String?

    /// The super types of a class, in order.
    var superTypes: [EcoreDraftType] = []

    /// The features of a class.
    var features: [EcoreDraft] = []

    /// The operations of a class.
    var operations: [EcoreDraft] = []

    /// The type parameters of a classifier or operation.
    var typeParameters: [EcoreDraft] = []

    /// The literals of an enumeration.
    var literals: [EcoreDraft] = []

    /// The bounds of a type parameter.
    var bounds: [EcoreDraftType] = []

    // MARK: Typed elements

    /// The type of a typed element.
    var type: EcoreDraftType?

    /// The lower bound of a typed element.
    var lowerBound = 0

    /// The upper bound of a typed element, `-1` for unbounded.
    var upperBound = 1

    /// Whether a typed element is ordered.
    var ordered = true

    /// Whether a typed element is unique.
    var unique = true

    /// The exceptions of an operation.
    var exceptions: [EcoreDraftType] = []

    /// The parameters of an operation.
    var parameters: [EcoreDraft] = []

    // MARK: Features

    /// Whether a feature can be changed.
    var changeable = true

    /// Whether a feature is derived.
    var derived = false

    /// Whether a feature is transient.
    var transient = false

    /// Whether a feature is volatile.
    var volatile = false

    /// Whether a feature is unsettable.
    var unsettable = false

    /// Whether an attribute is an identifier.
    var iD = false

    /// Whether a reference is a containment.
    var containment = false

    /// Whether a reference resolves proxies.
    var resolveProxies = true

    /// The opposite of a reference.
    weak var opposite: EcoreDraft?

    /// The key attributes of a reference.
    var keys: [EcoreDraft] = []

    /// The default value literal of a feature.
    var defaultValueLiteral: String?

    // MARK: Literals

    /// The value of an enumeration literal.
    var value = 0

    /// The literal of an enumeration literal, if it differs from the name.
    var literal: String?

    /// Creates a draft.
    ///
    /// - Parameters:
    ///   - kind: What the draft stands for.
    ///   - source: The UML element it is made from, if any.
    init(_ kind: Kind, source: EUUID? = nil) {
        self.kind = kind
        self.source = source
    }

    /// The annotation with a source, created at the end of the annotations if it does not exist.
    ///
    /// - Parameter source: The source of the annotation.
    /// - Returns: The annotation.
    func annotation(_ source: String) -> EcoreDraftAnnotation {
        if let existing = annotations.first(where: { $0.source == source }) { return existing }
        let annotation = EcoreDraftAnnotation(source: source)
        annotations.append(annotation)
        return annotation
    }

    /// The annotation with a source, if the element has one.
    ///
    /// - Parameter source: The source of the annotation.
    /// - Returns: The annotation, or `nil`.
    func existingAnnotation(_ source: String) -> EcoreDraftAnnotation? {
        annotations.first { $0.source == source }
    }

    /// The package that contains the element, or the element itself if it is a package.
    var package: EcoreDraft? {
        var current: EcoreDraft? = self
        while let element = current, element.kind != .package { current = element.container }
        return current
    }

    /// The root package of the element.
    var root: EcoreDraft {
        var current = self
        while let container = current.container { current = container }
        return current
    }

    /// The name of the element qualified by the names of its containers, for messages.
    var qualifiedName: String {
        var names = [name]
        var current = container
        while let element = current {
            names.insert(element.name, at: 0)
            current = element.container
        }
        return names.joined(separator: UMLToEcore.Syntax.qualifiedNameSeparator)
    }

    /// Whether the element is a feature or operation with more than one value.
    var isMany: Bool { upperBound > 1 || upperBound == -1 }

    /// The classifier that types the element, if it is a draft of this conversion.
    var typeDraft: EcoreDraft? {
        if case .classifier(let classifier, _) = type { return classifier }
        return nil
    }

    // MARK: Classes

    /// The classes of the super types of a class.
    var superClasses: [EcoreDraft] {
        superTypes.compactMap { type in
            if case .classifier(let classifier, _) = type, classifier.kind == .eClass { return classifier }
            return nil
        }
    }

    /// The class and its super classes, transitively, each once, the class first.
    var allClasses: [EcoreDraft] {
        var result: [EcoreDraft] = []
        var seen = Set<ObjectIdentifier>()
        func visit(_ eClass: EcoreDraft) {
            guard seen.insert(ObjectIdentifier(eClass)).inserted else { return }
            for superClass in eClass.superClasses { visit(superClass) }
            result.append(eClass)
        }
        visit(self)
        return result
    }

    /// Whether a class is this class or one of its super classes, transitively.
    ///
    /// - Parameter other: The other class.
    /// - Returns: `true` if this class is a super type of the other class, or the same class.
    func isSuperType(of other: EcoreDraft) -> Bool {
        other.allClasses.contains { $0 === self }
    }

    /// The features of a class and its super classes, inherited features first.
    var allFeatures: [EcoreDraft] { allClasses.flatMap(\.features) }

    /// The operations of a class and its super classes, inherited operations first.
    var allOperations: [EcoreDraft] { allClasses.flatMap(\.operations) }
}

/// An annotation of a draft.
final class EcoreDraftAnnotation {
    /// The source of the annotation.
    let source: String

    /// The details of the annotation, in order.
    var details: OrderedDictionary<String, String> = [:]

    /// The elements that the annotation refers to.
    var references: [DraftReference] = []

    /// The elements that the annotation contains.
    var contents: [EcoreDraft] = []

    /// The annotations of the annotation.
    var annotations: [EcoreDraftAnnotation] = []

    /// Creates an annotation.
    ///
    /// - Parameter source: The source of the annotation.
    init(source: String) {
        self.source = source
    }

    /// The annotation of this annotation with a source, created if it does not exist.
    ///
    /// - Parameter source: The source of the annotation.
    /// - Returns: The annotation.
    func annotation(_ source: String) -> EcoreDraftAnnotation {
        if let existing = annotations.first(where: { $0.source == source }) { return existing }
        let annotation = EcoreDraftAnnotation(source: source)
        annotations.append(annotation)
        return annotation
    }

    /// Adds a reference to a draft unless the annotation already refers to it.
    ///
    /// - Parameter draft: The element to refer to.
    func addReference(_ draft: EcoreDraft) {
        if !references.contains(where: { if case .draft(let other) = $0 { return other === draft } else { return false } }) {
            references.append(.draft(draft))
        }
    }
}

/// An element that an annotation refers to.
enum DraftReference {
    /// An element of the conversion.
    case draft(EcoreDraft)
    /// An element of another document, as an Ecore reference.
    case external(String)
}

/// The type of a typed element, a super type or a bound.
indirect enum EcoreDraftType {
    /// A classifier of the conversion, with type arguments.
    case classifier(EcoreDraft, arguments: [EcoreDraftType])
    /// A classifier of another metamodel, as an Ecore reference with its type qualifier,
    /// for example `ecore:EDataType http://www.eclipse.org/emf/2002/Ecore#//EString`.
    case external(reference: String, isClass: Bool, name: String, arguments: [EcoreDraftType])
    /// A type parameter of the conversion.
    case typeParameter(EcoreDraft)

    /// Whether the type is a class.
    var isClass: Bool {
        switch self {
        case .classifier(let classifier, _): return classifier.kind == .eClass
        case .external(_, let isClass, _, _): return isClass
        case .typeParameter: return true
        }
    }

    /// The name of the type, for messages and comparisons.
    var name: String {
        switch self {
        case .classifier(let classifier, _): return classifier.qualifiedName
        case .external(_, _, let name, _): return name
        case .typeParameter(let parameter): return parameter.name
        }
    }

    /// Whether the type needs a generic type element rather than a plain type reference.
    var isGeneric: Bool {
        switch self {
        case .classifier(_, let arguments), .external(_, _, _, let arguments): return !arguments.isEmpty
        case .typeParameter: return true
        }
    }

    /// Whether two types stand for the same classifier or type parameter.
    ///
    /// - Parameter other: The other type.
    /// - Returns: `true` if both refer to the same element.
    func isSame(as other: EcoreDraftType?) -> Bool {
        switch (self, other) {
        case (.classifier(let left, _), .classifier(let right, _)?): return left === right
        case (.typeParameter(let left), .typeParameter(let right)?): return left === right
        case (.external(let left, _, _, _), .external(let right, _, _, _)?): return left == right
        default: return false
        }
    }
}

// MARK: - Writing

/// Writes drafts as an Ecore document.
///
/// Every element is written with an `xmi:id`, and references within the document refer to
/// those identifiers, so that the Ecore loader resolves them however the elements are nested.
struct EcoreDraftWriter {
    /// The document being written.
    private var out = XMLTextBuilder()

    /// The Ecore qualifiers of the kinds of classifiers and features.
    private static let qualifiers: [EcoreDraft.Kind: EcoreClassifier] = [
        .eClass: .eClass, .eDataType: .eDataType, .eEnum: .eEnum, .attribute: .eAttribute,
        .reference: .eReference, .operation: .eOperation, .parameter: .eParameter, .literal: .eEnumLiteral,
        .package: .ePackage, .typeParameter: .eTypeParameter,
    ]

    /// Writes root packages as an Ecore document.
    ///
    /// - Parameter packages: The root packages, in order.
    /// - Returns: The text of the document.
    mutating func write(_ packages: [EcoreDraft]) -> String {
        let declarations = [
            (XMIAttribute.xmiVersion.rawValue, CrossReferenceSyntax.xmiVersion),
            (CrossReferenceSyntax.namespaceAttribute(for: CrossReferenceSyntax.xmiPrefix), EcoreURI.xmiNamespace.rawValue),
            (CrossReferenceSyntax.namespaceAttribute(for: CrossReferenceSyntax.xsiPrefix), EcoreURI.xsiNamespace.rawValue),
            (CrossReferenceSyntax.namespaceAttribute(for: CrossReferenceSyntax.ecorePrefix), EcoreURI.ecoreNamespace.rawValue),
        ]
        let packageElement = CrossReferenceSyntax.ecorePrefix + ":" + EcoreClassifier.ePackage.rawValue
        if packages.count == 1 {
            writePackage(packages[0], elementName: packageElement, leading: declarations)
        } else {
            out.open(CrossReferenceSyntax.xmiPrefix + ":" + XMIDocumentSyntax.multipleRootElement, declarations)
            for package in packages { writePackage(package, elementName: packageElement, leading: []) }
            out.close()
        }
        return out.text
    }

    /// Writes a package with its classifiers and subpackages.
    ///
    /// - Parameters:
    ///   - package: The package.
    ///   - elementName: The name of its element.
    ///   - leading: The attributes that precede those of the package.
    private mutating func writePackage(_ package: EcoreDraft, elementName: String, leading: [(String, String)]) {
        var attributes = leading + identity(package)
        attributes.append((EcoreFeatureName.nsURI.rawValue, package.nsURI))
        attributes.append((EcoreFeatureName.nsPrefix.rawValue, package.nsPrefix))
        out.open(elementName, attributes)
        writeAnnotations(package.annotations)
        for classifier in package.classifiers { writeElement(classifier, as: EcoreFeatureName.eClassifiers.rawValue) }
        for subpackage in package.subpackages {
            writePackage(subpackage, elementName: EcoreFeatureName.eSubpackages.rawValue, leading: [])
        }
        out.close()
    }

    /// Writes an element other than a package under a given element name.
    ///
    /// - Parameters:
    ///   - draft: The element.
    ///   - elementName: The name of its element, such as `eClassifiers`.
    private mutating func writeElement(_ draft: EcoreDraft, as elementName: String) {
        if draft.kind == .package {
            writePackage(draft, elementName: elementName, leading: [typeAttribute(draft.kind)])
            return
        }
        var attributes: [(String, String)] = []
        if draft.kind != .typeParameter && draft.kind != .literal && draft.kind != .operation
            && draft.kind != .parameter || elementName == EcoreFeatureName.contents.rawValue
        {
            attributes.append(typeAttribute(draft.kind))
        }
        attributes += identity(draft)
        switch draft.kind {
        case .eClass:
            if draft.isAbstract { attributes.append((XMIAttribute.abstract.rawValue, "true")) }
            if draft.isInterface { attributes.append((XMIAttribute.interface.rawValue, "true")) }
            if let name = draft.instanceClassName { attributes.append((XMIAttribute.instanceClassName.rawValue, name)) }
            if !draft.superTypes.contains(where: \.isGeneric), !draft.superTypes.isEmpty {
                attributes.append((XMIAttribute.eSuperTypes.rawValue, draft.superTypes.map(reference).joined(separator: " ")))
            }
        case .eDataType, .eEnum:
            if let name = draft.instanceClassName { attributes.append((XMIAttribute.instanceClassName.rawValue, name)) }
        case .literal:
            attributes.append((XMIAttribute.value.rawValue, String(draft.value)))
            if let literal = draft.literal { attributes.append((XMIAttribute.literal.rawValue, literal)) }
        case .attribute, .reference, .operation, .parameter:
            attributes += typedAttributes(draft)
        case .package, .typeParameter:
            break
        }
        if draft.kind.isFeature {
            if !draft.changeable { attributes.append((XMIAttribute.changeable.rawValue, "false")) }
            if draft.volatile { attributes.append((XMIAttribute.volatile.rawValue, "true")) }
            if draft.transient { attributes.append((XMIAttribute.transient.rawValue, "true")) }
            if let value = draft.defaultValueLiteral { attributes.append((XMIAttribute.defaultValueLiteral.rawValue, value)) }
            if draft.unsettable { attributes.append((XMIAttribute.unsettable.rawValue, "true")) }
            if draft.derived { attributes.append((XMIAttribute.derived.rawValue, "true")) }
        }
        if draft.kind == .attribute, draft.iD { attributes.append((XMIAttribute.iD.rawValue, "true")) }
        if draft.kind == .reference {
            if draft.containment { attributes.append((XMIAttribute.containment.rawValue, "true")) }
            if !draft.resolveProxies { attributes.append((XMIAttribute.resolveProxies.rawValue, "false")) }
            if let opposite = draft.opposite, opposite.container != nil {
                attributes.append((XMIAttribute.eOpposite.rawValue, local(opposite)))
            }
            if !draft.keys.isEmpty {
                attributes.append((EcoreFeatureName.eKeys.rawValue, draft.keys.map(local).joined(separator: " ")))
            }
        }
        if draft.kind == .operation, !draft.exceptions.isEmpty, !draft.exceptions.contains(where: \.isGeneric) {
            attributes.append((EcoreFeatureName.eExceptions.rawValue, draft.exceptions.map(reference).joined(separator: " ")))
        }
        out.open(elementName, attributes)
        writeAnnotations(draft.annotations)
        for parameter in draft.typeParameters { writeElement(parameter, as: EcoreFeatureName.eTypeParameters.rawValue) }
        for bound in draft.bounds { writeGeneric(bound, as: EcoreFeatureName.eBounds.rawValue) }
        for literal in draft.literals { writeElement(literal, as: EcoreFeatureName.eLiterals.rawValue) }
        for operation in draft.operations { writeElement(operation, as: EcoreFeatureName.eOperations.rawValue) }
        for feature in draft.features { writeElement(feature, as: EcoreFeatureName.eStructuralFeatures.rawValue) }
        for parameter in draft.parameters { writeElement(parameter, as: EcoreFeatureName.eParameters.rawValue) }
        if draft.superTypes.contains(where: \.isGeneric) {
            for superType in draft.superTypes { writeGeneric(superType, as: EcoreFeatureName.eGenericSuperTypes.rawValue) }
        }
        if draft.exceptions.contains(where: \.isGeneric) {
            for exception in draft.exceptions { writeGeneric(exception, as: EcoreFeatureName.eGenericExceptions.rawValue) }
        }
        if let type = draft.type, type.isGeneric { writeGeneric(type, as: EcoreFeatureName.eGenericType.rawValue) }
        out.close()
    }

    /// The multiplicity, ordering, uniqueness and plain type of a typed element.
    ///
    /// - Parameter draft: The typed element.
    /// - Returns: The attributes whose values differ from the Ecore defaults.
    private func typedAttributes(_ draft: EcoreDraft) -> [(String, String)] {
        var attributes: [(String, String)] = []
        if !draft.ordered { attributes.append((XMIAttribute.ordered.rawValue, "false")) }
        if !draft.unique { attributes.append((XMIAttribute.unique.rawValue, "false")) }
        if draft.lowerBound != 0 { attributes.append((XMIAttribute.lowerBound.rawValue, String(draft.lowerBound))) }
        if draft.upperBound != 1 { attributes.append((XMIAttribute.upperBound.rawValue, String(draft.upperBound))) }
        if let type = draft.type, !type.isGeneric { attributes.append((XMIAttribute.eType.rawValue, reference(type))) }
        return attributes
    }

    /// Writes a generic type.
    ///
    /// - Parameters:
    ///   - type: The type.
    ///   - elementName: The name of its element, such as `eGenericType`.
    private mutating func writeGeneric(_ type: EcoreDraftType, as elementName: String) {
        switch type {
        case .typeParameter(let parameter):
            out.empty(elementName, [(EcoreFeatureName.eTypeParameter.rawValue, local(parameter))])
        case .classifier(_, let arguments), .external(_, _, _, let arguments):
            out.open(elementName, [(EcoreFeatureName.eClassifier.rawValue, reference(type))])
            for argument in arguments { writeGeneric(argument, as: EcoreFeatureName.eTypeArguments.rawValue) }
            out.close()
        }
    }

    /// Writes annotations.
    ///
    /// - Parameter annotations: The annotations, in order.
    private mutating func writeAnnotations(_ annotations: [EcoreDraftAnnotation]) {
        for annotation in annotations {
            var attributes = [(EcoreFeatureName.source.rawValue, annotation.source)]
            let references = annotation.references.compactMap { reference -> String? in
                switch reference {
                case .draft(let draft): return draft.isAttached ? local(draft) : nil
                case .external(let text): return text
                }
            }
            if !references.isEmpty {
                attributes.append((EcoreFeatureName.references.rawValue, references.joined(separator: " ")))
            }
            out.open(EcoreFeatureName.eAnnotations.rawValue, attributes)
            for (key, value) in annotation.details {
                out.empty(EcoreFeatureName.details.rawValue, [
                    (EcoreFeatureName.key.rawValue, key), (EcoreFeatureName.value.rawValue, value),
                ])
            }
            writeAnnotations(annotation.annotations)
            for content in annotation.contents { writeElement(content, as: EcoreFeatureName.contents.rawValue) }
            out.close()
        }
    }

    /// The `xsi:type` attribute of an element.
    ///
    /// - Parameter kind: The kind of the element.
    /// - Returns: The attribute, such as `xsi:type="ecore:EClass"`.
    private func typeAttribute(_ kind: EcoreDraft.Kind) -> (String, String) {
        (XMITypeAttribute.xsi.rawValue,
         CrossReferenceSyntax.ecorePrefix + ":" + (Self.qualifiers[kind] ?? .eClass).rawValue)
    }

    /// The identifier and name of an element.
    ///
    /// - Parameter draft: The element.
    /// - Returns: Its `xmi:id` and `name` attributes.
    private func identity(_ draft: EcoreDraft) -> [(String, String)] {
        [(XMIAttribute.xmiId.rawValue, draft.identifier), (XMIAttribute.name.rawValue, draft.name)]
    }

    /// A reference to an element of the document.
    ///
    /// - Parameter draft: The element.
    /// - Returns: `#` followed by its identifier.
    private func local(_ draft: EcoreDraft) -> String {
        String(CrossReferenceSyntax.fragmentSeparator) + draft.identifier
    }

    /// The plain reference to the classifier of a type.
    ///
    /// - Parameter type: The type.
    /// - Returns: The reference to the classifier, or to the type parameter.
    private func reference(_ type: EcoreDraftType) -> String {
        switch type {
        case .classifier(let classifier, _): return local(classifier)
        case .external(let reference, _, _, _): return reference
        case .typeParameter(let parameter): return local(parameter)
        }
    }
}

extension EcoreDraft {
    /// Whether the element is still part of a package of the conversion.
    var isAttached: Bool {
        if kind == .package { return true }
        return container != nil
    }
}
