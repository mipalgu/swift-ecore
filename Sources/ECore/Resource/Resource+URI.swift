//
// Resource+URI.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase
import Foundation
import OrderedCollections

/// Errors raised when a resource is given a URI or saved as a document in a resource set.
public enum ResourceSetError: Error, Sendable, Equatable {
    /// Another resource of the resource set already has the URI.
    ///
    /// The associated value is the canonical form of the URI.
    case uriInUse(String)

    /// The resource does not belong to the resource set that was asked to save it as a
    /// document.
    ///
    /// The associated value is the URI of the resource.
    case notInResourceSet(String)
}

extension ResourceSetError: CustomStringConvertible, LocalizedError {
    /// A sentence that describes the error and names the URI involved.
    public var description: String {
        switch self {
        case .uriInUse(let uri):
            return "Cannot give a resource the URI \(uri): another resource of the resource set has it"
        case .notInResourceSet(let uri):
            return "Cannot save \(uri) as a new document: the resource belongs to another resource set"
        }
    }

    /// The ``description`` of the error.
    public var errorDescription: String? { description }
}

extension Resource {
    /// Gives this resource a new URI, as EMF's `Resource.setURI` does.
    ///
    /// The URI is canonicalised as ``ResourceSet/createResource(uri:)`` canonicalises the
    /// URIs of the resources it creates. In a resource set, the resource keeps its position
    /// among the resources of the set and is found under the new URI only, so that the
    /// previous URI is free for another resource. Its objects keep their identities and
    /// fragments.
    ///
    /// A ``ResourceProxy`` that refers to the resource under its previous URI, whether it is
    /// held by the resource itself or by another resource of its set, is changed to refer to
    /// it under the new URI. References to the objects of the resource are therefore written
    /// against the new URI when the resources of the set are next saved, relative or absolute
    /// as the options of the writer choose, and the references of the resource to other
    /// documents are written relative to the new URI. The packages of a metamodel resource
    /// record the new URI as the document they come from, and metamodels of the set that
    /// refer to them record it as the document of the classifiers they refer to.
    ///
    /// Giving a resource its own URI changes nothing. No document is read or written: use
    /// ``ModelIO/saveAs(_:to:format:xmiOptions:registry:diagnostics:)`` or
    /// ``ResourceSet/saveAs(_:to:options:)`` to save a resource as a document and give it
    /// the URI of that document.
    ///
    /// Resources are equal and hash by their URIs, so a resource that is held in a `Set` or
    /// as a dictionary key must be removed before its URI changes and inserted again after.
    ///
    /// - Parameter newURI: The URI that the resource is to have.
    /// - Throws: ``ResourceSetError/uriInUse(_:)`` if another resource of the resource set
    ///   already has the URI, in which case nothing changes.
    public func setURI(_ newURI: String) async throws {
        let uri = URIReference.canonicalise(newURI)
        if let resourceSet {
            try await resourceSet.moveResource(self, to: uri)
        } else {
            let previous = adoptURI(uri)
            guard previous != uri else { return }
            retargetReferences(from: previous, to: uri)
        }
    }

    /// Replaces the URI of this resource.
    ///
    /// - Parameter uri: The canonical URI that the resource is to have.
    /// - Returns: The URI that the resource had before.
    @discardableResult
    nonisolated func adoptURI(_ uri: String) -> String {
        uriStorage.withLock { current in
            let previous = current
            current = uri
            return previous
        }
    }

    /// Makes the references of this resource that name a document under one URI name it
    /// under another.
    ///
    /// The proxies held by the features of the objects of the resource change, whether a
    /// feature holds a single proxy or a list that contains proxies. So do the native
    /// packages among its root objects: the URI of the document that a package records as
    /// its origin, the proxies of the classifiers, types, opposites and references that it
    /// records, and the references of the annotations of the package and its elements.
    ///
    /// - Parameters:
    ///   - oldURI: The URI that the references name.
    ///   - newURI: The URI that they are to name instead.
    func retargetReferences(from oldURI: String, to newURI: String) {
        let retargeting = ProxyRetargeting(from: oldURI, to: newURI)
        for case var object as DynamicEObject in getAllObjects() {
            var changed = false
            for feature in object.getFeatureNames() {
                guard let value = retargeting.retargeted(object.eGet(feature)) else { continue }
                object.eSet(feature, value: value)
                changed = true
            }
            if changed { objects[object.id] = object }
        }
        for case var package as EPackage in getRootObjects() {
            var changed = retargeting.retargetAnnotations(in: &package)
            if let origin = package.origin.flatMap({ retargeting.retargeted($0) }) {
                package.origin = origin
                changed = true
            }
            if changed { registerNativePackage(package) }
        }
    }
}

extension ResourceSet {
    /// Gives a resource of this set a new URI.
    ///
    /// The resource takes the place of its previous URI among the resources of the set, and
    /// the proxies of every resource of the set that name the previous URI name the new one.
    ///
    /// - Parameters:
    ///   - resource: The resource to move.
    ///   - uri: The canonical URI that the resource is to have.
    /// - Throws: ``ResourceSetError/uriInUse(_:)`` if another resource of the set has the URI.
    func moveResource(_ resource: Resource, to uri: String) async throws {
        try checkURIAvailable(uri, for: resource)
        let previous = resource.uri
        guard previous != uri else { return }
        if resources[previous] === resource {
            var moved = OrderedDictionary<String, Resource>(minimumCapacity: resources.count)
            for (key, value) in resources {
                moved[key == previous ? uri : key] = value
            }
            resources = moved
        }
        resource.adoptURI(uri)
        var affected = Array(resources.values)
        if !affected.contains(where: { $0 === resource }) { affected.append(resource) }
        for member in affected {
            await member.retargetReferences(from: previous, to: uri)
        }
    }

    /// Checks that a resource can have a URI in this set.
    ///
    /// - Parameters:
    ///   - uri: The canonical URI.
    ///   - resource: The resource that is to have the URI.
    /// - Throws: ``ResourceSetError/uriInUse(_:)`` if another resource of the set has the URI.
    func checkURIAvailable(_ uri: String, for resource: Resource) throws {
        if let holder = resources[uri], holder !== resource {
            throw ResourceSetError.uriInUse(uri)
        }
    }
}

/// Changes the proxies that name a document under one URI to name it under another.
struct ProxyRetargeting: Sendable {
    /// The URI that the proxies name.
    let oldURI: String

    /// The URI that they are to name instead.
    let newURI: String

    /// Creates a retargeting.
    ///
    /// - Parameters:
    ///   - oldURI: The URI that the proxies name.
    ///   - newURI: The URI that they are to name instead.
    init(from oldURI: String, to newURI: String) {
        self.oldURI = oldURI
        self.newURI = newURI
    }

    /// A proxy that names the new URI instead of the old one.
    ///
    /// - Parameter proxy: The proxy.
    /// - Returns: The proxy with the new URI and its fragment and qualifier, or `nil` if it
    ///   does not name the old URI.
    func retargeted(_ proxy: ResourceProxy) -> ResourceProxy? {
        guard proxy.uri == oldURI else { return nil }
        return ResourceProxy(uri: newURI, fragment: proxy.fragment, qualifier: proxy.qualifier)
    }

    /// A feature value whose proxies name the new URI instead of the old one.
    ///
    /// - Parameter value: A single proxy, a list of proxies, a list of mixed values, or any
    ///   other value.
    /// - Returns: The value in the same form with its proxies changed, or `nil` if it holds
    ///   no proxy that names the old URI.
    func retargeted(_ value: (any EcoreValue)?) -> (any EcoreValue)? {
        switch value {
        case let proxy as ResourceProxy:
            return retargeted(proxy)
        case let proxies as [ResourceProxy]:
            return retargeted(proxies)
        case let array as EcoreValueArray:
            var changed = false
            let values = array.values.map { element -> any EcoreValue in
                guard let replaced = retargeted(element) else { return element }
                changed = true
                return replaced
            }
            return changed ? EcoreValueArray(values, kind: array.kind) : nil
        default:
            return nil
        }
    }

    /// Proxies that name the new URI instead of the old one.
    ///
    /// - Parameter proxies: The proxies.
    /// - Returns: All proxies, with those that named the old URI changed, or `nil` if none did.
    func retargeted(_ proxies: [ResourceProxy]) -> [ResourceProxy]? {
        var changed = false
        let values = proxies.map { proxy -> ResourceProxy in
            guard let replaced = retargeted(proxy) else { return proxy }
            changed = true
            return replaced
        }
        return changed ? values : nil
    }

    /// The origin of a package with the proxies that name the old URI changed to name the new
    /// one, and the new URI as the document of the package if it was loaded from the old one.
    ///
    /// - Parameter origin: The origin of a package.
    /// - Returns: The changed origin, or `nil` if nothing in it names the old URI.
    func retargeted(_ origin: EPackageOrigin) -> EPackageOrigin? {
        var result = origin
        var changed = false
        if result.documentURI == oldURI {
            result.documentURI = newURI
            changed = true
        }
        func retarget(_ proxies: inout [EUUID: ResourceProxy]) {
            for (key, proxy) in proxies {
                guard let replaced = retargeted(proxy) else { continue }
                proxies[key] = replaced
                changed = true
            }
        }
        retarget(&result.externalReferences)
        retarget(&result.unresolvedTypes)
        retarget(&result.externalOpposites)
        for (owner, features) in result.unresolvedReferences {
            for (feature, proxies) in features {
                guard let replaced = retargeted(proxies) else { continue }
                result.unresolvedReferences[owner]?[feature] = replaced
                changed = true
            }
        }
        return changed ? result : nil
    }

    /// Annotations whose references to elements of other documents name the new URI instead
    /// of the old one, as do those of the annotations that they carry.
    ///
    /// - Parameter annotations: The annotations.
    /// - Returns: All annotations, with those that referred to the old URI changed, or `nil`
    ///   if none did.
    func retargeted(_ annotations: [EAnnotation]) -> [EAnnotation]? {
        var changed = false
        let values = annotations.map { annotation -> EAnnotation in
            var annotation = annotation
            var references = annotation.references
            for index in references.indices {
                guard case .external(let proxy) = references[index], let replaced = retargeted(proxy) else { continue }
                references[index] = .external(replaced)
                changed = true
            }
            annotation.references = references
            if let nested = retargeted(annotation.eAnnotations) {
                annotation.eAnnotations = nested
                changed = true
            }
            return annotation
        }
        return changed ? values : nil
    }

    /// Changes the annotations of a model element.
    ///
    /// - Parameter element: The model element.
    /// - Returns: Whether an annotation of the element referred to the old URI.
    func retargetAnnotations<Element: EModelElement>(of element: inout Element) -> Bool {
        guard let annotations = retargeted(element.eAnnotations) else { return false }
        element.eAnnotations = annotations
        return true
    }

    /// Changes the annotations of a package, its classifiers and their members, and its
    /// subpackages.
    ///
    /// - Parameter package: The package.
    /// - Returns: Whether an annotation referred to the old URI.
    func retargetAnnotations(in package: inout EPackage) -> Bool {
        var changed = retargetAnnotations(of: &package)
        var classifiers = package.eClassifiers
        var classifiersChanged = false
        for index in classifiers.indices {
            switch classifiers[index] {
            case var eClass as EClass:
                guard retargetAnnotations(in: &eClass) else { continue }
                classifiers[index] = eClass
            case var eEnum as EEnum:
                var literals = eEnum.literals
                let literalsChanged = retargetAnnotations(inEach: &literals)
                let enumChanged = retargetAnnotations(of: &eEnum)
                guard literalsChanged || enumChanged else { continue }
                if literalsChanged { eEnum.literals = literals }
                classifiers[index] = eEnum
            case var dataType as EDataType:
                guard retargetAnnotations(of: &dataType) else { continue }
                classifiers[index] = dataType
            default:
                continue
            }
            classifiersChanged = true
        }
        if classifiersChanged {
            package.eClassifiers = classifiers
            changed = true
        }
        var subpackages = package.eSubpackages
        var subpackagesChanged = false
        for index in subpackages.indices where retargetAnnotations(in: &subpackages[index]) {
            subpackagesChanged = true
        }
        if subpackagesChanged {
            package.eSubpackages = subpackages
            changed = true
        }
        return changed
    }

    /// Changes the annotations of a class, its structural features, and its operations and
    /// their parameters.
    ///
    /// - Parameter eClass: The class.
    /// - Returns: Whether an annotation referred to the old URI.
    func retargetAnnotations(in eClass: inout EClass) -> Bool {
        var changed = retargetAnnotations(of: &eClass)
        var features = eClass.eStructuralFeatures
        var featuresChanged = false
        for index in features.indices {
            switch features[index] {
            case var attribute as EAttribute:
                guard retargetAnnotations(of: &attribute) else { continue }
                features[index] = attribute
            case var reference as EReference:
                guard retargetAnnotations(of: &reference) else { continue }
                features[index] = reference
            default:
                continue
            }
            featuresChanged = true
        }
        if featuresChanged {
            eClass.eStructuralFeatures = features
            changed = true
        }
        var operations = eClass.eOperations
        var operationsChanged = false
        for index in operations.indices {
            var parameters = operations[index].eParameters
            let parametersChanged = retargetAnnotations(inEach: &parameters)
            if parametersChanged { operations[index].eParameters = parameters }
            if retargetAnnotations(of: &operations[index]) || parametersChanged { operationsChanged = true }
        }
        if operationsChanged {
            eClass.eOperations = operations
            changed = true
        }
        return changed
    }

    /// Changes the annotations of each of a list of model elements.
    ///
    /// - Parameter elements: The model elements.
    /// - Returns: Whether an annotation of an element referred to the old URI.
    func retargetAnnotations<Element: EModelElement>(inEach elements: inout [Element]) -> Bool {
        var changed = false
        for index in elements.indices where retargetAnnotations(of: &elements[index]) {
            changed = true
        }
        return changed
    }
}
