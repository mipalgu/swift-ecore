//
// MultiLevelViews.swift
// MultiLevel
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import ECore
public import EMFBase
import Foundation
import OrderedCollections

/// A read-only view of one level of a deep model as an Ecore package and a resource.
///
/// Every clabject above the level that can still be instantiated (a *type facet*) becomes a
/// class, and its ontological type becomes a supertype of that class, next to its own
/// supertypes. Ecore tools that test types by supertypes, such as AQL's `oclIsKindOf` and
/// `allInstances` and ATL's rule matching, therefore see every clabject of the level as an
/// instance of all its deep types: a rule for `ProductType` matches the books of a shop two
/// levels below.
///
/// A class carries the features of its clabject whose slots fall at the level of the view.
/// A feature whose slot lies above the level (a type-level slot such as a VAT rate given for
/// a product type) appears as a derived, unchangeable attribute that holds the value found
/// along the type chain, and a feature that a lower clabject instantiates under another
/// name holds the values of the instantiating slots. Each clabject of the level becomes an
/// object whose identifier is the identifier of the clabject. Values include defaults.
///
/// The view is a snapshot; changes to its resource are not written back. Use a
/// ``LevelPairView`` to edit a level.
public struct DeepLevelView: Sendable {
    /// The level that the view shows.
    public let level: Int

    /// The package of the classes of the view.
    public let package: EPackage

    /// The resource that holds the objects of the view.
    public let resource: Resource

    /// The model that the view shows.
    public let model: DeepModel

    /// The clabject of each class of the view, by class identifier.
    public let classClabjects: [EUUID: EUUID]

    /// The namespace URI of the package.
    public var namespaceURI: String { package.nsURI }

    /// The clabject that an object of the view stands for.
    ///
    /// - Parameter object: An object of the view, or a value that refers to one.
    /// - Returns: The clabject, or `nil` if the object is not part of the model.
    public func clabject(of object: any EObject) -> Clabject? {
        model.clabject(object.id)
    }

    /// The clabject whose type facet, or synthesised object facet, a class is.
    ///
    /// - Parameter eClass: A class of the view.
    /// - Returns: The clabject, or `nil` if the class is not part of the view.
    public func clabject(ofClass eClass: EClass) -> Clabject? {
        classClabjects[eClass.id].flatMap(model.clabject)
    }

    /// The class of the view that stands for a clabject.
    ///
    /// - Parameter clabject: The identifier of the clabject.
    /// - Returns: The class, or `nil` if the clabject has no class in the view.
    public func eClass(of clabject: EUUID) -> EClass? {
        package.eClassifiers.compactMap { $0 as? EClass }.first { classClabjects[$0.id] == clabject }
    }
}

/// A writable view of two adjacent levels: the type facets of the upper level as an Ecore
/// package and the clabjects of the lower level as objects.
///
/// A class carries every feature visible at its clabject that is a slot at the lower level;
/// those that may still change there are changeable, and type-level slots are derived and
/// unchangeable. Supertypes are the clabject's own supertypes, and a clabject with leap
/// potency whose instances reside at the lower level contributes a synthesised class. The
/// objects hold the explicit slots of their clabjects; inherited defaults are the default
/// values of the attributes.
///
/// After the resource has been edited, for example as the target of a transformation,
/// ``committed()`` returns the deep model with the changes applied: changed slots, new
/// clabjects for new objects (with generated names), and without clabjects whose objects were
/// removed.
public struct LevelPairView: Sendable {
    /// The lower level, whose clabjects are the objects of the view.
    public let level: Int

    /// The package of the classes of the view.
    public let package: EPackage

    /// The resource that holds the objects of the view.
    public let resource: Resource

    /// The model that the view was taken from.
    public let model: DeepModel

    /// The clabject of each class of the view, by class identifier.
    public let classClabjects: [EUUID: EUUID]

    /// The objects that the view was created with, by identifier.
    let originalObjects: Set<EUUID>

    /// The namespace URI of the package.
    public var namespaceURI: String { package.nsURI }

    /// The deep model with the changes made to the resource applied.
    ///
    /// - Returns: The updated model; validate it to check the changes.
    public func committed() async -> DeepModel {
        var updated = model
        let index = DeepIndex(model)
        guard let position = model.levels.indices.first(where: { model.levelNumber(ofModelAt: $0) == level }) else {
            return model
        }
        let classes = Dictionary(
            package.eClassifiers.compactMap { $0 as? EClass }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var present: Set<EUUID> = []
        var usedNames = Set(model.levels[position].clabjects.map(\.name))
        for object in await resource.getAllObjects() {
            guard let dynamic = object as? DynamicEObject, let eClass = classes[dynamic.eClass.id],
                let classClabject = classClabjects[eClass.id]
            else { continue }
            present.insert(dynamic.id)
            var clabject: Clabject
            if let existing = updated.levels[position].clabjects.first(where: { $0.id == dynamic.id }) {
                clabject = existing
            } else {
                let name = Self.generatedName(for: dynamic.id, avoiding: usedNames)
                usedNames.insert(name)
                let isOwnFacet = classClabject == dynamic.id
                clabject = Clabject(id: dynamic.id, name: name, type: isOwnFacet ? nil : classClabject)
                updated.levels[position].clabjects.append(clabject)
            }
            for feature in eClass.allStructuralFeatures where Self.isChangeable(feature) && !Self.isDerived(feature) {
                let values = dynamic.eIsSet(feature.name) ? Self.deepValues(of: dynamic.eGet(feature.name)) : []
                if let existing = clabject.slots.firstIndex(where: { $0.feature == feature.name }) {
                    if values.isEmpty {
                        clabject.slots.remove(at: existing)
                    } else {
                        clabject.slots[existing].values = values
                    }
                } else if !values.isEmpty {
                    clabject.slots.append(DeepSlot(feature: feature.name, values: values))
                }
            }
            if let slot = updated.levels[position].clabjects.firstIndex(where: { $0.id == clabject.id }) {
                updated.levels[position].clabjects[slot] = clabject
            }
        }
        let removed = originalObjects.subtracting(present)
        updated.levels[position].clabjects.removeAll { removed.contains($0.id) && index.location[$0.id] != nil }
        return updated
    }

    /// A name for a new clabject, derived from its identifier and unique within its model.
    static func generatedName(for id: EUUID, avoiding names: Set<String>) -> String {
        let hex = id.uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        var length = 8
        while length < hex.count, names.contains(MultiLevelSyntax.anonymousPrefix + hex.prefix(length)) { length += 4 }
        return MultiLevelSyntax.anonymousPrefix + hex.prefix(length)
    }

    /// Whether a feature may be changed.
    static func isChangeable(_ feature: any EStructuralFeature) -> Bool {
        (feature as? EAttribute)?.changeable ?? (feature as? EReference)?.changeable ?? false
    }

    /// Whether a feature is derived.
    static func isDerived(_ feature: any EStructuralFeature) -> Bool {
        (feature as? EAttribute)?.derived ?? (feature as? EReference)?.derived ?? false
    }

    /// The deep values of an Ecore value.
    static func deepValues(of value: (any EcoreValue)?) -> [DeepValue] {
        switch value {
        case nil: return []
        case let text as String: return [.string(text)]
        case let flag as Bool: return [.boolean(flag)]
        case let number as Int: return [.integer(number)]
        case let number as Int64: return [.integer(Int(number))]
        case let number as Double: return [.real(number)]
        case let number as Float: return [.real(Double(number))]
        case let id as EUUID: return [.object(id)]
        case let object as any EObject: return [.object(object.id)]
        case let array as EcoreValueArray: return array.values.flatMap { deepValues(of: $0) }
        case let texts as [String]: return texts.map { .string($0) }
        case let numbers as [Int]: return numbers.map { .integer($0) }
        case let numbers as [Double]: return numbers.map { .real($0) }
        case let flags as [Bool]: return flags.map { .boolean($0) }
        case let ids as [EUUID]: return ids.map { .object($0) }
        case let values as [any EcoreValue]: return values.flatMap { deepValues(of: $0) }
        default: return []
        }
    }
}

extension DeepModel {
    /// Creates the read-only deep view of a level.
    ///
    /// - Parameters:
    ///   - level: The level to view.
    ///   - resourceSet: The resource set that receives the resource of the view and in which
    ///     its package is registered (default a new resource set). Views of several levels
    ///     in one resource set resolve level-crossing references among each other.
    /// - Returns: The view.
    /// - Throws: ``MultiLevelError/noSuchLevel(_:)`` if the model has no such level.
    public func deepLevelView(atLevel level: Int, in resourceSet: ResourceSet = ResourceSet()) async throws
        -> DeepLevelView
    {
        let built = try ViewBuilder(model: self, level: level, kind: .deep).build()
        let resource = await built.install(in: resourceSet)
        return DeepLevelView(
            level: level, package: built.package, resource: resource, model: self, classClabjects: built.classClabjects)
    }

    /// Creates the read-only deep views of every level in one resource set.
    ///
    /// - Parameter resourceSet: The resource set that receives the views.
    /// - Returns: The views, from the top level down.
    /// - Throws: The error of creating a view.
    public func deepLevelViews(in resourceSet: ResourceSet) async throws -> [DeepLevelView] {
        var views: [DeepLevelView] = []
        for level in levelNumbers { views.append(try await deepLevelView(atLevel: level, in: resourceSet)) }
        return views
    }

    /// Creates the writable view of a level and the level above it.
    ///
    /// - Parameters:
    ///   - level: The lower level, whose clabjects become objects.
    ///   - resourceSet: The resource set that receives the resource of the view and in which
    ///     its package is registered (default a new resource set).
    /// - Returns: The view.
    /// - Throws: ``MultiLevelError/noSuchLevel(_:)`` if the model has no such level.
    public func levelPairView(atLevel level: Int, in resourceSet: ResourceSet = ResourceSet()) async throws
        -> LevelPairView
    {
        let built = try ViewBuilder(model: self, level: level, kind: .pair).build()
        let resource = await built.install(in: resourceSet)
        return LevelPairView(
            level: level, package: built.package, resource: resource, model: self, classClabjects: built.classClabjects,
            originalObjects: Set(built.objects.map(\.id)))
    }

    /// The Ecore metamodel of a level: the classes of its level-pair view, annotated with
    /// the levels and potencies of their clabjects and features.
    ///
    /// The export is one-way: Ecore cannot hold instances of instances or slots of classes,
    /// so the annotations record, but do not restore, the multi-level information.
    ///
    /// - Parameter level: The level whose metamodel is exported.
    /// - Returns: The package.
    /// - Throws: ``MultiLevelError/noSuchLevel(_:)`` if the model has no such level.
    public func ecorePackage(forLevel level: Int) throws -> EPackage {
        try ViewBuilder(model: self, level: level, kind: .pair).build().package
    }
}

extension MultiLevelError {
    /// The error raised for a level that a deep model does not have.
    ///
    /// - Parameter level: The level.
    /// - Returns: An ``invalidValue(_:)`` error naming the level.
    public static func noSuchLevel(_ level: Int) -> MultiLevelError {
        .invalidValue("level \(level) does not exist")
    }
}

// MARK: - Building

/// The package and objects of a view, before they are installed in a resource.
struct BuiltView {
    /// The package of classes that the view declares.
    let package: EPackage
    /// The objects of the view.
    let objects: [DynamicEObject]
    /// The identifiers of the clabjects that the classes of the package stand for, by the identifier of the class.
    let classClabjects: [EUUID: EUUID]
    /// The namespace URI of the package, which is also the URI of the resource.
    let uri: String

    /// Registers the package and adds the objects to a new resource of a resource set.
    func install(in resourceSet: ResourceSet) async -> Resource {
        await resourceSet.registerMetamodel(package)
        let resource = await resourceSet.createResource(uri: uri)
        await resource.add(contentsOf: objects)
        return resource
    }
}

/// Builds the package and objects of a deep level view or a level-pair view.
struct ViewBuilder {
    /// The kinds of view.
    enum Kind {
        /// The read-only deep level view.
        case deep
        /// The writable level-pair view.
        case pair

        /// The suffix of the namespace URI.
        var suffix: String { self == .deep ? MultiLevelSyntax.deepViewSuffix : MultiLevelSyntax.pairViewSuffix }
    }

    /// One structural feature of a class, with what it shows.
    struct ClassFeature {
        /// The declaration that the feature shows.
        let reference: FeatureReference
        /// The feature as declared.
        let feature: DeepFeature
        /// How the values of the feature are found.
        let source: ValueSource
    }

    /// How the values of a feature of a view are found.
    enum ValueSource {
        /// The slot of the feature itself, or the slots of the features that instantiate it.
        case slot
        /// The value found along the type chain (a type-level slot).
        case typeLevel
    }

    /// The model that the view shows.
    let model: DeepModel
    /// The index of the model.
    let index: DeepIndex
    /// The level that the view shows.
    let level: Int
    /// The kind of view to build.
    let kind: Kind
    /// The position in the model's chain of the level model that holds the level's clabjects.
    let modelPosition: Int

    /// Creates a builder.
    ///
    /// - Parameters:
    ///   - model: The model to show.
    ///   - level: The level whose clabjects the view shows.
    ///   - kind: The kind of view to build.
    /// - Throws: ``MultiLevelError/noSuchLevel(_:)`` if the model has no such level.
    init(model: DeepModel, level: Int, kind: Kind) throws {
        guard let position = model.levels.indices.first(where: { model.levelNumber(ofModelAt: $0) == level }) else {
            throw MultiLevelError.noSuchLevel(level)
        }
        self.model = model
        self.index = DeepIndex(model)
        self.level = level
        self.kind = kind
        self.modelPosition = position
    }

    /// The namespace URI of the view.
    var namespaceURI: String {
        MultiLevelSyntax.viewNamespacePrefix + "\(model.name):\(model.levels[modelPosition].name):\(kind.suffix)"
    }

    /// The name of the package: the type model of the level, or the level model at the top.
    var packageName: String {
        model.levels[modelPosition].typeModel ?? model.levels[modelPosition].name
    }

    // MARK: Facets

    /// The clabjects that have a class in the view, from the top level down.
    func facetClabjects() -> [EUUID] {
        var facets = OrderedSet<EUUID>()
        for (position, levelModel) in model.levels.enumerated() {
            let number = model.levelNumber(ofModelAt: position)
            for clabject in levelModel.clabjects {
                guard let potency = index.potency(of: clabject.id), !potency.isZero else { continue }
                switch kind {
                case .deep:
                    if number > level { facets.append(clabject.id) }
                case .pair:
                    let residence = number - index.instantiationOffset(of: clabject.id)
                    if number == level + 1 || (clabject.isLeap && residence == level) {
                        for member in index.superTypesInclusive(of: clabject.id) { facets.append(member) }
                    }
                }
            }
        }
        return facets.elements
    }

    /// The direct supertypes of the class of a clabject.
    func superFacets(of id: EUUID, among facets: Set<EUUID>) -> [EUUID] {
        guard let clabject = index.clabject(id) else { return [] }
        var supers: [EUUID] = []
        if kind == .deep, let type = clabject.type, facets.contains(type) { supers.append(type) }
        supers += clabject.supertypes.filter { facets.contains($0) && $0 != id }
        return supers
    }

    /// The features that the class of a clabject declares itself.
    func classFeatures(of id: EUUID, inherited: Set<String>) -> [ClassFeature] {
        guard let clabject = index.clabject(id), let clabjectLevel = index.level(of: id) else { return [] }
        var result: [ClassFeature] = []
        var names = inherited
        switch kind {
        case .deep:
            let levelsBelow = clabjectLevel - level
            for feature in clabject.features where !names.contains(feature.name) {
                let (durability, mutability) = index.durability(of: feature, ownedBy: id)
                let source: ValueSource
                if model.potencyScheme.role(durability: durability, mutability: mutability, levelsBelow: levelsBelow).isSlot {
                    source = .slot
                } else if hadSlotAbove(durability: durability, mutability: mutability, levelsBelow: levelsBelow) {
                    source = .typeLevel
                } else {
                    continue
                }
                names.insert(feature.name)
                result.append(ClassFeature(reference: FeatureReference(clabject: id, name: feature.name), feature: feature, source: source))
            }
        case .pair:
            let offset = clabjectLevel - level
            for resolved in index.visibleFeatures(of: id) where !names.contains(resolved.feature.name) {
                let levelsBelow = resolved.levelsBelow + offset
                let role = model.potencyScheme.role(
                    durability: resolved.durability, mutability: resolved.mutability, levelsBelow: levelsBelow)
                let source: ValueSource
                if role.isSlot {
                    source = .slot
                } else if hadSlotAbove(durability: resolved.durability, mutability: resolved.mutability, levelsBelow: levelsBelow) {
                    source = .typeLevel
                } else {
                    continue
                }
                names.insert(resolved.feature.name)
                result.append(ClassFeature(reference: resolved.reference, feature: resolved.feature, source: source))
            }
        }
        return result
    }

    /// Whether a feature that is no slot at some levels below its declaration was a slot at a
    /// level above them.
    func hadSlotAbove(durability: Potency, mutability: Potency?, levelsBelow: Int) -> Bool {
        guard !model.potencyScheme.role(durability: durability, mutability: mutability, levelsBelow: levelsBelow).exists
        else { return false }
        return (0..<max(levelsBelow, 0)).contains {
            model.potencyScheme.role(durability: durability, mutability: mutability, levelsBelow: $0).isSlot
        }
    }

    // MARK: Classes

    /// The data type of a feature in Ecore.
    static func dataType(named name: String) -> EDataType {
        let ecoreName = MultiLevelSyntax.dataTypes[name] ?? EcoreDataType.eString.rawValue
        return EcoreDataType(rawValue: ecoreName).flatMap(EcorePackage.dataType) ?? EDataType(name: ecoreName)
    }

    /// The annotation that records the level and potency of a clabject or feature.
    func annotation(_ details: [(String, String)]) -> EAnnotation {
        var ordered = OrderedDictionary<String, String>()
        for (key, value) in details { ordered[key] = value }
        return EAnnotation(source: MultiLevelSyntax.annotationSource, orderedDetails: ordered)
    }

    /// The identifier of the class of a clabject.
    static func classIdentifier(of id: EUUID) -> EUUID { MultiLevelIdentifiers.typeFacetIdentifier(of: id) }

    /// Builds the package and objects of the view.
    func build() throws -> BuiltView {
        let facets = facetClabjects()
        let facetSet = Set(facets)
        var built: [EUUID: EClass] = [:]
        var visiting: Set<EUUID> = []
        var classClabjects: [EUUID: EUUID] = [:]

        func shell(_ id: EUUID) -> EClass {
            EClass(id: Self.classIdentifier(of: id), name: index.clabject(id)?.name ?? id.uuidString)
        }

        func build(_ id: EUUID) -> EClass? {
            if let existing = built[id] { return existing }
            guard visiting.insert(id).inserted, let clabject = index.clabject(id) else { return nil }
            defer { visiting.remove(id) }
            let supers = superFacets(of: id, among: facetSet).compactMap(build)
            let inherited = Set(supers.flatMap { $0.allStructuralFeatures.map(\.name) })
            let features = classFeatures(of: id, inherited: inherited)
            var structural: [any EStructuralFeature] = features.map { structuralFeature($0, owner: id) }
            if let ends = clabject.ends, !supers.contains(where: { $0.getEReference(name: MultiLevelSyntax.edgeSourceName) != nil }) {
                structural.append(EReference(name: MultiLevelSyntax.edgeSourceName, eType: shell(ends.source.clabject)))
                structural.append(EReference(name: MultiLevelSyntax.edgeTargetName, eType: shell(ends.target.clabject)))
            }
            var details: [(String, String)] = [(MultiLevelSyntax.clabjectKey, clabject.name)]
            if let clabjectLevel = index.level(of: id) { details.append((MultiLevelSyntax.levelKey, String(clabjectLevel))) }
            if let potency = index.potency(of: id) { details.append((MultiLevelSyntax.potencyKey, potency.description)) }
            if clabject.isLeap { details.append((MultiLevelSyntax.leapKey, String(true))) }
            let eClass = EClass(
                id: Self.classIdentifier(of: id), name: clabject.name, isAbstract: clabject.isAbstract, eSuperTypes: supers,
                eStructuralFeatures: structural, eAnnotations: [annotation(details)])
            built[id] = eClass
            classClabjects[eClass.id] = id
            return eClass
        }

        func structuralFeature(_ classFeature: ClassFeature, owner: EUUID) -> any EStructuralFeature {
            let feature = classFeature.feature
            let (durability, mutability) = index.durability(of: feature, ownedBy: classFeature.reference.clabject)
            var details: [(String, String)] = [(MultiLevelSyntax.potencyKey, durability.description)]
            if let mutability { details.append((MultiLevelSyntax.mutabilityKey, mutability.description)) }
            if classFeature.source == .typeLevel { details.append((MultiLevelSyntax.typeLevelSlotKey, String(true))) }
            let isComputed = classFeature.source != .slot || feature.isDerived
            let changeable = kind == .pair && !isComputed && isMutable(classFeature, owner: owner)
            let upper = feature.upperBound
            switch feature.type {
            case .data(let dataType):
                return EAttribute(
                    name: feature.name, eType: Self.dataType(named: dataType), lowerBound: isComputed ? 0 : feature.lowerBound,
                    upperBound: upper, changeable: changeable, defaultValueLiteral: defaultLiteral(of: classFeature, owner: owner),
                    eAnnotations: [annotation(details)], ordered: feature.isOrdered, unique: feature.isUnique,
                    derived: isComputed)
            case .reference(let target):
                return EReference(
                    name: feature.name, eType: shell(target), lowerBound: isComputed ? 0 : feature.lowerBound,
                    upperBound: upper, changeable: changeable, containment: feature.isContainment && !isComputed,
                    eAnnotations: [annotation(details)], ordered: feature.isOrdered, unique: feature.isUnique,
                    derived: isComputed)
            }
        }

        func isMutable(_ classFeature: ClassFeature, owner: EUUID) -> Bool {
            guard let ownerLevel = index.level(of: owner) else { return false }
            let feature = classFeature.feature
            let (durability, mutability) = index.durability(of: feature, ownedBy: classFeature.reference.clabject)
            let declaringLevel = index.level(of: classFeature.reference.clabject) ?? ownerLevel
            return model.potencyScheme.role(
                durability: durability, mutability: mutability, levelsBelow: declaringLevel - level
            ).isMutable
        }

        func defaultLiteral(of classFeature: ClassFeature, owner: EUUID) -> String? {
            guard kind == .pair, classFeature.source == .slot, !classFeature.feature.isMany,
                let value = index.values(of: classFeature.feature.name, at: owner)?.first
            else { return nil }
            switch value {
            case .string(let text), .literal(let text): return text
            case .integer(let number): return String(number)
            case .real(let number): return String(number)
            case .boolean(let flag): return String(flag)
            case .object: return nil
            }
        }

        for facet in facets { _ = build(facet) }

        // Objects of the level, with a synthesised class where the clabject needs one.
        var objectClasses: [EUUID: EClass] = [:]
        var objectFeatures: [EUUID: [ClassFeature]] = [:]
        var synthesised: [EClass] = []
        let levelModel = model.levels[modelPosition]
        let facetNames = Set(built.values.map(\.name))
        for clabject in levelModel.clabjects {
            let typeClass: EClass? = clabject.type.flatMap { built[$0] }
            let ownSlots = clabject.features.filter { feature in
                let (durability, mutability) = index.durability(of: feature, ownedBy: clabject.id)
                return model.potencyScheme.role(durability: durability, mutability: mutability, levelsBelow: 0).isSlot
            }
            if let typeClass, ownSlots.isEmpty {
                objectClasses[clabject.id] = typeClass
                continue
            }
            guard typeClass != nil || clabject.type == nil else { continue }
            let inherited = Set(typeClass?.allStructuralFeatures.map(\.name) ?? [])
            let features = ownSlots.filter { !inherited.contains($0.name) }.map {
                ClassFeature(reference: FeatureReference(clabject: clabject.id, name: $0.name), feature: $0, source: .slot)
            }
            let name = facetNames.contains(clabject.name) ? clabject.name + "_" + clabject.id.uuidString.prefix(8) : clabject.name
            let eClass = EClass(
                id: MultiLevelIdentifiers.identifier(for: ["object-facet", clabject.id.uuidString]), name: name,
                eSuperTypes: typeClass.map { [$0] } ?? [],
                eStructuralFeatures: features.map { structuralFeature($0, owner: clabject.id) },
                eAnnotations: [annotation([(MultiLevelSyntax.clabjectKey, clabject.name), (MultiLevelSyntax.levelKey, String(level))])])
            synthesised.append(eClass)
            objectClasses[clabject.id] = eClass
            objectFeatures[clabject.id] = features
            classClabjects[eClass.id] = clabject.id
        }
        let edgeContributions = edgeContributions()
        var objects: [DynamicEObject] = []
        for clabject in levelModel.clabjects {
            guard let eClass = objectClasses[clabject.id] else { continue }
            var object = DynamicEObject(id: clabject.id, eClass: eClass)
            var lineage = classLineage(of: clabject.id, built: built)
            lineage.append(contentsOf: objectFeatures[clabject.id] ?? [])
            for classFeature in lineage {
                let values = self.values(of: classFeature, at: clabject.id, edges: edgeContributions)
                guard !values.isEmpty else { continue }
                if kind == .pair, classFeature.source == .slot, !hasExplicitSlot(classFeature, at: clabject.id) { continue }
                object.eSet(classFeature.feature.name, value: Self.ecoreValue(values, feature: classFeature.feature))
            }
            if let ends = clabject.ends {
                object.eSet(MultiLevelSyntax.edgeSourceName, value: ends.source.clabject)
                object.eSet(MultiLevelSyntax.edgeTargetName, value: ends.target.clabject)
            }
            objects.append(object)
        }
        let classes = facets.compactMap { built[$0] } + synthesised
        let package = EPackage(
            id: MultiLevelIdentifiers.packageIdentifier(of: namespaceURI), name: packageName, nsURI: namespaceURI,
            nsPrefix: packageName.lowercased(), eClassifiers: classes)
        return BuiltView(package: package, objects: objects, classClabjects: classClabjects, uri: namespaceURI)
    }

    /// The class features of the class of a clabject's type and all its supertypes.
    func classLineage(of id: EUUID, built: [EUUID: EClass]) -> [ClassFeature] {
        guard let clabject = index.clabject(id) else { return [] }
        var owners = OrderedSet<EUUID>()
        var pending: [EUUID] = clabject.type.map { [$0] } ?? []
        while !pending.isEmpty {
            let current = pending.removeFirst()
            guard built[current] != nil, owners.append(current).inserted else { continue }
            pending += superFacets(of: current, among: Set(built.keys))
        }
        var names: Set<String> = []
        var result: [ClassFeature] = []
        for owner in owners.reversed() {
            let inherited = Set(superFacets(of: owner, among: Set(built.keys)).flatMap { built[$0]?.allStructuralFeatures.map(\.name) ?? [] })
            for feature in classFeatures(of: owner, inherited: inherited) where names.insert(feature.feature.name).inserted {
                result.append(feature)
            }
        }
        return result
    }

    /// Whether a clabject holds an explicit slot for a feature, or for a feature that
    /// instantiates it.
    func hasExplicitSlot(_ classFeature: ClassFeature, at id: EUUID) -> Bool {
        index.superTypesInclusive(of: id).contains { member in
            index.clabject(member)?.slot(named: classFeature.feature.name) != nil
        }
    }

    /// The values of a feature of a class at an object.
    func values(of classFeature: ClassFeature, at id: EUUID, edges: [EUUID: [String: [DeepValue]]]) -> [DeepValue] {
        let name = classFeature.feature.name
        let visible = index.visibleFeatures(of: id).first { $0.feature.name == name }
        var values: [DeepValue]
        switch classFeature.source {
        case .typeLevel:
            values = index.values(of: name, at: id) ?? []
        case .slot:
            if let visible, visible.reference == classFeature.reference || index.instantiates(visible.reference, classFeature.reference) {
                values = index.values(of: name, at: id) ?? []
            } else {
                values = index.values(instantiating: classFeature.reference, at: id)
            }
        }
        if values.isEmpty, let contributed = edges[id]?[name] { values = contributed }
        return values
    }

    /// The reference values that edges contribute, by end clabject and reference name.
    func edgeContributions() -> [EUUID: [String: [DeepValue]]] {
        var contributions: [EUUID: [String: [DeepValue]]] = [:]
        for clabject in model.levels[modelPosition].clabjects {
            guard let ends = clabject.ends else { continue }
            for type in index.deepTypes(of: clabject.id) {
                guard let typeEnds = index.clabject(type)?.ends else { continue }
                if let feature = typeEnds.source.feature {
                    contributions[ends.source.clabject, default: [:]][feature, default: []].append(.object(ends.target.clabject))
                }
                if let feature = typeEnds.target.feature {
                    contributions[ends.target.clabject, default: [:]][feature, default: []].append(.object(ends.source.clabject))
                }
                break
            }
        }
        return contributions
    }

    /// The Ecore value of deep values for a feature.
    static func ecoreValue(_ values: [DeepValue], feature: DeepFeature) -> any EcoreValue {
        let ecoreName = feature.type.target == nil ? MultiLevelSyntax.dataTypes[feature.type.dataTypeName ?? ""] : nil
        let converted: [any EcoreValue] = values.map { value in
            switch value {
            case .string(let text), .literal(let text): return text
            case .integer(let number):
                return ecoreName == EcoreDataType.eDouble.rawValue || ecoreName == EcoreDataType.eFloat.rawValue
                    ? Double(number) : number
            case .real(let number): return number
            case .boolean(let flag): return flag
            case .object(let id): return id
            }
        }
        let many = feature.isMany || values.count > 1
        guard many else { return converted[0] }
        if let ids = converted as? [EUUID] { return ids }
        if let texts = converted as? [String] { return texts }
        if let numbers = converted as? [Int] { return numbers }
        if let numbers = converted as? [Double] { return numbers }
        if let flags = converted as? [Bool] { return flags }
        return EcoreValueArray(converted)
    }
}

extension DeepFeatureType {
    /// The name of the data type, if the feature is an attribute.
    var dataTypeName: String? {
        if case .data(let name) = self { return name }
        return nil
    }
}
