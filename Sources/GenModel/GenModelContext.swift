//
// GenModelContext.swift
// GenModel
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation

/// An immutable snapshot of a generator model and the Ecore elements it describes.
///
/// Objects of a loaded model live inside an asynchronous ``Resource`` and refer to
/// each other by identifier. A context copies the generator model objects and indexes
/// the native Ecore elements they refer to, so that all navigation and ordering
/// queries of ``GenElement`` can run synchronously, for example from template
/// services.
///
/// A context does not observe later changes. Take a new snapshot after modifying
/// the model.
///
/// ## Example
///
/// ```swift
/// let context = await GenModelContext.snapshot(of: resourceSet)
/// for genModel in context.genModels {
///     print(genModel.genPackages.count)
/// }
/// ```
public struct GenModelContext: Sendable {
    private let objects: [EUUID: DynamicEObject]
    private let orderedIDs: [EUUID]
    private let rootIDs: [EUUID]
    private let parents: [EUUID: EUUID]
    private let classes: [EUUID: EClass]
    private let features: [EUUID: any EStructuralFeature]
    private let operations: [EUUID: EOperation]
    private let parameters: [EUUID: EParameter]
    private let enums: [EUUID: EEnum]
    private let literals: [EUUID: EEnumLiteral]
    private let dataTypes: [EUUID: EDataType]
    private let packages: [EUUID: EPackage]
    private let genClassIDsByEcoreClass: [EUUID: EUUID]
    private let instanceTypeNames: [EUUID: String]

    /// Creates a context from generator model objects and native Ecore packages.
    ///
    /// Only objects whose class is one of the generator metamodel classes are kept.
    /// All classes, features, operations, parameters, enumerations, literals, data types
    /// and subpackages of the given Ecore packages become resolvable targets of `ecore*`
    /// references.
    ///
    /// - Parameters:
    ///   - objects: The generator model objects, in a stable order. Objects that are
    ///     not contained in another object are the roots of the context.
    ///   - ecorePackages: The native Ecore packages that the objects refer to.
    ///   - instanceTypeNames: The instance type names of Ecore classes by class
    ///     identifier, used to recognise map entry classes. Native classes do not
    ///     carry this information, so callers that know it may supply it here.
    public init(
        objects: [DynamicEObject],
        ecorePackages: [EPackage] = [],
        instanceTypeNames: [EUUID: String] = [:]
    ) {
        let generatorClassNames = Set(GenModelConstants.ClassName.all)
        let kept = objects.filter { generatorClassNames.contains($0.eClass.name) }
        var byID: [EUUID: DynamicEObject] = [:]
        for object in kept { byID[object.id] = object }

        var parents: [EUUID: EUUID] = [:]
        for object in kept {
            for featureName in GenModelConstants.FeatureName.containments {
                for childID in Self.identifiers(of: object, feature: featureName) {
                    parents[childID] = object.id
                }
            }
        }
        self.objects = byID
        self.parents = parents
        self.orderedIDs = kept.map(\.id)
        self.rootIDs = kept.map(\.id).filter { parents[$0] == nil }

        var classes: [EUUID: EClass] = [:]
        var features: [EUUID: any EStructuralFeature] = [:]
        var operations: [EUUID: EOperation] = [:]
        var parameters: [EUUID: EParameter] = [:]
        var enums: [EUUID: EEnum] = [:]
        var literals: [EUUID: EEnumLiteral] = [:]
        var dataTypes: [EUUID: EDataType] = [:]
        var packageIndex: [EUUID: EPackage] = [:]
        func index(_ package: EPackage) {
            packageIndex[package.id] = package
            for classifier in package.eClassifiers {
                switch classifier {
                case let eClass as EClass:
                    classes[eClass.id] = eClass
                    for feature in eClass.eStructuralFeatures { features[feature.id] = feature }
                    for operation in eClass.eOperations {
                        operations[operation.id] = operation
                        for parameter in operation.eParameters { parameters[parameter.id] = parameter }
                    }
                case let eEnum as EEnum:
                    enums[eEnum.id] = eEnum
                    for literal in eEnum.literals { literals[literal.id] = literal }
                case let dataType as EDataType:
                    dataTypes[dataType.id] = dataType
                default:
                    break
                }
            }
            for subpackage in package.eSubpackages { index(subpackage) }
        }
        for package in ecorePackages { index(package) }
        self.classes = classes
        self.features = features
        self.operations = operations
        self.parameters = parameters
        self.enums = enums
        self.literals = literals
        self.dataTypes = dataTypes
        self.packages = packageIndex
        self.instanceTypeNames = instanceTypeNames

        var genClassIDs: [EUUID: EUUID] = [:]
        for object in kept where object.eClass.name == GenModelConstants.ClassName.genClass {
            if let target = Self.identifiers(of: object, feature: GenModelConstants.FeatureName.ecoreClass).first {
                genClassIDs[target] = genClassIDs[target] ?? object.id
            }
        }
        self.genClassIDsByEcoreClass = genClassIDs
    }

    /// Takes a snapshot of every generator model held by a resource set.
    ///
    /// All resources of the set are scanned for generator model objects, and every
    /// registered metamodel becomes available as a target of `ecore*` references.
    ///
    /// - Parameters:
    ///   - resourceSet: The resource set to snapshot.
    ///   - instanceTypeNames: Optional instance type names by Ecore class identifier.
    /// - Returns: The new context.
    public static func snapshot(
        of resourceSet: ResourceSet,
        instanceTypeNames: [EUUID: String] = [:]
    ) async -> GenModelContext {
        let resources = await resourceSet.getResources()
        var packages: [EPackage] = []
        for uri in await resourceSet.getMetamodelURIs().sorted() {
            if let package = await resourceSet.getMetamodel(uri: uri) { packages.append(package) }
        }
        return await snapshot(
            of: resources, ecorePackages: packages, instanceTypeNames: instanceTypeNames)
    }

    /// Takes a snapshot of the generator model objects of some resources.
    ///
    /// - Parameters:
    ///   - resources: The resources to scan, in order. Root objects keep resource order.
    ///   - ecorePackages: The native Ecore packages that the objects refer to.
    ///   - instanceTypeNames: Optional instance type names by Ecore class identifier.
    /// - Returns: The new context.
    public static func snapshot(
        of resources: [Resource],
        ecorePackages: [EPackage],
        instanceTypeNames: [EUUID: String] = [:]
    ) async -> GenModelContext {
        var objects: [DynamicEObject] = []
        for resource in resources {
            let roots = await resource.getRootObjects()
            let all = await resource.getAllObjects()
            var seen = Set<EUUID>()
            for object in roots + all {
                if let dynamic = object as? DynamicEObject, seen.insert(dynamic.id).inserted {
                    objects.append(dynamic)
                }
            }
        }
        return GenModelContext(
            objects: objects, ecorePackages: ecorePackages, instanceTypeNames: instanceTypeNames)
    }

    // MARK: - Elements

    /// The generator models of this context, in resource order.
    public var genModels: [GenElement] {
        rootIDs.compactMap { id in
            element(id: id).flatMap { $0.isKind(of: GenModelConstants.ClassName.genModel) ? $0 : nil }
        }
    }

    /// Wraps an object of this context as an element.
    ///
    /// - Parameter id: The identifier of a generator model object.
    /// - Returns: The element, or `nil` if the context holds no such object.
    public func element(id: EUUID) -> GenElement? {
        objects[id].map { GenElement(object: $0, context: self) }
    }

    /// All elements of the context whose class is, or derives from, a metaclass.
    ///
    /// - Parameter className: The name of a generator metaclass.
    /// - Returns: The matching elements, in the order the objects were supplied.
    public func elements(ofKind className: String) -> [GenElement] {
        orderedIDs
            .compactMap { element(id: $0) }
            .filter { $0.isKind(of: className) }
    }

    // MARK: - Internal lookups

    func parentID(of id: EUUID) -> EUUID? { parents[id] }

    func ecoreClass(id: EUUID) -> EClass? { classes[id] }
    func ecoreFeature(id: EUUID) -> (any EStructuralFeature)? { features[id] }
    func ecoreOperation(id: EUUID) -> EOperation? { operations[id] }
    func ecoreParameter(id: EUUID) -> EParameter? { parameters[id] }
    func ecoreEnum(id: EUUID) -> EEnum? { enums[id] }
    func ecoreEnumLiteral(id: EUUID) -> EEnumLiteral? { literals[id] }
    func ecoreDataType(id: EUUID) -> EDataType? { dataTypes[id] }
    func ecorePackage(id: EUUID) -> EPackage? { packages[id] }
    func instanceTypeName(ofClass id: EUUID) -> String? { instanceTypeNames[id] }

    /// All transitive supertypes of a class, ancestors before descendants.
    ///
    /// For each direct supertype in declaration order, its own supertypes come first,
    /// followed by the supertype itself. Each class appears once.
    func allSuperTypes(of eClass: EClass) -> [EClass] {
        var result: [EClass] = []
        var seen: Set<EUUID> = [eClass.id]
        func visit(_ current: EClass) {
            for declared in current.eSuperTypes {
                let superType = classes[declared.id] ?? declared
                guard seen.insert(superType.id).inserted else { continue }
                visit(superType)
                result.append(superType)
            }
        }
        visit(classes[eClass.id] ?? eClass)
        return result
    }

    func genClass(forEcoreClass id: EUUID) -> GenElement? {
        genClassIDsByEcoreClass[id].flatMap { element(id: $0) }
    }

    /// Reads the identifiers held by a reference feature of an object.
    ///
    /// Single-valued and multi-valued storage are both accepted, as is storage
    /// of objects instead of identifiers. Unresolved textual references yield no
    /// identifiers.
    static func identifiers(of object: DynamicEObject, feature: String) -> [EUUID] {
        switch object.eGet(feature) {
        case let id as EUUID: return [id]
        case let ids as [EUUID]: return ids
        case let target as DynamicEObject: return [target.id]
        case let targets as [DynamicEObject]: return targets.map(\.id)
        default: return []
        }
    }
}
