//
// OCLinEcoreBuilder.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import OCL
import OrderedCollections

/// Builds Ecore packages from the declarations of an OCLinEcore document.
///
/// Classifiers are created first, so that every type reference can be resolved whatever the
/// order of the declarations; then features, operations and constraints are added, opposites
/// and keys are linked, and the snapshots of the classes are refreshed with ``MetamodelLinker``.
struct OCLinEcoreBuilder {
    /// The vocabulary of OCLinEcore.
    typealias Syntax = OCLinEcoreSyntax

    /// The name of the document, attached to each diagnostic.
    let document: String?
    /// The packages that imported names may refer to.
    let externals: [EPackage]
    /// The diagnostics collected so far.
    var diagnostics: [SourceDiagnostic] = []
    /// The resolver of type names against the packages being built and the external packages.
    var resolver = OCLTypeResolver(packages: [])

    /// The identifier of each reference by the identifier of its class and its name.
    var referenceIDs: [EUUID: [String: EUUID]] = [:]

    /// The opposites to link: class, reference, target class, opposite name and range.
    var pendingOpposites: [(classID: EUUID, referenceID: EUUID, targetID: EUUID, name: String, range: SourceRange)] = []

    /// The keys to link: class, reference, target class, key names and ranges.
    var pendingKeys: [(classID: EUUID, referenceID: EUUID, targetID: EUUID, keys: [(name: String, range: SourceRange)])] = []

    /// Creates a builder.
    ///
    /// - Parameters:
    ///   - document: The name of the document, attached to each diagnostic.
    ///   - externals: The packages that imported names may refer to.
    init(document: String?, externals: [EPackage]) {
        self.document = document
        self.externals = externals
    }

    /// Records an error.
    ///
    /// - Parameters:
    ///   - message: The description of the error.
    ///   - code: The diagnostic code.
    ///   - range: The source range of the error, if known.
    mutating func error(_ message: String, code: String = OCLDiagnosticCode.unresolvedName, range: SourceRange?) {
        diagnostics.append(SourceDiagnostic(severity: .error, code: code, message: message, range: range, document: document))
    }

    /// Records a warning.
    ///
    /// - Parameters:
    ///   - message: The description of the warning.
    ///   - code: The diagnostic code.
    ///   - range: The source range of the warning, if known.
    mutating func warning(_ message: String, code: String, range: SourceRange?) {
        diagnostics.append(SourceDiagnostic(severity: .warning, code: code, message: message, range: range, document: document))
    }

    // MARK: - Building

    /// Builds the packages that a document declares.
    ///
    /// - Parameter declaration: The parsed document.
    /// - Returns: The root packages, with resolved types and opposites.
    mutating func build(_ declaration: OCLinEcoreDocumentDeclaration) -> [EPackage] {
        let shells = declaration.packages.map(shell)
        var aliases: [String: EPackage] = [:]
        for anImport in declaration.imports {
            guard let alias = anImport.alias, !anImport.isLibrary else { continue }
            if OCLTypeResolver.isEcoreURI(anImport.target) {
                aliases[alias] = EcorePackage.instance
            } else if let external = externals.first(where: {
                $0.nsURI == OCLTypeResolver.namespaceURI(of: anImport.target) || $0.name == anImport.target
            }) {
                aliases[alias] = external
            } else if let own = shells.first(where: { $0.nsURI == OCLTypeResolver.namespaceURI(of: anImport.target) }) {
                aliases[alias] = own
            } else {
                warning("The import '\(anImport.target)' is not among the known packages", code: OCLDiagnosticCode.unresolvedName, range: anImport.range)
            }
        }
        resolver = OCLTypeResolver(packages: shells + externals, aliases: aliases)
        var packages = zip(declaration.packages, shells).map { fill($1, from: $0) }
        var classes: [EUUID: EClass] = [:]
        for package in packages { collectClasses(of: package, into: &classes) }
        packages = packages.map { linked($0, classes: classes) }
        packages = MetamodelLinker.relinked(packages, externals: externals)
        for index in packages.indices {
            for anImport in declaration.imports {
                guard let alias = anImport.alias, !anImport.isLibrary else { continue }
                OCLConstraintAnnotations.addImport(alias: alias, uri: OCLTypeResolver.namespaceURI(of: anImport.target), to: &packages[index])
            }
            if OCLConstraintAnnotations.hasExpressions(packages[index]) {
                OCLConstraintAnnotations.installDelegates(on: &packages[index])
            }
        }
        return packages
    }

    /// Creates a package with bare classifiers, so that names can be resolved.
    func shell(_ declaration: PackageDeclaration) -> EPackage {
        var package = EPackage(
            name: declaration.header.name, nsURI: declaration.nsURI ?? "", nsPrefix: declaration.nsPrefix ?? "")
        package.eClassifiers = declaration.classifiers.map { classifier -> any EClassifier in
            switch classifier.kind {
            case .class(let isAbstract, let isInterface):
                return EClass(
                    name: classifier.header.name, isAbstract: isAbstract, isInterface: isInterface,
                    instanceClassName: classifier.instanceClassName)
            case .dataType:
                return EDataType(
                    name: classifier.header.name, serialisable: classifier.isSerializable ?? false,
                    instanceClassName: classifier.instanceClassName)
            case .enumeration:
                var eEnum = EEnum(name: classifier.header.name)
                eEnum.instanceClassName = classifier.instanceClassName
                eEnum.serialisable = classifier.isSerializable ?? false
                return eEnum
            }
        }
        package.eSubpackages = declaration.packages.map(shell)
        return package
    }

    /// Fills the classifiers of a package shell from their declarations.
    mutating func fill(_ shell: EPackage, from declaration: PackageDeclaration) -> EPackage {
        var package = shell
        package.eAnnotations = annotations(declaration.annotations)
        package.eClassifiers = zip(declaration.classifiers, shell.eClassifiers).map { fill($1, from: $0) }
        package.eSubpackages = zip(declaration.packages, shell.eSubpackages).map { fill($1, from: $0) }
        return package
    }

    /// Fills a classifier shell with the contents of its declaration.
    ///
    /// - Parameters:
    ///   - shell: The classifier created in advance, so that other declarations can refer to it.
    ///   - declaration: The declaration of the classifier.
    /// - Returns: The completed classifier.
    mutating func fill(_ shell: any EClassifier, from declaration: ClassifierDeclaration) -> any EClassifier {
        let invariants = declaration.invariants.compactMap { specification -> OCLConstraintText? in
            guard let text = specification.text else { return nil }
            return OCLConstraintText(name: specification.name, expression: text, message: specification.message)
        }
        if var eClass = shell as? EClass {
            eClass.eAnnotations = annotations(declaration.annotations)
            for invariant in invariants { OCLConstraintAnnotations.addInvariant(invariant, to: &eClass) }
            eClass.eSuperTypes = declaration.superTypes.compactMap { type in
                guard let resolved = resolver.resolve(type)?.classifier else {
                    error("Cannot find the supertype '\(type.text)'", range: type.range)
                    return nil
                }
                guard let superType = resolved as? EClass else {
                    error("The supertype '\(type.text)' is not a class", range: type.range)
                    return nil
                }
                return superType
            }
            eClass.eStructuralFeatures = declaration.features.map { feature($0, in: eClass) }
            eClass.eOperations = declaration.operations.map { operation($0) }
            return eClass
        }
        if var eEnum = shell as? EEnum {
            eEnum.eAnnotations = annotations(declaration.annotations)
            for invariant in invariants { OCLConstraintAnnotations.addInvariant(invariant, to: &eEnum) }
            var next = 0
            eEnum.literals = declaration.literals.map { literal in
                let value = literal.value ?? next
                next = value + 1
                return EEnumLiteral(
                    name: literal.header.name, value: value, literal: literal.literal,
                    eAnnotations: annotations(literal.annotations))
            }
            return eEnum
        }
        if var dataType = shell as? EDataType {
            dataType.eAnnotations = annotations(declaration.annotations)
            for invariant in invariants { OCLConstraintAnnotations.addInvariant(invariant, to: &dataType) }
            return dataType
        }
        return shell
    }

    // MARK: - Features and operations

    /// The bounds of a type reference, `[1]` when none is written.
    func bounds(of type: OCLTypeReference?, resolved: OCLResolvedType?) -> (lower: Int, upper: Int) {
        if let multiplicity = type?.multiplicity { return (multiplicity.lower, multiplicity.upper) }
        if resolved?.collectionKind != nil {
            let inner = type?.arguments.first?.multiplicity
            return (inner?.lower ?? 0, inner?.upper ?? OCLMultiplicity.unbounded)
        }
        return (1, 1)
    }

    /// Resolves the type of a typed element, reporting a name that cannot be found.
    mutating func resolve(_ type: OCLTypeReference?, isRequired: Bool) -> OCLResolvedType? {
        guard let type else { return nil }
        if let resolved = resolver.resolve(type, isRequired: isRequired) { return resolved }
        error("Cannot find the type '\(type.text)'", range: type.range)
        return nil
    }

    /// Creates the attribute or reference that a declaration describes.
    ///
    /// - Parameters:
    ///   - declaration: The feature declaration.
    ///   - owner: The class that owns the feature.
    /// - Returns: The structural feature.
    mutating func feature(_ declaration: FeatureDeclaration, in owner: EClass) -> any EStructuralFeature {
        let lowerBound = declaration.type?.multiplicity?.lower ?? 1
        let resolved = resolve(declaration.type, isRequired: lowerBound >= 1)
        let (lower, upper) = bounds(of: declaration.type, resolved: resolved)
        /// Whether a qualifier is set, falling back to the type and the defaults of the language.
        ///
        /// - Parameter name: The qualifier.
        /// - Returns: `true` if the qualifier applies.
        func qualifier(_ name: String) -> Bool {
            declaration.qualifiers[name] ?? (name == Syntax.ordered ? resolved?.isOrdered : nil)
                ?? (name == Syntax.unique ? resolved?.isUnique : nil) ?? Syntax.qualifierDefaults[name] ?? false
        }
        let classifier = resolved?.classifier ?? EcorePackage.dataType(.eString)!
        let specificationAnnotations = annotations(declaration.annotations)
        /// Adds the initial and derivation expressions of the declaration to an element.
        ///
        /// - Parameter feature: The element.
        /// - Returns: The element with the expressions.
        func specified<Feature: EModelElement>(_ feature: Feature) -> Feature {
            var result = feature
            if let initial = declaration.initial?.text { OCLConstraintAnnotations.setInitial(initial, of: &result) }
            if let derivation = declaration.derivation?.text { OCLConstraintAnnotations.setDerivation(derivation, of: &result) }
            return result
        }
        let isReference = classifier is EClass
        if declaration.isAttribute, isReference {
            warning(
                "The attribute '\(declaration.header.name)' has a class type and is read as a reference",
                code: OCLDiagnosticCode.unsupportedConstruct, range: declaration.header.nameRange)
        }
        if !isReference {
            if declaration.opposite != nil || !declaration.keys.isEmpty || declaration.qualifiers[Syntax.composes] == true {
                error("The property '\(declaration.header.name)' has a data type and cannot have opposites, keys or containment",
                    code: OCLDiagnosticCode.unsupportedConstruct, range: declaration.header.nameRange)
            }
            return specified(EAttribute(
                name: declaration.header.name, eType: classifier, lowerBound: lower, upperBound: upper,
                changeable: !qualifier(Syntax.readonly), volatile: qualifier(Syntax.volatile),
                transient: qualifier(Syntax.transient), defaultValueLiteral: declaration.defaultValue,
                isID: qualifier(Syntax.id), eAnnotations: specificationAnnotations, ordered: qualifier(Syntax.ordered),
                unique: qualifier(Syntax.unique), unsettable: qualifier(Syntax.unsettable), derived: qualifier(Syntax.derived)))
        }
        var reference = EReference(
            name: declaration.header.name, eType: classifier, lowerBound: lower, upperBound: upper,
            changeable: !qualifier(Syntax.readonly), volatile: qualifier(Syntax.volatile),
            transient: qualifier(Syntax.transient), containment: qualifier(Syntax.composes),
            resolveProxies: qualifier(Syntax.resolve), eAnnotations: specificationAnnotations,
            ordered: qualifier(Syntax.ordered), unique: qualifier(Syntax.unique), unsettable: qualifier(Syntax.unsettable),
            derived: qualifier(Syntax.derived))
        reference.defaultValueLiteral = declaration.defaultValue
        reference = specified(reference)
        referenceIDs[owner.id, default: [:]][reference.name] = reference.id
        if let opposite = declaration.opposite {
            pendingOpposites.append((owner.id, reference.id, classifier.id, opposite, declaration.header.nameRange))
        }
        if !declaration.keys.isEmpty {
            pendingKeys.append((owner.id, reference.id, classifier.id, declaration.keys))
        }
        return reference
    }

    /// Creates the operation that a declaration describes.
    ///
    /// - Parameter declaration: The operation declaration.
    /// - Returns: The operation.
    mutating func operation(_ declaration: OperationDeclaration) -> EOperation {
        let lowerBound = declaration.type?.multiplicity?.lower ?? 1
        let resolved = resolve(declaration.type, isRequired: lowerBound >= 1)
        let (lower, upper) = declaration.type == nil ? (0, 1) : bounds(of: declaration.type, resolved: resolved)
        /// Whether a qualifier is set, falling back to the defaults of the language.
        ///
        /// - Parameter name: The qualifier.
        /// - Returns: `true` if the qualifier applies.
        func qualifier(_ name: String) -> Bool {
            declaration.qualifiers[name] ?? Syntax.qualifierDefaults[name] ?? false
        }
        let parameters = declaration.parameters.map { parameter -> EParameter in
            let parameterLower = parameter.type?.multiplicity?.lower ?? 1
            let resolved = resolve(parameter.type, isRequired: parameterLower >= 1)
            let (lower, upper) = parameter.type == nil ? (0, 1) : bounds(of: parameter.type, resolved: resolved)
            var result = EParameter(
                name: parameter.header.name, eType: resolved?.classifier, lowerBound: lower, upperBound: upper,
                ordered: parameter.qualifiers[Syntax.ordered] ?? resolved?.isOrdered ?? false,
                unique: parameter.qualifiers[Syntax.unique] ?? resolved?.isUnique ?? true)
            result.eAnnotations = annotations(parameter.annotations)
            return result
        }
        var operation = EOperation(
            name: declaration.header.name, eType: resolved?.classifier, lowerBound: lower, upperBound: upper,
            ordered: declaration.qualifiers[Syntax.ordered] ?? resolved?.isOrdered ?? false,
            unique: declaration.qualifiers[Syntax.unique] ?? resolved?.isUnique ?? true,
            eParameters: parameters,
            eExceptions: declaration.exceptions.compactMap { resolve($0, isRequired: true)?.classifier },
            eAnnotations: annotations(declaration.annotations))
        if qualifier(Syntax.derived) || qualifier(Syntax.transient) {
            warning("Operation qualifiers other than 'ordered' and 'unique' have no counterpart in Ecore",
                code: OCLDiagnosticCode.unsupportedConstruct, range: declaration.header.nameRange)
        }
        if let body = declaration.body?.text { OCLConstraintAnnotations.setBody(body, of: &operation) }
        for condition in declaration.preconditions {
            guard let text = condition.text else { continue }
            OCLConstraintAnnotations.addPrecondition(
                OCLConstraintText(name: condition.name, expression: text, message: condition.message), to: &operation)
        }
        for condition in declaration.postconditions {
            guard let text = condition.text else { continue }
            OCLConstraintAnnotations.addPostcondition(
                OCLConstraintText(name: condition.name, expression: text, message: condition.message), to: &operation)
        }
        return operation
    }

    // MARK: - Linking

    /// Links the opposites and keys of the references in a package tree.
    /// Finds an attribute of a class or of one of its supertypes, by the filled classes.
    func attribute(named name: String, in classID: EUUID, classes: [EUUID: EClass], visited: Set<EUUID> = []) -> EAttribute? {
        guard !visited.contains(classID), let eClass = classes[classID] else { return nil }
        if let own = eClass.eStructuralFeatures.lazy.compactMap({ $0 as? EAttribute }).first(where: { $0.name == name }) {
            return own
        }
        for superType in eClass.eSuperTypes {
            if let inherited = attribute(named: name, in: superType.id, classes: classes, visited: visited.union([classID])) {
                return inherited
            }
        }
        return nil
    }

    /// Collects the classes of a package and its subpackages.
    ///
    /// - Parameters:
    ///   - package: The package to search.
    ///   - classes: The classes found so far, by identifier, to which more are added.
    func collectClasses(of package: EPackage, into classes: inout [EUUID: EClass]) {
        for case let eClass as EClass in package.eClassifiers { classes[eClass.id] = eClass }
        for subpackage in package.eSubpackages { collectClasses(of: subpackage, into: &classes) }
    }

    /// Replaces the opposites of references with the references that carry the same identifiers.
    ///
    /// - Parameters:
    ///   - package: The package to relink.
    ///   - classes: The classes of every package, by identifier.
    /// - Returns: The package with its references linked.
    mutating func linked(_ package: EPackage, classes: [EUUID: EClass]) -> EPackage {
        var result = package
        result.eClassifiers = package.eClassifiers.map { classifier in
            guard var eClass = classifier as? EClass else { return classifier }
            eClass.eStructuralFeatures = eClass.eStructuralFeatures.map { feature in
                guard var reference = feature as? EReference else { return feature }
                if let pending = pendingOpposites.first(where: { $0.referenceID == reference.id }) {
                    if let opposite = referenceIDs[pending.targetID]?[pending.name] {
                        reference.opposite = opposite
                    } else {
                        error("Cannot find the opposite '\(pending.name)' of '\(reference.name)'", range: pending.range)
                    }
                }
                if let pending = pendingKeys.first(where: { $0.referenceID == reference.id }) {
                    reference.eKeys = pending.keys.compactMap { key in
                        guard let attribute = attribute(named: key.name, in: pending.targetID, classes: classes) else {
                            error("Cannot find the key '\(key.name)'", range: key.range)
                            return nil
                        }
                        return attribute.id
                    }
                }
                return reference
            }
            return eClass
        }
        result.eSubpackages = package.eSubpackages.map { linked($0, classes: classes) }
        return result
    }

    // MARK: - Annotations

    /// Creates annotations from their declarations.
    ///
    /// - Parameter declarations: The annotation declarations.
    /// - Returns: The annotations.
    func annotations(_ declarations: [AnnotationDeclaration]) -> [EAnnotation] {
        declarations.compactMap { declaration in
            var details: OrderedDictionary<String, String> = [:]
            switch declaration.kind {
            case .annotation(let source):
                for detail in declaration.details { details[detail.key] = detail.value }
                return EAnnotation(source: source ?? "", orderedDetails: details, eAnnotations: annotations(declaration.children))
            case .documentation(let text):
                if let text { details[AnnotationSource.GenModelKey.documentation] = text }
                for detail in declaration.details { details[detail.key] = detail.value }
                return EAnnotation(source: AnnotationSource.genModel, orderedDetails: details)
            case .sysml:
                return nil
            }
        }
    }
}
