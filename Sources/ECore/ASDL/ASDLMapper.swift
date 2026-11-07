//
// ASDLMapper.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase

/// Turns parsed ASDL modules into metamodel drafts.
struct ASDLMapper {
    /// The settings that control the mapping.
    let options: ASDLImportOptions

    /// The name of the source document, which names a package without a module name.
    let sourceName: String?

    /// The diagnostics found so far.
    private(set) var collector: DiagnosticCollector

    /// Prepares a mapping.
    ///
    /// - Parameters:
    ///   - options: The settings that control the mapping.
    ///   - sourceName: The name of the source document.
    init(options: ASDLImportOptions, sourceName: String?) {
        self.options = options
        self.sourceName = sourceName
        collector = DiagnosticCollector(document: sourceName)
    }

    /// How a module's types are represented.
    private enum TypeKind {
        /// A sum or product type that becomes a class.
        case eClass
        /// A sum of constructors without fields that becomes an enumeration.
        case eEnum
    }

    /// What a module contributes to the mapping of fields.
    private struct ModuleInfo {
        /// The name of the package made from the module.
        let packageName: String
        /// The representation of each type the module defines.
        let types: [String: TypeKind]
    }

    /// Maps modules to package drafts, one per module.
    ///
    /// - Parameter modules: The modules in source order.
    /// - Returns: The drafts in the same order.
    mutating func map(_ modules: [ASDLModule]) -> [GrammarDraftPackage] {
        var infos: [String: ModuleInfo] = [:]
        var definitionsByModule: [[ASDLDefinition]] = []
        for module in modules {
            let definitions = uniqueDefinitions(of: module)
            definitionsByModule.append(definitions)
            var types: [String: TypeKind] = [:]
            for definition in definitions { types[definition.name] = isEnumeration(definition) ? .eEnum : .eClass }
            infos[module.name] = ModuleInfo(packageName: packageName(of: module), types: types)
        }
        return zip(modules, definitionsByModule).map { module, definitions in
            draft(of: module, definitions: definitions, infos: infos, isOnly: modules.count == 1)
        }
    }

    /// The name of the package made from a module.
    ///
    /// - Parameter module: The module.
    /// - Returns: The module name, or a name from the options or source name if the module has none.
    private func packageName(of module: ASDLModule) -> String {
        GrammarNaming.packageName(declared: module.name, option: options.packageName, sourceName: sourceName)
    }

    /// The definitions of a module without repeated type names or constructors.
    ///
    /// - Parameter module: The module.
    /// - Returns: The definitions, without later repetitions, which are reported.
    private mutating func uniqueDefinitions(of module: ASDLModule) -> [ASDLDefinition] {
        var typeNames: Set<String> = []
        var result: [ASDLDefinition] = []
        for definition in module.definitions {
            guard typeNames.insert(definition.name).inserted else {
                collector.error(
                    ASDLDiagnosticCode.duplicateType.rawValue,
                    "The type '\(definition.name)' is already defined in module '\(module.name)'",
                    at: definition.nameRange)
                continue
            }
            result.append(definition)
        }
        var constructorNames: Set<String> = []
        for index in result.indices {
            guard case .sum(let constructors) = result[index].body else { continue }
            let kept = constructors.filter { constructor in
                if typeNames.contains(constructor.name) {
                    collector.error(
                        ASDLDiagnosticCode.duplicateConstructor.rawValue,
                        "The constructor '\(constructor.name)' has the name of a type of module '\(module.name)'",
                        at: constructor.nameRange)
                    return false
                }
                guard constructorNames.insert(constructor.name).inserted else {
                    collector.error(
                        ASDLDiagnosticCode.duplicateConstructor.rawValue,
                        "The constructor '\(constructor.name)' is already defined in module '\(module.name)'",
                        at: constructor.nameRange)
                    return false
                }
                return true
            }
            result[index].body = .sum(kept)
        }
        return result
    }

    /// Whether a definition becomes an enumeration.
    ///
    /// - Parameter definition: The definition.
    /// - Returns: `true` for a sum of constructors without fields and without
    ///   attributes when the options ask for enumerations.
    private func isEnumeration(_ definition: ASDLDefinition) -> Bool {
        guard options.enumerations == .allNullarySums, definition.attributes.isEmpty,
            case .sum(let constructors) = definition.body, !constructors.isEmpty
        else { return false }
        return constructors.allSatisfy(\.fields.isEmpty)
    }

    /// The draft of one module.
    ///
    /// - Parameters:
    ///   - module: The module.
    ///   - definitions: Its definitions without repetitions.
    ///   - infos: What every module of the text defines, by module name.
    ///   - isOnly: Whether the module is the only one in the text.
    /// - Returns: The package draft.
    private mutating func draft(
        of module: ASDLModule, definitions: [ASDLDefinition], infos: [String: ModuleInfo], isOnly: Bool
    ) -> GrammarDraftPackage {
        let name = packageName(of: module)
        let nsURI = options.nsURI.map { isOnly ? $0 : $0 + "/" + name }
            ?? GrammarNaming.defaultNsURI(notation: "asdl", packageName: name)
        let nsPrefix = options.nsPrefix ?? GrammarNaming.defaultNsPrefix(packageName: name)
        var details: [GrammarDraftDetail] = []
        if let version = module.version { details.append(GrammarDraftDetail(ASDLSyntax.AnnotationKey.version, version)) }
        if !module.imports.isEmpty {
            details.append(GrammarDraftDetail(ASDLSyntax.AnnotationKey.imports, module.imports.joined(separator: " ")))
        }
        for imported in module.imports where infos[imported] == nil {
            collector.warning(
                ASDLDiagnosticCode.unresolvedImport.rawValue,
                "The imported module '\(imported)' is not part of the text; its types are not resolved",
                at: module.nameRange)
        }
        var classifiers: [GrammarDraftClassifier] = []
        for definition in definitions {
            classifiers += self.classifiers(of: definition, in: module, infos: infos)
        }
        return GrammarDraftPackage(
            name: name, nsURI: nsURI, nsPrefix: nsPrefix, classifiers: classifiers,
            annotations: details.isEmpty ? [] : [GrammarDraftAnnotation(source: ASDLSyntax.annotationSource, details: details)],
            range: module.nameRange)
    }

    /// The classifiers that one definition becomes.
    ///
    /// - Parameters:
    ///   - definition: The definition.
    ///   - module: The module that contains it.
    ///   - infos: What every module of the text defines.
    /// - Returns: An enumeration; a class for a product; or an abstract class
    ///   followed by one subclass per constructor for a sum.
    private mutating func classifiers(
        of definition: ASDLDefinition, in module: ASDLModule, infos: [String: ModuleInfo]
    ) -> [GrammarDraftClassifier] {
        switch definition.body {
        case .sum(let constructors) where isEnumeration(definition):
            return [.eEnum(GrammarDraftEnum(
                name: definition.name,
                literals: constructors.map { GrammarDraftLiteral(name: $0.name, range: $0.nameRange) },
                range: definition.nameRange))]
        case .sum(let constructors):
            let attributeNames = GrammarNaming.fieldNames(definition.attributes.map { ($0.typeName, $0.name) })
            let attributes = zip(definition.attributes, attributeNames).map {
                feature($0, name: $1, isAttribute: true, in: module, infos: infos)
            }
            var result: [GrammarDraftClassifier] = [.eClass(GrammarDraftClass(
                name: definition.name, isAbstract: true, features: attributes, range: definition.nameRange))]
            for constructor in constructors {
                let inherited = zip(definition.attributes, attributeNames).map { ($0.typeName, Optional($1)) }
                let names = GrammarNaming.fieldNames(constructor.fields.map { ($0.typeName, $0.name) } + inherited)
                let fields = zip(constructor.fields, names).map {
                    feature($0, name: $1, isAttribute: false, in: module, infos: infos)
                }
                result.append(.eClass(GrammarDraftClass(
                    name: constructor.name, superTypes: [.named(definition.name)], features: fields,
                    range: constructor.nameRange)))
            }
            return result
        case .product(let fields):
            let all = fields + definition.attributes
            let names = GrammarNaming.fieldNames(all.map { ($0.typeName, $0.name) })
            let features = zip(all.indices, names).map { index, name in
                feature(all[index], name: name, isAttribute: index >= fields.count, in: module, infos: infos)
            }
            return [.eClass(GrammarDraftClass(name: definition.name, features: features, range: definition.nameRange))]
        }
    }

    /// The feature that a field becomes.
    ///
    /// - Parameters:
    ///   - field: The field.
    ///   - name: Its name, given or generated.
    ///   - isAttribute: Whether the field comes from an `attributes` clause.
    ///   - module: The module that contains it.
    ///   - infos: What every module of the text defines.
    /// - Returns: A containment reference for a field of a sum or product type,
    ///   otherwise an attribute.
    private mutating func feature(
        _ field: ASDLField, name: String, isAttribute: Bool, in module: ASDLModule, infos: [String: ModuleInfo]
    ) -> GrammarDraftFeature {
        var details: [GrammarDraftDetail] = []
        let (type, isClass) = resolveType(of: field, in: module, infos: infos, details: &details)
        if isAttribute { details.append(GrammarDraftDetail(ASDLSyntax.AnnotationKey.attribute, ASDLSyntax.markerValue)) }
        if field.name == nil {
            details.append(GrammarDraftDetail(ASDLSyntax.AnnotationKey.generatedName, ASDLSyntax.markerValue))
        }
        let (lower, upper) = multiplicity(of: field, details: &details)
        let isMany = upper == -1
        return GrammarDraftFeature(
            name: name, type: type, lowerBound: lower, upperBound: upper, isContainment: isClass,
            isUnique: !isMany || isClass,
            annotations: details.isEmpty ? [] : [GrammarDraftAnnotation(source: ASDLSyntax.annotationSource, details: details)],
            range: field.range)
    }

    /// The type of a field and whether it is a class.
    ///
    /// - Parameters:
    ///   - field: The field.
    ///   - module: The module that contains it.
    ///   - infos: What every module of the text defines.
    ///   - details: Receives the annotation detail naming a built-in or external type.
    /// - Returns: The type reference and whether it names a class.
    private mutating func resolveType(
        of field: ASDLField, in module: ASDLModule, infos: [String: ModuleInfo], details: inout [GrammarDraftDetail]
    ) -> (GrammarDraftTypeReference, Bool) {
        if let qualifier = field.module, qualifier != module.name {
            if let info = infos[qualifier], let kind = info.types[field.typeName] {
                return (.named(field.typeName, package: info.packageName), kind == .eClass)
            }
            details.append(GrammarDraftDetail(ASDLSyntax.AnnotationKey.type, qualifier + ASDLSyntax.Symbol.dot + field.typeName))
            collector.warning(
                ASDLDiagnosticCode.externalType.rawValue,
                "The type '\(qualifier).\(field.typeName)' belongs to a module that is not part of the text;"
                    + " it is represented as a containment of any EObject",
                at: field.typeRange)
            return (.eObject, true)
        }
        if let kind = infos[module.name]?.types[field.typeName] {
            return (.named(field.typeName), kind == .eClass)
        }
        if let builtin = options.builtinTypes[field.typeName] {
            details.append(GrammarDraftDetail(ASDLSyntax.AnnotationKey.type, field.typeName))
            return (.ecore(builtin), false)
        }
        collector.error(
            ASDLDiagnosticCode.undefinedType.rawValue,
            "The type '\(field.typeName)' is neither defined in module '\(module.name)' nor built in",
            at: field.typeRange)
        return (.ecore(.eJavaObject), false)
    }

    /// The bounds of a field from its quantifiers.
    ///
    /// - Parameters:
    ///   - field: The field.
    ///   - details: Receives the quantifiers when Ecore can only approximate them.
    /// - Returns: `1..1` without a quantifier, `0..1` for `?`, and `0..-1`
    ///   (unbounded) for `*` or any combination containing `*`.
    private mutating func multiplicity(of field: ASDLField, details: inout [GrammarDraftDetail]) -> (Int, Int) {
        switch field.quantifiers {
        case "": return (1, 1)
        case ASDLSyntax.Symbol.optional: return (0, 1)
        case ASDLSyntax.Symbol.sequence: return (0, -1)
        default: break
        }
        details.append(GrammarDraftDetail(ASDLSyntax.AnnotationKey.quantifiers, field.quantifiers))
        let isSequence = field.quantifiers.contains(ASDLSyntax.Symbol.sequence)
        let meaning =
            field.quantifiers == "?*"
            ? "a sequence of optional values, but an Ecore list cannot hold absent entries"
            : "a combination that Ecore cannot express"
        collector.information(
            ASDLDiagnosticCode.approximatedQuantifier.rawValue,
            "The quantifiers '\(field.quantifiers)' of '\(field.typeName)' describe \(meaning);"
                + " the feature becomes \(isSequence ? "[0..*]" : "[0..1]")",
            at: field.range)
        return isSequence ? (0, -1) : (0, 1)
    }
}
