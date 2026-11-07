//
// CompleteOCLApplier.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import OCL

/// The result of adding the constraints of a Complete OCL document to Ecore packages.
public struct CompleteOCLApplication: Sendable {
    /// The packages with the constraints added as annotations.
    public var packages: [EPackage]

    /// The contexts that could not be resolved and the constraints that could not be added.
    public var diagnostics: [SourceDiagnostic]

    /// The number of constraints, definitions, bodies, initial values and derivations added.
    public var appliedCount: Int

    /// Creates an application result.
    ///
    /// - Parameters:
    ///   - packages: The packages with the constraints.
    ///   - diagnostics: The problems found.
    ///   - appliedCount: The number of specifications added.
    public init(packages: [EPackage], diagnostics: [SourceDiagnostic], appliedCount: Int) {
        self.packages = packages
        self.diagnostics = diagnostics
        self.appliedCount = appliedCount
    }

    /// Whether every context was resolved and every specification added.
    public var isComplete: Bool { !diagnostics.contains { $0.severity == .error } }
}

/// Adds the constraints of Complete OCL documents to Ecore packages.
///
/// The constraints become the same annotations that the OCLinEcore reader creates (see
/// ``OCLConstraintAnnotations``), so a metamodel with a Complete OCL document is equivalent to
/// the OCLinEcore document that declares the constraints inline:
///
/// - `inv` adds an invariant to the classifier;
/// - `pre`, `post` and `body` add to the operation, which is chosen by name and, among
///   overloads, by the number and types of its parameters;
/// - `init` and `derive` set the initial value and the derivation of the structural feature;
/// - `def` adds an operation with a body, or a derived, volatile, transient and read-only
///   structural feature with a derivation.
///
/// A context is resolved by its qualified name, prefixed by its enclosing package declaration,
/// matched against the end of the qualified names of the classifiers of the packages; a
/// leading import alias is skipped. Names
/// that the document gives to `self` or to parameters, where they differ from the names in
/// the metamodel, are bound with `let` around the stored expression. The root packages that
/// receive constraints name the OCL delegates.
public enum CompleteOCLApplier {
    /// Adds the constraints of a document to packages.
    ///
    /// - Parameters:
    ///   - document: The Complete OCL document.
    ///   - packages: The root packages of the metamodels the document constrains.
    ///   - sourceName: The name of the document, attached to each diagnostic.
    /// - Returns: The packages with the constraints, and diagnostics for contexts that could not
    ///   be resolved.
    public static func apply(_ document: CompleteOCLDocument, to packages: [EPackage], sourceName: String? = nil) -> CompleteOCLApplication {
        var state = State(roots: packages, document: sourceName)
        state.aliases = Set(document.imports.compactMap(\.alias))
        for context in document.classifierContexts { state.apply(context) }
        for context in document.operationContexts { state.apply(context) }
        for context in document.propertyContexts { state.apply(context) }
        var roots = state.roots
        if state.addedFeatures { roots = MetamodelLinker.relinked(roots) }
        for index in roots.indices where state.touchedRoots.contains(index) {
            OCLConstraintAnnotations.installDelegates(on: &roots[index])
        }
        return CompleteOCLApplication(packages: roots, diagnostics: state.diagnostics, appliedCount: state.appliedCount)
    }

    /// The location of a classifier: the root package, the path of subpackage indices and the classifier index.
    struct Location: Hashable {
        /// The index of the root package that holds the classifier.
        var root: Int
        /// The indices of the subpackages, from the root package down to the package holding the classifier.
        var subpackages: [Int]
        /// The index of the classifier within its package.
        var classifier: Int
    }

    /// The state of one application.
    struct State {
        /// The root packages, with every change applied so far.
        var roots: [EPackage]
        /// The name of the document, attached to each diagnostic.
        let document: String?
        /// The diagnostics collected so far.
        var diagnostics: [SourceDiagnostic] = []
        /// The indices of the root packages that received constraints.
        var touchedRoots: Set<Int> = []
        /// The number of constraints and definitions applied so far.
        var appliedCount = 0
        /// Whether a definition added a feature or operation, so that the packages need relinking.
        var addedFeatures = false

        /// The import aliases, which may start the qualified name of a context.
        var aliases: Set<String> = []

        /// Creates the state for one application.
        ///
        /// - Parameters:
        ///   - roots: The root packages to constrain.
        ///   - document: The name of the document, attached to each diagnostic.
        init(roots: [EPackage], document: String?) {
            self.roots = roots
            self.document = document
        }

        /// Records an error.
        ///
        /// - Parameters:
        ///   - message: The description of the error.
        ///   - code: The diagnostic code.
        ///   - range: The source range of the error, if known.
        mutating func error(_ message: String, code: String = OCLDiagnosticCode.unresolvedContext, range: SourceRange?) {
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

        // MARK: Resolution

        /// Every classifier with its location and qualified name.
        func classifiers() -> [(Location, [String], any EClassifier)] {
            var result: [(Location, [String], any EClassifier)] = []
            /// Adds a package, its classifiers and its subpackages to the result.
            ///
            /// - Parameters:
            ///   - package: The package to visit.
            ///   - root: The index of the root package that contains it.
            ///   - indices: The subpackage indices leading to it from the root package.
            ///   - path: The names of the enclosing packages.
            func visit(_ package: EPackage, root: Int, indices: [Int], path: [String]) {
                let packagePath = path + [package.name]
                for (index, classifier) in package.eClassifiers.enumerated() {
                    result.append((Location(root: root, subpackages: indices, classifier: index), packagePath + [classifier.name], classifier))
                }
                for (index, subpackage) in package.eSubpackages.enumerated() {
                    visit(subpackage, root: root, indices: indices + [index], path: packagePath)
                }
            }
            for (index, root) in roots.enumerated() { visit(root, root: index, indices: [], path: []) }
            return result
        }

        /// Finds the classifier that a qualified name ends with.
        mutating func locate(_ written: [String], range: SourceRange?) -> (Location, any EClassifier)? {
            let path = written.count > 1 && aliases.contains(written[0]) ? Array(written.dropFirst()) : written
            let matches = classifiers().filter { $0.1.count >= path.count && Array($0.1.suffix(path.count)) == path }
            guard let first = matches.first else {
                error("Cannot find the classifier '\(path.joined(separator: "::"))'", range: range)
                return nil
            }
            if matches.count > 1 {
                warning("'\(path.joined(separator: "::"))' names several classifiers; the first is used",
                    code: OCLDiagnosticCode.unresolvedContext, range: range)
            }
            return (first.0, first.2)
        }

        /// Applies a change to the classifier at a location.
        mutating func modify(_ location: Location, _ change: (inout any EClassifier) -> Void) {
            /// Applies the change to the classifier within a package and its subpackages.
            ///
            /// - Parameters:
            ///   - package: The package to descend into.
            ///   - indices: The remaining subpackage indices leading to the classifier.
            func update(_ package: inout EPackage, _ indices: ArraySlice<Int>) {
                if let first = indices.first {
                    update(&package.eSubpackages[first], indices.dropFirst())
                } else {
                    change(&package.eClassifiers[location.classifier])
                }
            }
            update(&roots[location.root], location.subpackages[...])
            touchedRoots.insert(location.root)
        }

        /// The resolver of type names against the packages.
        var resolver: OCLTypeResolver { OCLTypeResolver(packages: roots) }

        /// Wraps an expression in `let` bindings that rename variables.
        static func bound(_ expression: String, _ bindings: [(name: String, value: String)]) -> String {
            bindings.reversed().reduce(expression) { "let \($1.name) = \($1.value) in " + $0 }
        }

        // MARK: Classifier contexts

        /// Applies the definitions and invariants of a classifier context.
        ///
        /// - Parameter context: The classifier context.
        mutating func apply(_ context: CompleteOCLClassifierContext) {
            guard let (location, classifier) = locate(context.packagePath + context.path, range: context.nameRange) else { return }
            let bindings = context.selfName.map { [($0, OCLSyntax.selfKeyword)] } ?? []
            var definitions: [any EStructuralFeature] = []
            var operations: [EOperation] = []
            for definition in context.definitions {
                if definition.isStatic {
                    warning("Static definitions have no counterpart in Ecore and are added as instance definitions",
                        code: OCLDiagnosticCode.unsupportedConstruct, range: definition.range)
                }
                guard let eClass = classifier as? EClass else {
                    error("Definitions need a class, but '\(classifier.name)' is not one", range: definition.range)
                    continue
                }
                let expression = Self.bound(definition.specification.expression, bindings)
                if let parameters = definition.parameters {
                    if eClass.eOperations.contains(where: { $0.name == definition.name && $0.eParameters.count == parameters.count }) {
                        error("'\(eClass.name)' already has the operation '\(definition.name)'",
                            code: OCLDiagnosticCode.duplicateDeclaration, range: definition.range)
                        continue
                    }
                    operations.append(operation(for: definition, parameters: parameters, expression: expression))
                } else {
                    if eClass.eAllStructuralFeatures.contains(where: { $0.name == definition.name }) {
                        error("'\(eClass.name)' already has the feature '\(definition.name)'",
                            code: OCLDiagnosticCode.duplicateDeclaration, range: definition.range)
                        continue
                    }
                    definitions.append(feature(for: definition, expression: expression))
                }
                appliedCount += 1
            }
            let invariants = context.invariants.map { constraint in
                OCLConstraintText(name: constraint.name, expression: Self.bound(constraint.expression, bindings), message: constraint.message)
            }
            appliedCount += invariants.count
            if !definitions.isEmpty || !operations.isEmpty { addedFeatures = true }
            modify(location) { classifier in
                switch classifier {
                case var eClass as EClass:
                    for invariant in invariants { OCLConstraintAnnotations.addInvariant(invariant, to: &eClass) }
                    eClass.eStructuralFeatures += definitions
                    eClass.eOperations += operations
                    classifier = eClass
                case var dataType as EDataType:
                    for invariant in invariants { OCLConstraintAnnotations.addInvariant(invariant, to: &dataType) }
                    classifier = dataType
                case var eEnum as EEnum:
                    for invariant in invariants { OCLConstraintAnnotations.addInvariant(invariant, to: &eEnum) }
                    classifier = eEnum
                default:
                    break
                }
            }
        }

        /// The bounds of a type: `[1]` unless written otherwise or a collection.
        func bounds(of type: OCLTypeReference?, resolved: OCLResolvedType?) -> (lower: Int, upper: Int) {
            if let multiplicity = type?.multiplicity { return (multiplicity.lower, multiplicity.upper) }
            if resolved?.collectionKind != nil { return (0, OCLMultiplicity.unbounded) }
            return (1, 1)
        }

        /// Resolves a type reference against the packages.
        ///
        /// - Parameters:
        ///   - type: The type reference, if any.
        ///   - range: The source range used for the diagnostic if the type is unknown.
        /// - Returns: The resolved type, or `nil` if there is no type or it cannot be found.
        mutating func resolve(_ type: OCLTypeReference?, range: SourceRange?) -> OCLResolvedType? {
            guard let type else { return nil }
            guard let resolved = resolver.resolve(type, isRequired: (type.multiplicity?.lower ?? 1) >= 1) else {
                error("Cannot find the type '\(type.text)'", code: OCLDiagnosticCode.unresolvedName, range: type.range ?? range)
                return nil
            }
            return resolved
        }

        /// Creates the operation that a definition declares.
        ///
        /// - Parameters:
        ///   - definition: The definition.
        ///   - parameters: The parameters of the definition.
        ///   - expression: The body expression of the operation.
        /// - Returns: The operation, with its body annotation.
        mutating func operation(for definition: CompleteOCLDefinition, parameters: [CompleteOCLParameter], expression: String) -> EOperation {
            let resolved = resolve(definition.type, range: definition.range)
            let (lower, upper) = definition.type == nil ? (0, 1) : bounds(of: definition.type, resolved: resolved)
            let eParameters = parameters.map { parameter -> EParameter in
                let resolvedParameter = resolve(parameter.type, range: definition.range)
                let (lower, upper) = bounds(of: parameter.type, resolved: resolvedParameter)
                return EParameter(
                    name: parameter.name ?? "", eType: resolvedParameter?.classifier, lowerBound: lower, upperBound: upper,
                    ordered: resolvedParameter?.isOrdered ?? false, unique: resolvedParameter?.isUnique ?? true)
            }
            var operation = EOperation(
                name: definition.name, eType: resolved?.classifier, lowerBound: lower, upperBound: upper,
                ordered: resolved?.isOrdered ?? false, unique: resolved?.isUnique ?? true, eParameters: eParameters)
            OCLConstraintAnnotations.setBody(expression, of: &operation)
            return operation
        }

        /// Creates the attribute or reference that a property definition declares.
        ///
        /// - Parameters:
        ///   - definition: The definition.
        ///   - expression: The derivation expression of the feature.
        /// - Returns: The structural feature, with its derivation annotation.
        mutating func feature(for definition: CompleteOCLDefinition, expression: String) -> any EStructuralFeature {
            let resolved = resolve(definition.type, range: definition.range)
            let (lower, upper) = bounds(of: definition.type, resolved: resolved)
            let classifier = resolved?.classifier ?? EcorePackage.dataType(.eString)!
            if classifier is EClass {
                var reference = EReference(
                    name: definition.name, eType: classifier, lowerBound: lower, upperBound: upper, changeable: false,
                    volatile: true, transient: true, ordered: resolved?.isOrdered ?? false, unique: resolved?.isUnique ?? true,
                    derived: true)
                OCLConstraintAnnotations.setDerivation(expression, of: &reference)
                return reference
            }
            var attribute = EAttribute(
                name: definition.name, eType: classifier, lowerBound: lower, upperBound: upper, changeable: false,
                volatile: true, transient: true, ordered: resolved?.isOrdered ?? false, unique: resolved?.isUnique ?? true,
                derived: true)
            OCLConstraintAnnotations.setDerivation(expression, of: &attribute)
            return attribute
        }

        // MARK: Operation contexts

        /// Whether the type of a parameter matches a type reference by name.
        func matches(_ parameter: EParameter, _ type: OCLTypeReference) -> Bool {
            guard let classifier = parameter.eType else { return false }
            if classifier.name == type.name { return true }
            guard let resolved = resolver.resolve(type, isRequired: parameter.lowerBound >= 1) else { return false }
            return resolved.classifier.id == classifier.id || resolved.classifier.name == classifier.name
        }

        /// Applies the conditions of an operation context.
        ///
        /// - Parameter context: The operation context.
        mutating func apply(_ context: CompleteOCLOperationContext) {
            let name = context.path[context.path.count - 1]
            let classPath = context.packagePath + context.path.dropLast()
            guard !context.path.dropLast().isEmpty, let (location, classifier) = locate(classPath, range: context.nameRange) else {
                if context.path.count < 2 { error("The operation '\(name)' needs a class", range: context.nameRange) }
                return
            }
            guard let eClass = classifier as? EClass else {
                error("'\(classifier.name)' is not a class", range: context.nameRange)
                return
            }
            let candidates = eClass.eOperations.enumerated().filter {
                $0.element.name == name && $0.element.eParameters.count == context.parameters.count
            }
            let chosen = candidates.first { candidate in
                zip(candidate.element.eParameters, context.parameters).allSatisfy { matches($0, $1.type) }
            } ?? (candidates.count == 1 ? candidates.first : nil)
            guard let (index, operation) = chosen else {
                let inherited = eClass.eAllOperations.contains { $0.name == name }
                error(inherited ? "The operation '\(name)' is inherited by '\(eClass.name)'; constrain it in the class that declares it"
                    : "Cannot find the operation '\(name)' with \(context.parameters.count) parameters in '\(eClass.name)'",
                    range: context.nameRange)
                return
            }
            let bindings = zip(operation.eParameters, context.parameters).compactMap { parameter, written -> (String, String)? in
                guard let writtenName = written.name, writtenName != parameter.name else { return nil }
                return (writtenName, parameter.name)
            }
            if context.bodies.count > 1 {
                warning("Only the last body of '\(name)' is kept", code: OCLDiagnosticCode.duplicateDeclaration, range: context.bodies.last?.range)
            }
            appliedCount += context.preconditions.count + context.postconditions.count + min(context.bodies.count, 1)
            modify(location) { classifier in
                guard var eClass = classifier as? EClass else { return }
                var updated = eClass.eOperations[index]
                if let body = context.bodies.last {
                    OCLConstraintAnnotations.setBody(Self.bound(body.expression, bindings), of: &updated)
                }
                for constraint in context.preconditions {
                    OCLConstraintAnnotations.addPrecondition(OCLConstraintText(
                        name: constraint.name, expression: Self.bound(constraint.expression, bindings), message: constraint.message), to: &updated)
                }
                for constraint in context.postconditions {
                    OCLConstraintAnnotations.addPostcondition(OCLConstraintText(
                        name: constraint.name, expression: Self.bound(constraint.expression, bindings), message: constraint.message), to: &updated)
                }
                eClass.eOperations[index] = updated
                classifier = eClass
            }
        }

        // MARK: Property contexts

        /// Applies the invariants and derivations of a property context.
        ///
        /// - Parameter context: The property context.
        mutating func apply(_ context: CompleteOCLPropertyContext) {
            let name = context.path[context.path.count - 1]
            guard context.path.count >= 2, let (location, classifier) = locate(context.packagePath + context.path.dropLast(), range: context.nameRange) else {
                if context.path.count < 2 { error("The property '\(name)' needs a class", range: context.nameRange) }
                return
            }
            guard let eClass = classifier as? EClass, let index = eClass.eStructuralFeatures.firstIndex(where: { $0.name == name }) else {
                let inherited = (classifier as? EClass)?.eAllStructuralFeatures.contains { $0.name == name } ?? false
                error(inherited ? "The property '\(name)' is inherited by '\(classifier.name)'; constrain it in the class that declares it"
                    : "Cannot find the property '\(name)' in '\(classifier.name)'", range: context.nameRange)
                return
            }
            for (list, kind) in [(context.initialisers, "initial value"), (context.derivations, "derivation")] where list.count > 1 {
                warning("Only the last \(kind) of '\(name)' is kept", code: OCLDiagnosticCode.duplicateDeclaration, range: list.last?.range)
            }
            appliedCount += min(context.initialisers.count, 1) + min(context.derivations.count, 1)
            modify(location) { classifier in
                guard var eClass = classifier as? EClass else { return }
                var feature = eClass.eStructuralFeatures[index]
                if var attribute = feature as? EAttribute {
                    if let initial = context.initialisers.last { OCLConstraintAnnotations.setInitial(initial.expression, of: &attribute) }
                    if let derivation = context.derivations.last { OCLConstraintAnnotations.setDerivation(derivation.expression, of: &attribute) }
                    feature = attribute
                } else if var reference = feature as? EReference {
                    if let initial = context.initialisers.last { OCLConstraintAnnotations.setInitial(initial.expression, of: &reference) }
                    if let derivation = context.derivations.last { OCLConstraintAnnotations.setDerivation(derivation.expression, of: &reference) }
                    feature = reference
                }
                eClass.eStructuralFeatures[index] = feature
                classifier = eClass
            }
        }
    }
}
