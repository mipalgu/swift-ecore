//
// GenElement.swift
// GenModel
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation

/// A language-neutral view of one object of a generator model.
///
/// An element wraps a ``DynamicEObject`` that is an instance of a class of the
/// generator metamodel, together with the ``GenModelContext`` it belongs to. It adds
/// the navigation and ordering semantics that every target language needs and that
/// are awkward to express as queries: inherited feature order, feature and classifier
/// numbering, label feature selection, and shortcuts to the properties of the Ecore
/// elements being described.
///
/// An element knows nothing about any target language. Names, types and layout
/// belong to templates.
///
/// Queries that do not apply to the kind of element they are called on return an
/// empty collection, `nil`, or `false`, so they can be called without first
/// testing the kind.
///
/// ## Example
///
/// ```swift
/// for genClass in genPackage.genClasses {
///     for feature in genClass.allGenFeatures {
///         print(genClass.featureID(of: feature) ?? -1, feature.name)
///     }
/// }
/// ```
public struct GenElement: Sendable, Hashable {
    /// The underlying generator model object.
    public let object: DynamicEObject

    /// The context that owns this element.
    public let context: GenModelContext

    /// Creates an element.
    ///
    /// - Parameters:
    ///   - object: A generator model object.
    ///   - context: The context that holds the object's model.
    public init(object: DynamicEObject, context: GenModelContext) {
        self.object = object
        self.context = context
    }

    /// Compares two elements by the identity of their objects.
    public static func == (lhs: GenElement, rhs: GenElement) -> Bool {
        lhs.object.id == rhs.object.id
    }

    /// Hashes the identity of the underlying object.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(object.id)
    }

    // MARK: - Kind

    /// The name of the generator metaclass of this element.
    public var className: String { object.eClass.name }

    /// Checks whether the element's class is, or derives from, a metaclass.
    ///
    /// - Parameter metaclassName: The name of a generator metaclass.
    /// - Returns: `true` if the element is an instance of the metaclass.
    public func isKind(of metaclassName: String) -> Bool {
        object.eClass.name == metaclassName
            || object.eClass.allSuperTypes.contains { $0.name == metaclassName }
    }

    // MARK: - Attribute access

    /// Reads a string-valued attribute of the generator model object.
    ///
    /// The value of an enumeration-typed attribute is the text of its literal, which is what
    /// `.genmodel` documents contain (`17.0` rather than the literal name `JDK170`). Use
    /// ``literalName(_:)`` to read the name of the literal.
    ///
    /// - Parameter feature: The attribute name.
    /// - Returns: The value, or `nil` if the attribute is not set.
    public func stringValue(_ feature: String) -> String? {
        let text: String?
        switch object.eGet(feature) {
        case let string as String: text = string
        case let bool as Bool: text = bool ? "true" : "false"
        case let int as Int: text = String(int)
        case let double as Double: text = String(double)
        default: text = nil
        }
        guard let text, let eEnum = enumeration(of: feature) else { return text }
        return eEnum.text(forStoredValue: text)
    }

    /// Reads the name of the literal that an enumeration-typed attribute holds.
    ///
    /// - Parameter feature: The attribute name.
    /// - Returns: The name of the literal, or `nil` if the attribute is not set. A value
    ///   that names no literal is returned as it is.
    public func literalName(_ feature: String) -> String? {
        guard let text = stringValue(feature) else { return nil }
        guard let eEnum = enumeration(of: feature) else { return text }
        return eEnum.storedValue(forText: text)
    }

    /// The enumeration that the type of an attribute names, if it has one.
    private func enumeration(of feature: String) -> EEnum? {
        (object.eClass.getStructuralFeature(name: feature) as? EAttribute)?.eType as? EEnum
    }

    /// Reads a boolean attribute of the generator model object.
    ///
    /// - Parameters:
    ///   - feature: The attribute name.
    ///   - defaultValue: The value to return if the attribute is not set.
    /// - Returns: The attribute value, or the default value.
    public func boolValue(_ feature: String, default defaultValue: Bool = false) -> Bool {
        switch object.eGet(feature) {
        case let bool as Bool: return bool
        case let string as String: return string.lowercased() == "true"
        default: return defaultValue
        }
    }

    /// Reads an integer attribute of the generator model object.
    ///
    /// - Parameters:
    ///   - feature: The attribute name.
    ///   - defaultValue: The value to return if the attribute is not set.
    /// - Returns: The attribute value, or the default value.
    public func intValue(_ feature: String, default defaultValue: Int = 0) -> Int {
        switch object.eGet(feature) {
        case let int as Int: return int
        case let string as String: return Int(string) ?? defaultValue
        default: return defaultValue
        }
    }

    /// Reads a many-valued string attribute of the generator model object.
    ///
    /// - Parameter feature: The attribute name.
    /// - Returns: The values, or an empty array.
    public func stringValues(_ feature: String) -> [String] {
        switch object.eGet(feature) {
        case let strings as [String]: return strings
        case let string as String: return [string]
        default: return []
        }
    }

    // MARK: - Navigation

    /// The elements held by a reference of this element.
    ///
    /// - Parameter feature: The reference name.
    /// - Returns: The referenced elements in order; unresolved references are omitted.
    public func elements(_ feature: String) -> [GenElement] {
        GenModelContext.identifiers(of: object, feature: feature).compactMap {
            context.element(id: $0)
        }
    }

    /// The element that contains this element.
    public var container: GenElement? {
        context.parentID(of: object.id).flatMap { context.element(id: $0) }
    }

    /// The nearest enclosing element, starting with this element, of a metaclass.
    ///
    /// - Parameter metaclassName: The name of a generator metaclass.
    /// - Returns: This element or the nearest ancestor of that kind, or `nil`.
    public func enclosing(_ metaclassName: String) -> GenElement? {
        var current: GenElement? = self
        while let candidate = current {
            if candidate.isKind(of: metaclassName) { return candidate }
            current = candidate.container
        }
        return nil
    }

    /// The generator model that owns this element.
    public var genModel: GenElement? { enclosing(GenModelConstants.ClassName.genModel) }

    /// The generator package that owns this element, or the element itself if it is a package.
    public var genPackage: GenElement? { enclosing(GenModelConstants.ClassName.genPackage) }

    /// The generator package that contains this package as a nested package.
    public var parentGenPackage: GenElement? {
        guard isKind(of: GenModelConstants.ClassName.genPackage) else { return nil }
        return container?.enclosing(GenModelConstants.ClassName.genPackage)
    }

    /// The generator class that owns this feature, operation or parameter.
    public var genClass: GenElement? { enclosing(GenModelConstants.ClassName.genClass) }

    /// The generator packages of a generator model, in model order.
    public var genPackages: [GenElement] { elements(GenModelConstants.FeatureName.genPackages) }

    /// The generator packages that a generator model refers to but does not own.
    public var usedGenPackages: [GenElement] {
        elements(GenModelConstants.FeatureName.usedGenPackages)
    }

    /// The nested generator packages of a package.
    public var nestedGenPackages: [GenElement] {
        elements(GenModelConstants.FeatureName.nestedGenPackages)
    }

    /// The packages of a model, with nested packages following their parent, depth first.
    public var allGenPackages: [GenElement] {
        let direct = isKind(of: GenModelConstants.ClassName.genModel) ? genPackages : nestedGenPackages
        return direct.flatMap { [$0] + $0.allGenPackages }
    }

    /// The generator classes of a package, in model order.
    public var genClasses: [GenElement] { elements(GenModelConstants.FeatureName.genClasses) }

    /// The generator enumerations of a package, in model order.
    public var genEnums: [GenElement] { elements(GenModelConstants.FeatureName.genEnums) }

    /// The generator data types of a package, in model order.
    public var genDataTypes: [GenElement] { elements(GenModelConstants.FeatureName.genDataTypes) }

    /// The generator features declared by a class, in model order.
    public var genFeatures: [GenElement] { elements(GenModelConstants.FeatureName.genFeatures) }

    /// The generator operations declared by a class, in model order.
    public var genOperations: [GenElement] { elements(GenModelConstants.FeatureName.genOperations) }

    /// The generator parameters of an operation, in model order.
    public var genParameters: [GenElement] { elements(GenModelConstants.FeatureName.genParameters) }

    /// The generator literals of an enumeration, in model order.
    public var genEnumLiterals: [GenElement] {
        elements(GenModelConstants.FeatureName.genEnumLiterals)
    }

    /// The generator type parameters of a classifier or operation.
    public var genTypeParameters: [GenElement] {
        elements(GenModelConstants.FeatureName.genTypeParameters)
    }

    /// The generator annotations of this element.
    public var genAnnotations: [GenElement] {
        elements(GenModelConstants.FeatureName.genAnnotations)
    }

    // MARK: - Ecore elements

    /// The target identifier of an `ecore*` reference.
    private func ecoreTargetID(_ feature: String) -> EUUID? {
        GenModelContext.identifiers(of: object, feature: feature).first
    }

    /// The Ecore package described by a generator package.
    public var ecorePackage: EPackage? {
        ecoreTargetID(GenModelConstants.FeatureName.ecorePackage).flatMap { context.ecorePackage(id: $0) }
    }

    /// The Ecore class described by a generator class.
    public var ecoreClass: EClass? {
        ecoreTargetID(GenModelConstants.FeatureName.ecoreClass).flatMap { context.ecoreClass(id: $0) }
    }

    /// The Ecore feature described by a generator feature.
    public var ecoreFeature: (any EStructuralFeature)? {
        ecoreTargetID(GenModelConstants.FeatureName.ecoreFeature).flatMap {
            context.ecoreFeature(id: $0)
        }
    }

    /// The Ecore enumeration described by a generator enumeration.
    public var ecoreEnum: EEnum? {
        ecoreTargetID(GenModelConstants.FeatureName.ecoreEnum).flatMap { context.ecoreEnum(id: $0) }
    }

    /// The Ecore enumeration literal described by a generator literal.
    public var ecoreEnumLiteral: EEnumLiteral? {
        ecoreTargetID(GenModelConstants.FeatureName.ecoreEnumLiteral).flatMap {
            context.ecoreEnumLiteral(id: $0)
        }
    }

    /// The Ecore data type described by a generator data type.
    public var ecoreDataType: EDataType? {
        ecoreTargetID(GenModelConstants.FeatureName.ecoreDataType).flatMap {
            context.ecoreDataType(id: $0)
        }
    }

    /// The name of the Ecore element that this element describes.
    ///
    /// For a generator model, which describes no single element, the model name is returned.
    /// Operations, parameters and type parameters have no native Ecore representation, so
    /// their names are taken from the last segment of the textual reference when it is name-based.
    /// The name is empty if the Ecore element cannot be determined.
    public var name: String {
        if let eClass = ecoreClass { return eClass.name }
        if let feature = ecoreFeature { return feature.name }
        if let eEnum = ecoreEnum { return eEnum.name }
        if let literal = ecoreEnumLiteral { return literal.name }
        if let dataType = ecoreDataType { return dataType.name }
        if let package = ecorePackage { return package.name }
        if isKind(of: GenModelConstants.ClassName.genModel) {
            return stringValue(GenModelConstants.FeatureName.modelName) ?? ""
        }
        for feature in [
            GenModelConstants.FeatureName.ecoreOperation,
            GenModelConstants.FeatureName.ecoreParameter,
            GenModelConstants.FeatureName.ecoreTypeParameter,
        ] {
            if let reference = object.eGet(feature) as? String,
                let referencedName = EcoreReference(reference)?.lastSegmentName
            {
                return referencedName
            }
        }
        return ""
    }

    // MARK: - Naming

    /// The name with its first character capitalised.
    public var capName: String { GenModelNaming.capName(name) }

    /// The name with its first character lowercased.
    public var uncapName: String { GenModelNaming.uncapName(name) }

    /// The name with its leading capitals lowercased, keeping the capital that begins a further word.
    public var uncapPrefixedName: String { GenModelNaming.uncapPrefixedName(name) }

    /// The name in upper case, with words separated by underscores.
    public var upperName: String { GenModelNaming.upperName(name) }
}
