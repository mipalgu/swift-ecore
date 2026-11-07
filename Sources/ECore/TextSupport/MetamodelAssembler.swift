//
// MetamodelAssembler.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import OrderedCollections
import Foundation

/// Resolves the names that a textual notation uses for classifiers it does not declare.
///
/// Each notation has its own spelling for the built-in types of Ecore, such as `String`
/// or `int`, and its own way of naming classifiers in other packages, so the assembler
/// asks the notation for any name it cannot find among the declared classifiers.
struct ExternalTypeNames {
    /// Returns the classifier that a name stands for, or `nil` if the notation knows none.
    var classifier: @Sendable (String) -> (any EClassifier)?

    /// Rewrites a type name through the imports of a document, before it is looked up.
    var aliases: [String: String]

    /// Creates a resolver for external type names.
    ///
    /// - Parameters:
    ///   - aliases: The qualified name that each imported simple name stands for.
    ///   - classifier: The lookup of built-in and other external names.
    init(aliases: [String: String] = [:], classifier: @escaping @Sendable (String) -> (any EClassifier)?) {
        self.aliases = aliases
        self.classifier = classifier
    }
}

/// Builds native Ecore packages from the declarations of a textual notation.
///
/// The assembler is shared by every notation that the package reads. It allocates an
/// identifier for every element, resolves type names (type parameters first, then
/// classifiers of the enclosing packages from the innermost outwards, then qualified
/// names, then the names that the notation itself knows), links opposites and keys, and
/// finally refreshes the class snapshots with ``MetamodelLinker``. A name that cannot be
/// resolved becomes a placeholder classifier that keeps the name as written, and is
/// reported, so that the metamodel is always complete.
struct MetamodelAssembler {
    /// A classifier declared in the document, with the package that holds it.
    private struct ClassifierEntry {
        /// The identifier given to the classifier.
        let id: EUUID
        /// The draft that declares the classifier.
        let draft: DraftClassifier
        /// The qualified key of the package that holds the classifier.
        let packageKey: String
    }

    /// A type parameter that is in scope, with the scopes in which its bound resolves.
    private struct ParameterBinding {
        /// The identifier given to the type parameter.
        let id: EUUID
        /// The draft of the bound of the type parameter, if it has one.
        let bound: DraftType?
        /// The scopes in which the bound is resolved.
        let scopes: [String]
    }

    /// The outcome of resolving a type name.
    private enum Resolved {
        /// The name denotes a classifier.
        case classifier(any EClassifier)
        /// The name denotes a type parameter.
        ///
        /// - Parameters:
        ///   - EUUID: The identifier of the type parameter.
        ///   - bound: The resolved bound of the type parameter, if it has one.
        case parameter(EUUID, bound: (any EClassifier)?)
        /// The name could not be resolved.
        case unresolved
    }

    /// The kind of classifier that a placeholder stands in for.
    private enum PlaceholderKind {
        /// A placeholder for a class that could not be resolved.
        case `class`
        /// A placeholder for a data type that could not be resolved.
        case dataType
    }

    /// The factory that creates diagnostics.
    private let factory: DiagnosticFactory
    /// The resolver for names that the document does not declare.
    private let external: ExternalTypeNames
    /// The severity of a type name that cannot be resolved.
    private let unresolvedSeverity: DiagnosticSeverity

    /// The diagnostics found so far.
    private var diagnostics: [SourceDiagnostic] = []
    /// The classifiers of the document, by qualified name.
    private var entries: [String: ClassifierEntry] = [:]
    /// The class drafts, by identifier.
    private var classDrafts: [EUUID: DraftClassifier] = [:]
    /// The scopes in which the names of each class resolve, by identifier.
    private var classScopes: [EUUID: [String]] = [:]
    /// The identifiers given to the features of each class, by feature name.
    private var featureIDs: [EUUID: [String: EUUID]] = [:]
    /// The data types built so far, by identifier.
    private var builtDataTypes: [EUUID: any EClassifier] = [:]
    /// The classes built so far, by identifier.
    private var builtClasses: [EUUID: EClass] = [:]
    /// The placeholder classifiers created so far, by key.
    private var placeholders: [String: any EClassifier] = [:]
    /// The identifiers of the packages, by qualified name.
    private var packageIDs: [String: EUUID] = [:]
    /// The identifiers of the supertypes of each class.
    private var superTypeIDs: [EUUID: [EUUID]] = [:]
    /// The identifiers of the classes in order of declaration.
    private var classOrder: [EUUID] = []

    /// Creates an assembler.
    ///
    /// - Parameters:
    ///   - factory: The factory that creates diagnostics in the namespace of the notation.
    ///   - external: The resolver for names that the document does not declare.
    ///   - unresolvedSeverity: The severity of a type name that cannot be resolved.
    init(
        factory: DiagnosticFactory, external: ExternalTypeNames, unresolvedSeverity: DiagnosticSeverity = .error
    ) {
        self.factory = factory
        self.external = external
        self.unresolvedSeverity = unresolvedSeverity
    }

    /// Builds the native packages of a document.
    ///
    /// - Parameters:
    ///   - drafts: The packages of the document.
    ///   - factory: The factory that creates diagnostics.
    ///   - external: The resolver for names that the document does not declare.
    ///   - unresolvedSeverity: The severity of a type name that cannot be resolved.
    /// - Returns: The native packages and the diagnostics found while building them.
    static func assemble(
        _ drafts: [DraftPackage], factory: DiagnosticFactory, external: ExternalTypeNames,
        unresolvedSeverity: DiagnosticSeverity = .error
    ) -> (packages: [EPackage], diagnostics: [SourceDiagnostic]) {
        var assembler = MetamodelAssembler(factory: factory, external: external, unresolvedSeverity: unresolvedSeverity)
        let packages = assembler.assemble(drafts)
        return (packages, assembler.diagnostics)
    }

    /// Builds the native packages of a document.
    ///
    /// - Parameter drafts: The packages of the document.
    /// - Returns: The native packages, in the order of the drafts.
    mutating func assemble(_ drafts: [DraftPackage]) -> [EPackage] {
        for draft in drafts { index(draft, parentKey: nil) }
        for draft in drafts { buildDataTypes(of: draft, key: Self.rootKey(of: draft)) }
        for identifier in classOrder { resolveSuperTypeIDs(of: identifier) }
        for identifier in classOrder { buildClass(identifier) }
        for identifier in classOrder { linkReferences(of: identifier) }
        let packages = drafts.map { package($0, key: Self.rootKey(of: $0)) }
        return MetamodelLinker.relinked(packages)
    }

    /// The diagnostics found so far.
    var foundDiagnostics: [SourceDiagnostic] { diagnostics }

    // MARK: Indexing

    /// The key of a top-level package.
    ///
    /// - Parameter draft: The package.
    /// - Returns: The qualified name of the package, or its name if it has none.
    private static func rootKey(of draft: DraftPackage) -> String {
        draft.qualifiedName ?? draft.name
    }

    /// Joins a scope and a name.
    ///
    /// - Parameters:
    ///   - scope: The enclosing scope, which may be empty.
    ///   - name: The name to qualify.
    /// - Returns: The qualified name.
    private static func qualified(_ scope: String, _ name: String) -> String {
        scope.isEmpty ? name : scope + "." + name
    }

    /// Records the classifiers of a package and its subpackages.
    ///
    /// - Parameters:
    ///   - draft: The package to index.
    ///   - parentKey: The qualified key of the enclosing package, if any.
    private mutating func index(_ draft: DraftPackage, parentKey: String?) {
        let key = parentKey.map { Self.qualified($0, draft.name) } ?? Self.rootKey(of: draft)
        if packageIDs[key] != nil {
            diagnostics.append(factory.error(
                .duplicateName, "Duplicate package name '\(draft.name)'", at: draft.location.nameRange))
        }
        packageIDs[key] = packageIDs[key] ?? EUUID()
        for classifier in draft.classifiers {
            let classifierKey = Self.qualified(key, classifier.name)
            guard entries[classifierKey] == nil else {
                diagnostics.append(factory.error(
                    .duplicateName, "Duplicate classifier name '\(classifier.name)' in package '\(draft.name)'",
                    at: classifier.location.nameRange))
                continue
            }
            let identifier = EUUID()
            entries[classifierKey] = ClassifierEntry(id: identifier, draft: classifier, packageKey: key)
            guard classifier.kind == .class else { continue }
            classDrafts[identifier] = classifier
            classScopes[identifier] = Self.scopes(of: key)
            classOrder.append(identifier)
            var features: [String: EUUID] = [:]
            for feature in classifier.features {
                if features[feature.name] != nil {
                    diagnostics.append(factory.error(
                        .duplicateName, "Duplicate feature name '\(feature.name)' in class '\(classifier.name)'",
                        at: feature.location.nameRange))
                    continue
                }
                features[feature.name] = EUUID()
            }
            featureIDs[identifier] = features
        }
        for subpackage in draft.subpackages { index(subpackage, parentKey: key) }
    }

    /// The scopes visible from a package, innermost first.
    private static func scopes(of key: String) -> [String] {
        var result: [String] = []
        var current = key
        while true {
            result.append(current)
            guard let dot = current.lastIndex(of: ".") else { break }
            current = String(current[..<dot])
        }
        result.append("")
        return result
    }

    // MARK: Resolution

    /// Finds a classifier by name.
    ///
    /// - Parameters:
    ///   - name: The name as written.
    ///   - scopes: The scopes to search, innermost first.
    /// - Returns: The classifier entry, or `nil` if no scope declares the name.
    private func entry(named name: String, scopes: [String]) -> ClassifierEntry? {
        for scope in scopes {
            if let found = entries[Self.qualified(scope, name)] { return found }
        }
        if let first = name.split(separator: ".", maxSplits: 1).first, let alias = external.aliases[String(first)] {
            let rest = name.dropFirst(first.count)
            if let found = entries[alias + rest] { return found }
        }
        return nil
    }

    /// The native classifier that stands for an entry.
    ///
    /// - Parameter entry: The classifier entry.
    /// - Returns: The built data type or class, or a proxy if the entry is not yet built.
    private func reference(to entry: ClassifierEntry) -> any EClassifier {
        if let dataType = builtDataTypes[entry.id] { return dataType }
        switch entry.draft.kind {
        case .class:
            return EClass(
                id: entry.id, name: entry.draft.name, isAbstract: entry.draft.isAbstract,
                isInterface: entry.draft.isInterface)
        case .enumeration:
            return EEnum(id: entry.id, name: entry.draft.name)
        case .dataType:
            return EDataType(id: entry.id, name: entry.draft.name)
        }
    }

    /// Resolves a name to a classifier or type parameter.
    ///
    /// - Parameters:
    ///   - name: The name as written.
    ///   - scopes: The scopes to search, innermost first.
    ///   - parameters: The type parameters in scope, by name.
    /// - Returns: What the name denotes.
    private func resolve(_ name: String, scopes: [String], parameters: [String: ParameterBinding]) -> Resolved {
        if let binding = parameters[name] {
            return .parameter(binding.id, bound: binding.bound.flatMap { classifier(of: $0, scopes: binding.scopes) })
        }
        if let found = entry(named: name, scopes: scopes) { return .classifier(reference(to: found)) }
        let aliased = external.aliases[name] ?? name
        if let builtin = external.classifier(aliased) { return .classifier(builtin) }
        return .unresolved
    }

    /// The classifier of a type without reporting anything, for the bounds of parameters.
    private func classifier(of type: DraftType, scopes: [String]) -> (any EClassifier)? {
        if case .classifier(let found) = resolve(type.name, scopes: scopes, parameters: [:]) { return found }
        return nil
    }

    /// Provides a placeholder for a type that cannot be resolved, and reports it.
    ///
    /// - Parameters:
    ///   - type: The type as written.
    ///   - kind: The kind of classifier to stand in for.
    /// - Returns: The placeholder classifier.
    private mutating func placeholder(for type: DraftType, kind: PlaceholderKind) -> any EClassifier {
        let name = external.aliases[type.name] ?? type.name
        let key = (kind == .class ? "class:" : "data:") + name
        diagnostics.append(SourceDiagnostic(
            severity: unresolvedSeverity, code: factory.code(.unresolvedType),
            message: "Cannot resolve type '\(type.name)'", range: type.range, document: factory.document))
        if let existing = placeholders[key] { return existing }
        let created: any EClassifier = kind == .class ? EClass(name: name) : EDataType(name: name)
        placeholders[key] = created
        return created
    }

    /// Converts a type into a raw classifier and a generic type.
    ///
    /// - Returns: The raw classifier, and the generic type when the type is parameterised.
    private mutating func typed(
        _ type: DraftType, scopes: [String], parameters: [String: ParameterBinding], kind: PlaceholderKind
    ) -> (classifier: any EClassifier, generic: EGenericType?) {
        let generic = genericType(type, scopes: scopes, parameters: parameters, kind: kind)
        if let parameter = generic.eTypeParameter {
            let binding = parameters.values.first { $0.id == parameter }
            let bound = binding?.bound.flatMap { classifier(of: $0, scopes: binding?.scopes ?? scopes) }
            return (bound ?? Self.javaObject, generic)
        }
        let raw = generic.eClassifier ?? Self.javaObject
        return (raw, generic.isParameterised ? generic : nil)
    }

    /// The Java object data type, used where no type can be determined.
    private static var javaObject: any EClassifier {
        EcorePackage.dataType(.eJavaObject) ?? EDataType(name: EcoreDataType.eJavaObject.rawValue)
    }

    /// Builds a generic type from a draft type.
    ///
    /// - Parameters:
    ///   - type: The type as written.
    ///   - scopes: The scopes in which names resolve.
    ///   - parameters: The type parameters in scope, by name.
    ///   - kind: The kind of placeholder to use for an unresolved name.
    /// - Returns: The generic type.
    private mutating func genericType(
        _ type: DraftType, scopes: [String], parameters: [String: ParameterBinding], kind: PlaceholderKind
    ) -> EGenericType {
        switch type.wildcard {
        case .unbounded:
            return EGenericType()
        case .upper:
            return EGenericType(eUpperBound: type.bounds.first.map {
                genericType($0, scopes: scopes, parameters: parameters, kind: .class)
            })
        case .lower:
            return EGenericType(eLowerBound: type.bounds.first.map {
                genericType($0, scopes: scopes, parameters: parameters, kind: .class)
            })
        case nil:
            break
        }
        let arguments = type.arguments.map { genericType($0, scopes: scopes, parameters: parameters, kind: .class) }
        switch resolve(type.name, scopes: scopes, parameters: parameters) {
        case .parameter(let identifier, _):
            return EGenericType(eTypeParameter: identifier)
        case .classifier(let found):
            return EGenericType(eClassifier: found, eTypeArguments: arguments)
        case .unresolved:
            return EGenericType(eClassifier: placeholder(for: type, kind: kind), eTypeArguments: arguments)
        }
    }

    /// Builds type parameters from their drafts.
    ///
    /// - Parameters:
    ///   - drafts: The drafts of the type parameters.
    ///   - scopes: The scopes in which bounds resolve.
    ///   - outer: The type parameters already in scope, by name.
    /// - Returns: The type parameters and the bindings that include them.
    private mutating func typeParameters(
        _ drafts: [DraftTypeParameter], scopes: [String], outer: [String: ParameterBinding]
    ) -> (parameters: [ETypeParameter], bindings: [String: ParameterBinding]) {
        var bindings = outer
        var identifiers: [EUUID] = []
        for draft in drafts {
            let identifier = EUUID()
            identifiers.append(identifier)
            bindings[draft.name] = ParameterBinding(id: identifier, bound: draft.bounds.first, scopes: scopes)
        }
        let parameters = zip(drafts, identifiers).map { draft, identifier in
            ETypeParameter(
                id: identifier, name: draft.name,
                eBounds: draft.bounds.map { genericType($0, scopes: scopes, parameters: bindings, kind: .class) },
                eAnnotations: annotations(draft.annotations))
        }
        return (parameters, bindings)
    }

    // MARK: Annotations

    /// Builds annotations from their drafts.
    ///
    /// - Parameter drafts: The annotation drafts.
    /// - Returns: The annotations, in order.
    private func annotations(_ drafts: [DraftAnnotation]) -> [EAnnotation] {
        drafts.map { draft in
            var details: OrderedDictionary<String, String> = [:]
            for detail in draft.details { details[detail.key] = detail.value }
            return EAnnotation(source: draft.source, orderedDetails: details)
        }
    }

    // MARK: Data types

    /// Builds the data types and enumerations of a package and its subpackages.
    ///
    /// - Parameters:
    ///   - draft: The package.
    ///   - key: The qualified key of the package.
    private mutating func buildDataTypes(of draft: DraftPackage, key: String) {
        let scopes = Self.scopes(of: key)
        for classifier in draft.classifiers where classifier.kind != .class {
            guard let entry = entries[Self.qualified(key, classifier.name)], entry.draft == classifier else { continue }
            let (parameters, _) = typeParameters(classifier.typeParameters, scopes: scopes, outer: [:])
            let instance = Self.instanceNames(classifier.instanceTypeName)
            switch classifier.kind {
            case .enumeration:
                var literals: [EEnumLiteral] = []
                var seen: Set<String> = []
                for literal in classifier.literals {
                    guard seen.insert(literal.name).inserted else {
                        diagnostics.append(factory.error(
                            .duplicateName, "Duplicate literal name '\(literal.name)' in enumeration '\(classifier.name)'",
                            at: literal.location.nameRange))
                        continue
                    }
                    literals.append(EEnumLiteral(
                        name: literal.name, value: literal.value, literal: literal.literal ?? literal.name,
                        eAnnotations: annotations(literal.annotations)))
                }
                var eEnum = EEnum(
                    id: entry.id, name: classifier.name, literals: literals,
                    eAnnotations: annotations(classifier.annotations))
                eEnum.serialisable = classifier.serialisable
                eEnum.instanceClassName = instance.className
                eEnum.instanceTypeName = instance.typeName
                eEnum.eTypeParameters = parameters
                builtDataTypes[entry.id] = eEnum
            case .dataType:
                var dataType = EDataType(
                    id: entry.id, name: classifier.name, serialisable: classifier.serialisable,
                    instanceClassName: instance.className, eAnnotations: annotations(classifier.annotations))
                dataType.instanceClassName = instance.className
                dataType.instanceTypeName = instance.typeName
                dataType.eTypeParameters = parameters
                builtDataTypes[entry.id] = dataType
            case .class:
                break
            }
        }
        for subpackage in draft.subpackages { buildDataTypes(of: subpackage, key: Self.qualified(key, subpackage.name)) }
    }

    /// Splits an instance type name into its erased class name and, if generic, its full type name.
    ///
    /// - Parameter text: The instance type name as written.
    /// - Returns: The class name, and the type name when it differs from the class name.
    static func instanceNames(_ text: String?) -> (className: String?, typeName: String?) {
        guard let text, !text.isEmpty else { return (nil, nil) }
        guard let open = text.firstIndex(of: "<") else { return (text, nil) }
        var erased = String(text[..<open]).trimmingCharacters(in: .whitespaces)
        if let close = text.lastIndex(of: ">"), close < text.endIndex {
            erased += text[text.index(after: close)...].trimmingCharacters(in: .whitespaces)
        }
        return (erased, text)
    }

    // MARK: Classes

    /// Resolves the supertypes of a class to identifiers.
    ///
    /// - Parameter identifier: The identifier of the class.
    private mutating func resolveSuperTypeIDs(of identifier: EUUID) {
        guard let draft = classDrafts[identifier], let scopes = classScopes[identifier] else { return }
        superTypeIDs[identifier] = draft.superTypes.compactMap { type in
            entry(named: type.name, scopes: scopes).map(\.id)
        }
    }

    /// Builds a class without resolving its references.
    ///
    /// - Parameter identifier: The identifier of the class.
    private mutating func buildClass(_ identifier: EUUID) {
        guard let draft = classDrafts[identifier], let scopes = classScopes[identifier] else { return }
        let (parameters, bindings) = typeParameters(draft.typeParameters, scopes: scopes, outer: [:])
        var superTypes: [EClass] = []
        var genericSuperTypes: [EGenericType] = []
        for type in draft.superTypes {
            let generic = genericType(type, scopes: scopes, parameters: bindings, kind: .class)
            genericSuperTypes.append(generic)
            if let eClass = generic.eClassifier as? EClass {
                superTypes.append(eClass)
            } else if generic.eClassifier != nil || generic.eTypeParameter != nil {
                diagnostics.append(factory.error(
                    .unresolvedType, "The supertype '\(type.text)' of '\(draft.name)' is not a class", at: type.range))
            }
        }
        var eClass = EClass(
            id: identifier, name: draft.name, isAbstract: draft.isAbstract, isInterface: draft.isInterface,
            eSuperTypes: superTypes, eAnnotations: annotations(draft.annotations))
        let instance = Self.instanceNames(draft.instanceTypeName)
        eClass.instanceClassName = instance.className
        eClass.instanceTypeName = instance.typeName
        eClass.eTypeParameters = parameters
        if genericSuperTypes.contains(where: { $0.isParameterised }) { eClass.eGenericSuperTypes = genericSuperTypes }
        let identifiers = featureIDs[identifier] ?? [:]
        var seen: Set<String> = []
        var features: [any EStructuralFeature] = []
        for feature in draft.features {
            guard let featureID = identifiers[feature.name], seen.insert(feature.name).inserted else { continue }
            features.append(structuralFeature(feature, id: featureID, scopes: scopes, parameters: bindings))
        }
        eClass.eStructuralFeatures = features
        eClass.eOperations = draft.operations.map { operation($0, scopes: scopes, parameters: bindings) }
        builtClasses[identifier] = eClass
    }

    /// Builds an attribute or reference from its draft.
    ///
    /// - Parameters:
    ///   - draft: The draft of the feature.
    ///   - id: The identifier to give the feature.
    ///   - scopes: The scopes in which names resolve.
    ///   - parameters: The type parameters in scope, by name.
    /// - Returns: The structural feature.
    private mutating func structuralFeature(
        _ draft: DraftFeature, id: EUUID, scopes: [String], parameters: [String: ParameterBinding]
    ) -> any EStructuralFeature {
        let annotations = annotations(draft.annotations)
        var kind = draft.kind
        if kind == .inferred {
            let (type, generic) = typed(draft.type, scopes: scopes, parameters: parameters, kind: .class)
            kind = type is EClass && generic?.eTypeParameter == nil ? .reference : .attribute
            diagnostics.removeAll { $0.code == factory.code(.unresolvedType) && $0.range == draft.type.range }
        }
        switch kind {
        case .attribute, .inferred:
            let (type, generic) = typed(draft.type, scopes: scopes, parameters: parameters, kind: .dataType)
            var attribute = EAttribute(
                id: id, name: draft.name, eType: type, lowerBound: draft.lowerBound, upperBound: draft.upperBound,
                changeable: draft.changeable, volatile: draft.volatile, transient: draft.transient,
                defaultValueLiteral: draft.defaultValue, isID: draft.isID, eAnnotations: annotations,
                ordered: draft.ordered, unique: draft.unique, unsettable: draft.unsettable, derived: draft.derived)
            attribute.eGenericType = generic
            return attribute
        case .reference:
            let (type, generic) = typed(draft.type, scopes: scopes, parameters: parameters, kind: .class)
            var reference = EReference(
                id: id, name: draft.name, eType: type, lowerBound: draft.lowerBound, upperBound: draft.upperBound,
                changeable: draft.changeable, volatile: draft.volatile, transient: draft.transient,
                containment: draft.containment, resolveProxies: draft.resolveProxies, eAnnotations: annotations,
                ordered: draft.ordered, unique: draft.unique, unsettable: draft.unsettable, derived: draft.derived)
            reference.defaultValueLiteral = draft.defaultValue
            reference.eGenericType = generic
            return reference
        }
    }

    /// Builds an operation from its draft.
    ///
    /// - Parameters:
    ///   - draft: The draft of the operation.
    ///   - scopes: The scopes in which names resolve.
    ///   - outer: The type parameters already in scope, by name.
    /// - Returns: The operation.
    private mutating func operation(
        _ draft: DraftOperation, scopes: [String], parameters outer: [String: ParameterBinding]
    ) -> EOperation {
        let (typeParameters, bindings) = typeParameters(draft.typeParameters, scopes: scopes, outer: outer)
        var seen: Set<String> = []
        var parameters: [EParameter] = []
        for draftParameter in draft.parameters {
            if !seen.insert(draftParameter.name).inserted {
                diagnostics.append(factory.error(
                    .duplicateName, "Duplicate parameter name '\(draftParameter.name)' in operation '\(draft.name)'",
                    at: draftParameter.location.nameRange))
            }
            let (type, generic) = typed(draftParameter.type, scopes: scopes, parameters: bindings, kind: .class)
            var parameter = EParameter(
                name: draftParameter.name, eType: type, lowerBound: draftParameter.lowerBound,
                upperBound: draftParameter.upperBound, ordered: draftParameter.ordered, unique: draftParameter.unique,
                eAnnotations: annotations(draftParameter.annotations))
            parameter.eGenericType = generic
            parameters.append(parameter)
        }
        var returnType: (any EClassifier)?
        var returnGeneric: EGenericType?
        if let type = draft.returnType {
            (returnType, returnGeneric) = typed(type, scopes: scopes, parameters: bindings, kind: .class)
        }
        var exceptions: [any EClassifier] = []
        var genericExceptions: [EGenericType] = []
        for type in draft.exceptions {
            let generic = genericType(type, scopes: scopes, parameters: bindings, kind: .class)
            genericExceptions.append(generic)
            if let raw = generic.eClassifier { exceptions.append(raw) }
        }
        var result = EOperation(
            name: draft.name, eType: returnType, lowerBound: draft.lowerBound, upperBound: draft.upperBound,
            ordered: draft.ordered, unique: draft.unique, eParameters: parameters, eExceptions: exceptions,
            eAnnotations: annotations(draft.annotations))
        result.eGenericType = returnGeneric
        result.eTypeParameters = typeParameters
        if genericExceptions.contains(where: { $0.isParameterised }) { result.eGenericExceptions = genericExceptions }
        return result
    }

    // MARK: Opposites and keys

    /// Finds a feature of a class or of its supertypes by name.
    private func feature(named name: String, in identifier: EUUID, visited: inout Set<EUUID>) -> (EUUID, DraftFeature)? {
        guard visited.insert(identifier).inserted, let draft = classDrafts[identifier] else { return nil }
        if let found = draft.features.first(where: { $0.name == name }), let featureID = featureIDs[identifier]?[name] {
            return (featureID, found)
        }
        for parent in superTypeIDs[identifier] ?? [] {
            if let found = feature(named: name, in: parent, visited: &visited) { return found }
        }
        return nil
    }

    /// Links the references of a class to their opposites and keys.
    ///
    /// - Parameter identifier: The identifier of the class.
    private mutating func linkReferences(of identifier: EUUID) {
        guard var eClass = builtClasses[identifier], let draft = classDrafts[identifier] else { return }
        var features = eClass.eStructuralFeatures
        for index in features.indices {
            guard var reference = features[index] as? EReference,
                let source = draft.features.first(where: { $0.name == reference.name })
            else { continue }
            let target = reference.eType.id
            if let opposite = source.opposite {
                var visited: Set<EUUID> = []
                if classDrafts[target] != nil, let (oppositeID, oppositeDraft) = feature(named: opposite, in: target, visited: &visited),
                    oppositeDraft.kind == .reference
                {
                    reference.opposite = oppositeID
                    reference.container = oppositeDraft.containment
                } else {
                    diagnostics.append(factory.error(
                        .unresolvedOpposite,
                        "Cannot resolve opposite '\(opposite)' of '\(draft.name).\(reference.name)' in '\(reference.eType.name)'",
                        at: source.oppositeRange ?? source.location.nameRange))
                }
            }
            var keys: [EUUID] = []
            for (position, key) in source.keys.enumerated() {
                var visited: Set<EUUID> = []
                if let (keyID, keyDraft) = feature(named: key, in: target, visited: &visited), keyDraft.kind == .attribute {
                    keys.append(keyID)
                } else {
                    let range = position < source.keyRanges.count ? source.keyRanges[position] : source.location.nameRange
                    diagnostics.append(factory.error(
                        .unresolvedKey,
                        "Cannot resolve key '\(key)' of '\(draft.name).\(reference.name)' in '\(reference.eType.name)'",
                        at: range))
                }
            }
            reference.eKeys = keys
            features[index] = reference
        }
        eClass.eStructuralFeatures = features
        builtClasses[identifier] = eClass
    }

    // MARK: Packages

    /// Builds a package, with its classifiers and subpackages.
    ///
    /// - Parameters:
    ///   - draft: The draft of the package.
    ///   - key: The qualified key of the package.
    /// - Returns: The package.
    private func package(_ draft: DraftPackage, key: String) -> EPackage {
        var classifiers: [any EClassifier] = []
        for classifier in draft.classifiers {
            guard let entry = entries[Self.qualified(key, classifier.name)], entry.draft == classifier else { continue }
            if let built = builtClasses[entry.id] ?? builtDataTypes[entry.id] { classifiers.append(built) }
        }
        return EPackage(
            id: packageIDs[key] ?? EUUID(), name: draft.name, nsURI: draft.nsURI, nsPrefix: draft.nsPrefix,
            eClassifiers: classifiers,
            eSubpackages: draft.subpackages.map { package($0, key: Self.qualified(key, $0.name)) },
            eAnnotations: annotations(draft.annotations))
    }
}
