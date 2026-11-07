//
// KM3Builder.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase

/// Turns the syntax tree of a KM3 document into native Ecore packages.
///
/// The mapping follows the KM32EMF transformation of the ATL tool chain: packages become
/// packages (nested packages become subpackages), classes become classes with their
/// supertypes, attributes whose type is a data type or enumeration become attributes,
/// attributes whose type is a class become containment references, references become
/// references, data types become data types (or built-in Ecore data types, depending on the
/// ``KM3PrimitiveTypeMapping``), enumerations become enumerations whose literals are numbered
/// from one (KM32EMF uses the one-based OCL `indexOf`), and operations become operations with parameters. Names are looked
/// up across every package of the document; when several classifiers share a name, the first
/// one in source order is used.
struct KM3Builder {
    /// A classifier that a name can refer to.
    private enum Target {
        /// A class of the document, by its index in ``classes``.
        case `class`(Int)

        /// A data type or enumeration of the document, or a built-in Ecore data type.
        case dataType(any EClassifier)
    }

    /// A class of the document together with the identifiers assigned to it and its members.
    private struct ClassEntry {
        /// The syntax of the class.
        let node: KM3ClassNode

        /// The identifier of the class.
        let id: EUUID

        /// The identifiers of the features, in the order of ``KM3ClassNode/features``.
        let featureIDs: [EUUID]

        /// The indices of the resolved direct supertypes in ``classes``.
        var supertypes: [Int] = []
    }

    /// How declared data types are treated.
    private let mapping: KM3PrimitiveTypeMapping

    /// The name of the document, for diagnostics.
    private let document: String?

    /// The classes of the document, in source order.
    private var classes: [ClassEntry] = []

    /// The classifiers by name; the first declaration of a name wins.
    private var targets: [String: Target] = [:]

    /// The identifiers of the features that contain their targets: references declared as
    /// containers and attributes, which contain when their type is a class.
    private var containments: Set<EUUID> = []

    /// The ranges of the first declaration of each classifier name, for diagnostics.
    private var declarations: [String: SourceRange] = [:]

    /// The problems found so far.
    private(set) var diagnostics: [SourceDiagnostic] = []

    /// Creates a builder.
    ///
    /// - Parameters:
    ///   - mapping: How declared data types are treated.
    ///   - document: The name of the document, which diagnostics carry.
    init(mapping: KM3PrimitiveTypeMapping, document: String?) {
        self.mapping = mapping
        self.document = document
    }

    /// Builds the packages of a document.
    ///
    /// - Parameter packages: The package declarations of the document.
    /// - Returns: The root packages, in source order, with linked class snapshots.
    mutating func build(_ packages: [KM3PackageNode]) -> [EPackage] {
        var shells: [PackageShell] = []
        var rootNames: [String: SourceRange] = [:]
        for package in packages {
            checkUnique(package.name, among: &rootNames, kind: "package")
            if let shell = declare(package) { shells.append(shell) }
        }
        resolveSupertypes()
        breakInheritanceCycles()
        let opposites = resolveOpposites()
        let built = shells.map { assemble($0, opposites: opposites) }
        return MetamodelLinker.relinked(built)
    }

    // MARK: Declarations

    /// A package whose classifiers have been declared but whose classes are not yet built.
    private struct PackageShell {
        /// The syntax of the package.
        let node: KM3PackageNode

        /// The classifiers in source order: data types and enumerations as built, classes as
        /// indices into ``classes``.
        var classifiers: [DeclaredClassifier] = []

        /// The nested packages.
        var subpackages: [PackageShell] = []
    }

    /// A classifier of a package shell.
    private enum DeclaredClassifier {
        /// A data type or enumeration.
        case built(any EClassifier)

        /// A class, by its index in ``classes``.
        case `class`(Int)
    }

    /// Declares the classifiers of a package and of its nested packages.
    ///
    /// - Parameter package: The syntax of the package.
    /// - Returns: The shell of the package, or `nil` if it only declared primitive types that
    ///   stand for built-in Ecore data types.
    private mutating func declare(_ package: KM3PackageNode) -> PackageShell? {
        var shell = PackageShell(node: package)
        var local: [String: SourceRange] = [:]
        var subpackageNames: [String: SourceRange] = [:]
        var mappedPrimitives = 0
        for element in package.elements {
            switch element {
            case .package(let nested):
                checkUnique(nested.name, among: &subpackageNames, kind: "package")
                if let nestedShell = declare(nested) { shell.subpackages.append(nestedShell) }
            case .dataType(let node):
                checkUnique(node.name, among: &local, kind: "classifier", code: .duplicateClassifier)
                if mapping == .ecore, let type = KM3PrimitiveTypes.ecoreType(forName: node.name.text) {
                    register(node.name, as: .dataType(Self.builtIn(type)))
                    mappedPrimitives += 1
                    continue
                }
                let dataType = EDataType(name: node.name.text)
                register(node.name, as: .dataType(dataType))
                shell.classifiers.append(.built(dataType))
            case .enumeration(let node):
                checkUnique(node.name, among: &local, kind: "classifier", code: .duplicateClassifier)
                var literalNames: [String: SourceRange] = [:]
                let literals = node.literals.enumerated().map { index, literal in
                    checkUnique(literal.name, among: &literalNames, kind: "literal")
                    return EEnumLiteral(name: literal.name.text, value: index + 1)
                }
                let eEnum = EEnum(name: node.name.text, literals: literals)
                register(node.name, as: .dataType(eEnum))
                shell.classifiers.append(.built(eEnum))
            case .class(let node):
                checkUnique(node.name, among: &local, kind: "classifier", code: .duplicateClassifier)
                let entry = ClassEntry(node: node, id: EUUID(), featureIDs: node.features.map { _ in EUUID() })
                for (feature, id) in zip(node.features, entry.featureIDs)
                where feature.kind == .attribute || feature.isContainer {
                    containments.insert(id)
                }
                classes.append(entry)
                register(node.name, as: .class(classes.count - 1))
                shell.classifiers.append(.class(classes.count - 1))
            }
        }
        let isOnlyPrimitives = mappedPrimitives > 0 && shell.classifiers.isEmpty && shell.subpackages.isEmpty
        return isOnlyPrimitives ? nil : shell
    }

    /// Registers a classifier name for lookups, reporting a name that another package uses.
    ///
    /// - Parameters:
    ///   - name: The name of the classifier.
    ///   - target: What the name refers to.
    private mutating func register(_ name: KM3NameNode, as target: Target) {
        if let first = declarations[name.text] {
            if !isDuplicateInSamePackage(name) {
                report(
                    .ambiguousClassifier,
                    "Another package also declares a classifier named '\(name.text)'; references use the first one",
                    name.range, severity: .warning, related: first)
            }
            return
        }
        declarations[name.text] = name.range
        targets[name.text] = target
    }

    /// Whether a classifier name has been reported as a duplicate in its own package.
    ///
    /// - Parameter name: The name.
    /// - Returns: `true` if a duplicate diagnostic covers the name.
    private func isDuplicateInSamePackage(_ name: KM3NameNode) -> Bool {
        diagnostics.contains { $0.code == KM3DiagnosticCode.duplicateClassifier.rawValue && $0.range == name.range }
    }

    /// Reports a name that is already used among its siblings.
    ///
    /// - Parameters:
    ///   - name: The name.
    ///   - names: The names of the siblings so far, which receive the name.
    ///   - kind: What the named element is, for diagnostics.
    ///   - code: The code of the diagnostic.
    private mutating func checkUnique(
        _ name: KM3NameNode, among names: inout [String: SourceRange], kind: String,
        code: KM3DiagnosticCode = .duplicateMember
    ) {
        if let first = names[name.text] {
            report(code, "There is already a \(kind) named '\(name.text)' here", name.range, related: first)
        } else {
            names[name.text] = name.range
        }
    }

    /// The built-in Ecore data type of a primitive type.
    ///
    /// - Parameter type: The Ecore data type.
    /// - Returns: The data type of ``EcorePackage``.
    private static func builtIn(_ type: EcoreDataType) -> any EClassifier {
        EcorePackage.dataType(type) ?? EDataType(name: type.rawValue)
    }

    // MARK: Supertypes

    /// Resolves the supertype names of every class.
    private mutating func resolveSupertypes() {
        for index in classes.indices {
            var resolved: [Int] = []
            for name in classes[index].node.supertypes {
                switch targets[name.text] {
                case .class(let target):
                    if resolved.contains(target) {
                        report(.duplicateMember, "'\(name.text)' is already a supertype", name.range, severity: .warning)
                    } else {
                        resolved.append(target)
                    }
                case .dataType:
                    report(.invalidTypeKind, "The supertype '\(name.text)' is not a class", name.range)
                case nil:
                    report(.unresolvedSupertype, "There is no class named '\(name.text)'", name.range)
                }
            }
            classes[index].supertypes = resolved
        }
    }

    /// Removes the supertypes that make a class inherit from itself.
    ///
    /// The classes are visited in source order; a supertype that leads back to a class on the
    /// current path is reported and dropped.
    private mutating func breakInheritanceCycles() {
        var state = [Int: Bool]()  // false while on the current path, true once finished
        /// Visits a class and its supertypes depth first, dropping supertypes on the path.
        ///
        /// - Parameter index: The index of the class.
        func visit(_ index: Int) {
            state[index] = false
            var kept: [Int] = []
            for parent in classes[index].supertypes {
                if state[parent] == false {
                    let name = classes[index].node.supertypes.first { $0.text == classes[parent].node.name.text }
                    report(
                        .cyclicInheritance,
                        "'\(classes[index].node.name.text)' cannot extend '\(classes[parent].node.name.text)', "
                            + "which inherits from it",
                        name?.range ?? classes[index].node.name.range)
                    continue
                }
                if state[parent] == nil { visit(parent) }
                kept.append(parent)
            }
            classes[index].supertypes = kept
            state[index] = true
        }
        for index in classes.indices where state[index] == nil { visit(index) }
    }

    // MARK: Opposites

    /// Resolves the opposites of the references.
    ///
    /// The opposite of a reference is looked up among the references of the referenced class
    /// and of its supertypes. Opposites that do not name each other are reported.
    ///
    /// - Returns: The identifier of the opposite of each reference, by the identifier of the
    ///   reference.
    private mutating func resolveOpposites() -> [EUUID: EUUID] {
        var opposites: [EUUID: EUUID] = [:]
        var declared: [EUUID: (owner: Int, feature: Int)] = [:]
        for (owner, entry) in classes.enumerated() {
            for (index, feature) in entry.node.features.enumerated() {
                guard feature.kind == .reference, let opposite = feature.opposite else { continue }
                guard let typeName = feature.type?.text, case .class(let target) = targets[typeName] else { continue }
                guard let found = lookUpFeature(named: opposite.text, from: target) else {
                    report(
                        .unresolvedOpposite,
                        "The class '\(typeName)' has no reference named '\(opposite.text)'", opposite.range)
                    continue
                }
                let candidate = classes[found.owner].node.features[found.feature]
                guard candidate.kind == .reference else {
                    report(
                        .invalidTypeKind, "'\(typeName).\(opposite.text)' is an attribute, not a reference",
                        opposite.range)
                    continue
                }
                opposites[entry.featureIDs[index]] = classes[found.owner].featureIDs[found.feature]
                declared[entry.featureIDs[index]] = (owner, index)
            }
        }
        for (reference, opposite) in opposites.sorted(by: { $0.key.uuidString < $1.key.uuidString }) {
            guard let location = declared[reference] else { continue }
            let node = classes[location.owner].node.features[location.feature]
            let back = opposites[opposite]
            guard back != reference else { continue }
            let ownerName = classes[location.owner].node.name.text
            let message = back == nil
                ? "'\(ownerName).\(node.name.text)' names '\(node.opposite?.text ?? "")' as its opposite, "
                    + "which does not name it in return"
                : "'\(ownerName).\(node.name.text)' names '\(node.opposite?.text ?? "")' as its opposite, "
                    + "which names another reference"
            report(.inconsistentOpposite, message, node.opposite?.range ?? node.name.range, severity: .warning)
        }
        return opposites
    }

    /// Finds a feature by name in a class or its supertypes, breadth first.
    ///
    /// - Parameters:
    ///   - name: The name of the feature.
    ///   - start: The index of the class.
    /// - Returns: The class and position of the feature, or `nil` if there is none.
    private func lookUpFeature(named name: String, from start: Int) -> (owner: Int, feature: Int)? {
        var queue = [start]
        var visited: Set<Int> = []
        while !queue.isEmpty {
            let index = queue.removeFirst()
            guard visited.insert(index).inserted else { continue }
            if let position = classes[index].node.features.firstIndex(where: { $0.name.text == name }) {
                return (index, position)
            }
            queue += classes[index].supertypes
        }
        return nil
    }

    // MARK: Assembly

    /// Builds a package with its classes and nested packages.
    ///
    /// - Parameters:
    ///   - shell: The declared package.
    ///   - opposites: The opposites of the references.
    /// - Returns: The package.
    private mutating func assemble(_ shell: PackageShell, opposites: [EUUID: EUUID]) -> EPackage {
        let classifiers: [any EClassifier] = shell.classifiers.map { classifier in
            switch classifier {
            case .built(let built): return built
            case .class(let index): return buildClass(index, opposites: opposites)
            }
        }
        return EPackage(
            name: shell.node.name.text, nsURI: shell.node.nsURI ?? "", nsPrefix: shell.node.nsPrefix ?? "",
            eClassifiers: classifiers,
            eSubpackages: shell.subpackages.map { assemble($0, opposites: opposites) })
    }

    /// Builds a class with its features and operations.
    ///
    /// Types and supertypes are placeholders that carry the identifiers of their classes;
    /// linking replaces them by snapshots of the complete classes.
    ///
    /// - Parameters:
    ///   - index: The index of the class.
    ///   - opposites: The opposites of the references.
    /// - Returns: The class.
    private mutating func buildClass(_ index: Int, opposites: [EUUID: EUUID]) -> EClass {
        let entry = classes[index]
        var members: [String: SourceRange] = [:]
        var features: [any EStructuralFeature] = []
        for (position, node) in entry.node.features.enumerated() {
            checkUnique(node.name, among: &members, kind: "feature")
            let id = entry.featureIDs[position]
            features.append(buildFeature(node, id: id, opposite: opposites[id], opposites: opposites))
        }
        let operations = entry.node.operations.map { node -> EOperation in
            var parameterNames: [String: SourceRange] = [:]
            let parameters = node.parameters.map { parameter -> EParameter in
                checkUnique(parameter.name, among: &parameterNames, kind: "parameter")
                return EParameter(name: parameter.name.text, eType: parameter.type.map { resolveType($0) })
            }
            return EOperation(name: node.name.text, eType: node.returnType.map { resolveType($0) }, eParameters: parameters)
        }
        return EClass(
            id: entry.id, name: entry.node.name.text, isAbstract: entry.node.isAbstract,
            eSuperTypes: entry.supertypes.map { placeholder(for: $0) },
            eStructuralFeatures: features, eOperations: operations)
    }

    /// Builds an attribute or reference.
    ///
    /// - Parameters:
    ///   - node: The syntax of the feature.
    ///   - id: The identifier of the feature.
    ///   - opposite: The identifier of the opposite reference, if any.
    ///   - opposites: The opposites of all references, to tell whether the opposite contains.
    /// - Returns: An attribute for an attribute of a data type or enumeration, otherwise a
    ///   reference.
    private mutating func buildFeature(
        _ node: KM3FeatureNode, id: EUUID, opposite: EUUID?, opposites: [EUUID: EUUID]
    ) -> any EStructuralFeature {
        let lower = node.multiplicity.lower
        let upper = node.multiplicity.upper
        if !node.subsets.isEmpty, let first = node.subsets.first, let last = node.subsets.last {
            report(
                .unsupportedConstruct, "Ecore has no counterpart of 'subsets'; it is ignored",
                first.range.union(last.range), severity: .warning)
        }
        let type = node.type.map { resolveType($0, preferringClass: node.kind == .reference) }
            ?? EDataType(name: "")
        let isClassType = type is EClass
        switch (node.kind, isClassType) {
        case (.attribute, false):
            return EAttribute(
                id: id, name: node.name.text, eType: type, lowerBound: lower, upperBound: upper,
                ordered: node.isOrdered, unique: node.isUnique)
        case (.attribute, true):
            return EReference(
                id: id, name: node.name.text, eType: type, lowerBound: lower, upperBound: upper,
                containment: true, ordered: node.isOrdered)
        case (.reference, true):
            return EReference(
                id: id, name: node.name.text, eType: type, lowerBound: lower, upperBound: upper,
                containment: node.isContainer, opposite: opposite, ordered: node.isOrdered,
                container: opposite.map { containments.contains($0) } ?? false)
        case (.reference, false):
            if let typeName = node.type, targets[typeName.text] != nil {
                report(
                    .invalidTypeKind,
                    "The type '\(typeName.text)' of reference '\(node.name.text)' is not a class; "
                        + "declare it as an attribute", typeName.range)
            }
            return EAttribute(
                id: id, name: node.name.text, eType: type, lowerBound: lower, upperBound: upper,
                ordered: node.isOrdered, unique: true)
        }
    }

    /// Resolves a type name.
    ///
    /// An unresolved name is reported; the type is then a stand-in of the name that belongs to
    /// no package: a class where a class is expected, otherwise a data type.
    ///
    /// - Parameters:
    ///   - name: The type name.
    ///   - preferringClass: Whether a stand-in for an unresolved name is a class.
    /// - Returns: The classifier.
    private mutating func resolveType(_ name: KM3NameNode, preferringClass: Bool = false) -> any EClassifier {
        switch targets[name.text] {
        case .class(let index): return placeholder(for: index)
        case .dataType(let type): return type
        case nil:
            report(.unresolvedType, "There is no classifier named '\(name.text)'", name.range)
            return preferringClass ? EClass(name: name.text) as any EClassifier : EDataType(name: name.text)
        }
    }

    /// A placeholder for a class that linking replaces by a snapshot of the class.
    ///
    /// - Parameter index: The index of the class.
    /// - Returns: A class with the identifier and name of the class.
    private func placeholder(for index: Int) -> EClass {
        EClass(id: classes[index].id, name: classes[index].node.name.text, isAbstract: classes[index].node.isAbstract)
    }

    // MARK: Diagnostics

    /// Records a problem.
    ///
    /// - Parameters:
    ///   - code: The code of the problem.
    ///   - message: The description of the problem.
    ///   - range: The text the problem concerns.
    ///   - severity: How serious the problem is.
    ///   - related: The range of a related declaration, if any.
    private mutating func report(
        _ code: KM3DiagnosticCode, _ message: String, _ range: SourceRange, severity: DiagnosticSeverity = .error,
        related: SourceRange? = nil
    ) {
        let context = related.map {
            [SourceDiagnostic(
                severity: .information, code: code.rawValue, message: "The other declaration is here", range: $0,
                document: document)]
        } ?? []
        diagnostics.append(
            SourceDiagnostic(
                severity: severity, code: code.rawValue, message: message, range: range, document: document,
                related: context))
    }
}
