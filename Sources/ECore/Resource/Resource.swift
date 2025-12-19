//
// Resource.swift
// ECore
//
//  Created by Rene Hexel on 3/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
public import EMFBase
import Foundation
import OrderedCollections

/// A resource manages model objects and provides EMF-compliant reference resolution.
///
/// Resources serve as containers for model objects, providing identity-based storage
/// and resolution capabilities. They enable cross-reference resolution, URI-based
/// addressing, and proper object lifecycle management following EMF patterns.
///
/// ## Thread Safety
///
/// Resources are thread-safe actors that manage concurrent access to model objects
/// and provide atomic reference resolution operations.
///
/// ## Example
///
/// ```swift
/// let resource = Resource(uri: "http://example.com/mymodel")
///
/// // Add objects to resource
/// let person = DynamicEObject(eClass: personClass)
/// resource.add(person)
///
/// // Resolve references by ID
/// if let resolved = resource.resolve(person.id) {
///     print("Found object: \(resolved)")
/// }
/// ```
@globalActor
public actor Resource {
    /// Global resource actor for thread-safe operations.
    public static let shared = Resource()

    /// The URI identifying this resource.
    ///
    /// Resources are identified by URIs following EMF conventions. The URI
    /// typically indicates the location or logical name of the resource.
    nonisolated public let uri: String

    /// Objects contained in this resource, indexed by their unique identifier.
    ///
    /// All objects within a resource must have unique identifiers. The resource
    /// maintains ownership and provides resolution services.
    /// Uses OrderedDictionary to preserve insertion order for EMF compliance.
    private var objects: OrderedDictionary<EUUID, any EObject>

    /// Root objects that are not contained by other objects in this resource.
    ///
    /// Root objects serve as entry points for model traversal and are typically
    /// the top-level objects that contain the entire model hierarchy.
    /// Maintains insertion order.
    private var rootObjects: [EUUID]

    /// The resource set that owns this resource, if any.
    ///
    /// Resources can be managed independently or as part of a resource set
    /// for cross-resource reference resolution.
    public weak var resourceSet: ResourceSet?

    /// Enable debug output.
    public var debug = false

    /// Initialises a new resource with the specified URI.
    ///
    /// - Parameter uri: The URI identifying this resource. Defaults to a generated URI.
    public init(uri: String = "resource://\(UUID().uuidString)", enableDebugging: Bool = false) {
        self.uri = uri
        objects = OrderedDictionary<EUUID, any EObject>()
        rootObjects = []
        debug = enableDebugging
    }

    /// Sets the resource set that owns this resource.
    ///
    /// - Parameter resourceSet: The resource set to associate with this resource.
    public func setResourceSet(_ resourceSet: ResourceSet?) {
        self.resourceSet = resourceSet
    }

    // MARK: - Object Management

    /// Registers an object with this resource without adding it as a root object.
    ///
    /// This method adds the object to the resource's object map for ID resolution,
    /// but does not add it to the root objects list. Use this for objects that will
    /// be contained by other objects (e.g., during XMI parsing when parent-child
    /// relationships will be established separately).
    ///
    /// - Parameter object: The object to register with this resource.
    /// - Returns: `true` if the object was registered, `false` if it already exists.
    @discardableResult
    public func register(_ object: any EObject) -> Bool {
        let isNew = objects[object.id] == nil
        objects[object.id] = object
        return isNew
    }

    /// Adds an object to this resource.
    ///
    /// The object becomes owned by this resource and can be resolved by its identifier.
    /// If the object is not contained by another object, it becomes a root object.
    ///
    /// - Parameter object: The object to add to this resource.
    /// - Returns: `true` if the object was added, `false` if it already exists.
    @discardableResult
    public func add(_ object: any EObject) -> Bool {
        let isNew = objects[object.id] == nil

        // Update or add the object
        objects[object.id] = object

        // Check if this should be a root object (not contained by another)
        // This check happens regardless of whether the object is new, because
        // objects might be registered first and then added as roots later
        let isContained = objects.values.contains { container in
            // Check if any object contains this one through containment references
            if let eClass = container.eClass as? EClass {
                return eClass.allReferences.contains { reference in
                    reference.containment
                        && doesObjectContain(container, objectId: object.id, through: reference)
                }
            }
            return false
        }

        if !isContained && !rootObjects.contains(object.id) {
            rootObjects.append(object.id)
        }

        return isNew
    }

    /// Removes an object from this resource.
    ///
    /// - Parameter object: The object to remove from this resource.
    /// - Returns: `true` if the object was removed, `false` if it wasn't found.
    @discardableResult
    public func remove(_ object: any EObject) -> Bool {
        return remove(id: object.id)
    }

    /// Removes an object from this resource by its identifier.
    ///
    /// - Parameter id: The identifier of the object to remove.
    /// - Returns: `true` if the object was removed, `false` if it wasn't found.
    @discardableResult
    public func remove(id: EUUID) -> Bool {
        guard objects.removeValue(forKey: id) != nil else { return false }
        rootObjects.removeAll { $0 == id }
        return true
    }

    /// Removes all objects from this resource.
    public func clear() {
        objects.removeAll()
        rootObjects.removeAll()
    }

    // MARK: - Object Resolution

    /// Resolves an object by its identifier.
    ///
    /// - Parameter id: The unique identifier of the object to resolve.
    /// - Returns: The resolved object, or `nil` if not found in this resource.
    public func resolve(_ id: EUUID) -> (any EObject)? {
        return objects[id]
    }

    /// Resolves an object by its identifier with a specific type.
    ///
    /// - Parameters:
    ///   - id: The unique identifier of the object to resolve.
    ///   - type: The expected type of the resolved object.
    /// - Returns: The resolved object cast to the specified type, or `nil` if not found or wrong type.
    public func resolve<T: EObject>(_ id: EUUID, as type: T.Type) -> T? {
        return objects[id] as? T
    }

    /// Gets all objects contained in this resource.
    /// Gets all objects in this resource in insertion order.
    ///
    /// Objects are returned in the order they were added to the resource,
    /// preserving EMF semantic ordering instead of arbitrary UUID-based sorting.
    ///
    /// - Returns: An array of all objects in insertion order.
    public func getAllObjects() -> [any EObject] {
        return Array(objects.values)
    }

    /// Gets all root objects in this resource.
    ///
    /// Root objects are those that are not contained by other objects
    /// within the same resource.
    ///
    /// - Returns: An array of root objects.
    public func getRootObjects() -> [any EObject] {
        return rootObjects.compactMap { objects[$0] }
    }

    /// Gets the number of objects in this resource.
    ///
    /// - Returns: The count of objects contained in this resource.
    public func count() -> Int {
        return objects.count
    }

    /// Checks if this resource contains an object with the specified identifier.
    ///
    /// - Parameter id: The identifier to check for.
    /// - Returns: `true` if an object with the identifier exists, `false` otherwise.
    public func contains(id: EUUID) -> Bool {
        return objects[id] != nil
    }

    // MARK: - Reference Resolution

    /// Resolves the opposite reference for a bidirectional reference.
    ///
    /// In EMF, bidirectional references maintain opposites automatically.
    /// This method resolves the opposite reference through ID-based lookup.
    ///
    /// - Parameter reference: The reference whose opposite should be resolved.
    /// - Returns: The opposite reference, or `nil` if not found.
    public func resolveOpposite(_ reference: EReference) -> EReference? {
        guard let oppositeId = reference.opposite else { return nil }

        // Search through all objects to find the reference with the matching ID
        for object in objects.values {
            if let eClass = object.eClass as? EClass {
                for feature in eClass.allReferences {
                    if feature.id == oppositeId {
                        return feature
                    }
                }
            }
        }

        // Check in resource set if this resource is part of one
        // Note: Cross-resource resolution requires async context in ResourceSet
        // Cross-resource resolution would need async context
        return nil
    }

    /// Resolves a reference to its target objects.
    ///
    /// For single-valued references, returns an array with one element.
    /// For multi-valued references, returns all referenced objects.
    ///
    /// - Parameters:
    ///   - reference: The reference to resolve.
    ///   - from: The object containing the reference.
    /// - Returns: An array of resolved target objects.
    public func resolveReference(_ reference: EReference, from object: any EObject) -> [any EObject]
    {
        guard let value = object.eGet(reference) else { return [] }

        if reference.isMany {
            // Multi-valued reference - extract IDs from array
            // Try casting to array of EUUIDs directly, or convert from Any array
            if let ids = value as? [EUUID] {
                return ids.compactMap { resolve($0) }
            } else if let anyArray = value as? [Any] {
                let ids = anyArray.compactMap { $0 as? EUUID }
                return ids.compactMap { resolve($0) }
            }
        } else {
            // Single-valued reference - direct ID
            if let id = value as? EUUID {
                return resolve(id).map { [$0] } ?? []
            }
        }

        return []
    }

    // MARK: - URI Resolution

    /// Resolves an object by its URI path within this resource.
    ///
    /// EMF uses URI paths to identify objects within resources, typically
    /// following XPath-like syntax for model navigation.
    ///
    /// - Parameter path: The URI path to resolve (e.g., "/@contents.0/@departments.1").
    /// - Returns: The resolved object, or `nil` if the path is invalid.
    public func resolveByPath(_ path: String) -> (any EObject)? {
        // Handle empty path or "/" - return first root
        if path.isEmpty || path == "/" {
            let roots = getRootObjects()
            return roots.first
        }

        // Strip leading slashes for UUID check
        let cleanPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        // Handle UUID-based lookup (fragment is just a UUID, possibly with leading slashes)
        if let uuid = UUID(uuidString: cleanPath) {
            return resolve(uuid as EUUID)
        }

        // Handle XPath-style paths
        if path.hasPrefix("/") {
            let components = path.dropFirst().split(separator: "/")

            // If path is just "/", return the first root object
            if components.isEmpty {
                let roots = getRootObjects()
                return roots.first
            }

            // Try to resolve as numeric index into roots
            if let index = Int(components[0]) {
                let roots = getRootObjects()
                guard index < roots.count else { return nil }

                var current: any EObject = roots[index]

                // Navigate through remaining components (feature/index pairs)
                var i = 1
                while i < components.count {
                    let component = String(components[i])

                    // Check if next component exists and is an index
                    if i + 1 < components.count, let featureIndex = Int(components[i + 1]) {
                        // This component is a feature name, next is an index
                        let featureName = component

                        // Cast to DynamicEObject to use string-based eGet
                        guard let dynObj = current as? DynamicEObject else { return nil }

                        // Get the feature value
                        if let featureValue = dynObj.eGet(featureName) as? [EUUID] {
                            guard featureIndex < featureValue.count else { return nil }
                            let nextId = featureValue[featureIndex]
                            guard let nextObj = resolve(nextId) else { return nil }
                            current = nextObj
                        } else {
                            return nil
                        }

                        // Skip both the feature name and index
                        i += 2
                    } else {
                        // Can't navigate further
                        return nil
                    }
                }

                return current
            }

            // Handle @contents.index syntax
            if components[0].hasPrefix("@contents.") {
                let indexStr = String(components[0].dropFirst("@contents.".count))
                guard let index = Int(indexStr) else { return nil }

                let roots = getRootObjects()
                guard index < roots.count else { return nil }

                return roots[index]
            }
        }

        return nil
    }

    // MARK: - Object Modification

    /// Modifies a feature value on an object managed by this resource.
    ///
    /// This method handles bidirectional reference updates automatically.
    /// When setting a reference with an opposite, the opposite side is also updated.
    /// Cross-resource opposite references are coordinated through the ResourceSet.
    ///
    /// - Parameters:
    ///   - objectId: The ID of the object to modify.
    ///   - featureName: The name of the feature to set.
    ///   - value: The new value for the feature.
    /// - Returns: `true` if the modification was successful, `false` otherwise.
    @discardableResult
    public func eSet(objectId: EUUID, feature featureName: String, value: (any EcoreValue)?) async
        -> Bool
    {
        guard var object = objects[objectId] as? DynamicEObject else { return false }
        let eClass = object.eClass

        // Check if feature is defined in the eClass
        guard let feature = eClass.getStructuralFeature(name: featureName) else {
            // Feature not defined - use dynamic storage (for XMI parsing without full metamodel)
            object.eSet(featureName, value: value)
            objects[objectId] = object
            return true
        }

        // Handle bidirectional references
        if let reference = feature as? EReference, let oppositeId = reference.opposite {
            // Handle multi-valued references (arrays of UUIDs)
            if reference.isMany {
                // Get old values to unset opposites
                if let oldValues = object.eGet(reference) as? [EUUID] {
                    for oldValueId in oldValues {
                        if var oldTarget = objects[oldValueId] as? DynamicEObject {
                            // Target is in same resource - update directly
                            let targetClass = oldTarget.eClass
                            if let oppositeRef = targetClass.allReferences.first(where: {
                                $0.id == oppositeId
                            }) {
                                if oppositeRef.isMany {
                                    // Remove from array
                                    if var oppositeArray = oldTarget.eGet(oppositeRef) as? [EUUID] {
                                        oppositeArray.removeAll { $0 == objectId }
                                        oldTarget.eSet(oppositeRef, oppositeArray)
                                    }
                                } else {
                                    // Unset single-valued opposite
                                    oldTarget.eSet(oppositeRef, nil)
                                }
                                objects[oldValueId] = oldTarget
                            }
                        } else if let resourceSet = resourceSet {
                            // Target is in different resource - use ResourceSet coordination
                            await resourceSet.updateOpposite(
                                targetId: oldValueId,
                                oppositeRefId: oppositeId,
                                sourceId: objectId,
                                add: false
                            )
                        }
                    }
                }

                // Set the new value
                object.eSet(feature, value)
                objects[objectId] = object

                // Set opposites for new values
                if let newValues = value as? [EUUID] {
                    for newValueId in newValues {
                        if var newTarget = objects[newValueId] as? DynamicEObject {
                            // Target is in same resource - update directly
                            let targetClass = newTarget.eClass
                            if let oppositeRef = targetClass.allReferences.first(where: {
                                $0.id == oppositeId
                            }) {
                                if oppositeRef.isMany {
                                    // Add to array
                                    var oppositeArray =
                                        (newTarget.eGet(oppositeRef) as? [EUUID]) ?? []
                                    if !oppositeArray.contains(objectId) {
                                        oppositeArray.append(objectId)
                                    }
                                    newTarget.eSet(oppositeRef, oppositeArray)
                                } else {
                                    // Set single-valued opposite
                                    newTarget.eSet(oppositeRef, objectId)
                                }
                                objects[newValueId] = newTarget
                            }
                        } else if let resourceSet = resourceSet {
                            // Target is in different resource - use ResourceSet coordination
                            await resourceSet.updateOpposite(
                                targetId: newValueId,
                                oppositeRefId: oppositeId,
                                sourceId: objectId,
                                add: true
                            )
                        }
                    }
                }
            } else {
                // Handle single-valued references
                // Get old value to unset opposite if needed
                if let oldValueId = object.eGet(reference) as? EUUID {
                    if var oldTarget = objects[oldValueId] as? DynamicEObject {
                        // Target is in same resource - update directly
                        let targetClass = oldTarget.eClass
                        if let oppositeRef = targetClass.allReferences.first(where: {
                            $0.id == oppositeId
                        }) {
                            if oppositeRef.isMany {
                                // Remove from array
                                if var oppositeArray = oldTarget.eGet(oppositeRef) as? [EUUID] {
                                    oppositeArray.removeAll { $0 == objectId }
                                    oldTarget.eSet(oppositeRef, oppositeArray)
                                }
                            } else {
                                // Unset single-valued opposite
                                oldTarget.eSet(oppositeRef, nil)
                            }
                            objects[oldValueId] = oldTarget
                        }
                    } else if let resourceSet = resourceSet {
                        // Target is in different resource - use ResourceSet coordination
                        await resourceSet.updateOpposite(
                            targetId: oldValueId,
                            oppositeRefId: oppositeId,
                            sourceId: objectId,
                            add: false
                        )
                    }
                }

                // Set the new value
                object.eSet(feature, value)
                objects[objectId] = object

                // Set the opposite if there's a new value
                if let newValueId = value as? EUUID {
                    if var newTarget = objects[newValueId] as? DynamicEObject {
                        // Target is in same resource - update directly
                        let targetClass = newTarget.eClass
                        if let oppositeRef = targetClass.allReferences.first(where: {
                            $0.id == oppositeId
                        }) {
                            if oppositeRef.isMany {
                                // Add to array
                                var oppositeArray = (newTarget.eGet(oppositeRef) as? [EUUID]) ?? []
                                if !oppositeArray.contains(objectId) {
                                    oppositeArray.append(objectId)
                                }
                                newTarget.eSet(oppositeRef, oppositeArray)
                            } else {
                                // Set single-valued opposite
                                newTarget.eSet(oppositeRef, objectId)
                            }
                            objects[newValueId] = newTarget
                        }
                    } else if let resourceSet = resourceSet {
                        // Target is in different resource - use ResourceSet coordination
                        await resourceSet.updateOpposite(
                            targetId: newValueId,
                            oppositeRefId: oppositeId,
                            sourceId: objectId,
                            add: true
                        )
                    }
                }
            }
        } else {
            // Non-bidirectional feature, just set it
            object.eSet(feature, value)
            objects[objectId] = object
        }

        // Handle containment: if this is a containment reference, remove targets from root objects
        if let reference = feature as? EReference, reference.containment {
            if reference.isMany {
                // Multi-valued containment - remove all targets from roots
                if let targetIds = value as? [EUUID] {
                    for targetId in targetIds {
                        rootObjects.removeAll { $0 == targetId }
                    }
                }
            } else {
                // Single-valued containment - remove target from roots
                if let targetId = value as? EUUID {
                    rootObjects.removeAll { $0 == targetId }
                }
            }
        }

        return true
    }

    /// Gets a feature value from an object managed by this resource.
    ///
    /// - Parameters:
    ///   - objectId: The ID of the object to query.
    ///   - featureName: The name of the feature to get.
    /// - Returns: The feature value, or `nil` if not found.
    public func eGet(objectId: EUUID, feature featureName: String) -> (any EcoreValue)? {
        guard let object = objects[objectId] as? DynamicEObject else { return nil }
        return object.eGet(featureName)
    }

    /// Get all feature names for an object
    ///
    /// Returns the names of all features (attributes and references) that have
    /// been set on the specified object.
    ///
    /// - Parameter objectId: The ID of the object to query
    /// - Returns: Array of feature names
    public func getFeatureNames(objectId: EUUID) -> [String] {
        guard let object = objects[objectId] as? DynamicEObject else { return [] }
        return object.getFeatureNames()
    }

    // MARK: - Private Helpers

    /// Checks if a container object contains a target object through a specific reference.
    ///
    /// - Parameters:
    ///   - container: The potential container object.
    ///   - objectId: The ID of the object to check for containment.
    ///   - reference: The containment reference to check.
    /// - Returns: `true` if the container contains the target object.
    private func doesObjectContain(
        _ container: any EObject, objectId: EUUID, through reference: EReference
    ) -> Bool {
        guard reference.containment else { return false }

        if let value = container.eGet(reference) {
            if reference.isMany {
                if let ids = value as? [EUUID] {
                    return ids.contains(objectId)
                } else if let anyArray = value as? [Any] {
                    let ids = anyArray.compactMap { $0 as? EUUID }
                    return ids.contains(objectId)
                }
            } else {
                if let id = value as? EUUID {
                    return id == objectId
                }
            }
        }

        return false
    }

    // MARK: - ATL Integration Methods

    /// Gets all instances of a specific EClass in this resource.
    ///
    /// This method is used by ATL virtual machine to find all elements
    /// that match a specific type for transformation rules.
    ///
    /// - Parameter eClass: The EClass to find instances of
    /// - Returns: Array of objects that are instances of the specified EClass
    public func getAllInstancesOf(_ eClass: EClass) -> [any EObject] {
        return objects.values.filter { object in
            if let objectClass = object.eClass as? EClass {
                return objectClass.name == eClass.name
                    || isSubclassOf(objectClass, superclass: eClass)
            }
            return false
        }
    }

    /// Gets an object by its ID, used for ATL lazy binding resolution.
    ///
    /// - Parameter id: The unique identifier of the object
    /// - Returns: The object if found, nil otherwise
    public func getObject(_ id: EUUID) -> (any EObject)? {
        return objects[id]
    }

    /// Checks if one EClass is a subclass of another.
    ///
    /// - Parameters:
    ///   - subclass: The potential subclass
    ///   - superclass: The potential superclass
    /// - Returns: True if subclass extends superclass
    private func isSubclassOf(_ subclass: EClass, superclass: EClass) -> Bool {
        // Check direct superclasses
        for superType in subclass.eSuperTypes {
            if superType.name == superclass.name {
                return true
            }
            // Recursive check for inheritance hierarchy
            if isSubclassOf(superType, superclass: superclass) {
                return true
            }
        }
        return false
    }

    // MARK: - EObject Type Resolution

    /// Resolves the concrete EClassifier type from a DynamicEObject.
    ///
    /// Dispatches to the appropriate concrete type initializer based on eClass.name.
    ///
    /// - Parameter object: The DynamicEObject to convert.
    /// - Returns: EClass, EEnum, or EDataType instance.
    /// - Throws: XMIError if the object type is unsupported or initialization fails.
    /// Resolve the concrete EClassifier type from a DynamicEObject.
    ///
    /// Dispatches to the appropriate factory method based on the object's metaclass name.
    /// This method handles UUID-based cross-reference resolution for complex types like
    /// EClass and EEnum, while using simple initialisation for basic types like EDataType.
    ///
    /// - Parameter object: The DynamicEObject to convert.
    /// - Returns: A concrete EClassifier instance (EClass, EEnum, or EDataType).
    /// - Throws: XMIError if the object type is unsupported or initialisation fails.
    public func resolvingType(_ object: any EObject) async throws -> any EClassifier {
        guard let dynamicObj = object as? DynamicEObject else {
            throw XMIError.invalidObjectType("\(type(of: object))")
        }

        let eClass = dynamicObj.eClass
        let typeName = eClass.name

        switch typeName {
        case EcoreClassifier.eClass.rawValue:
            return try await createEClass(from: object, shouldIgnoreUnresolvedFeatures: true)
        case EcoreClassifier.eEnum.rawValue:
            return try await createEEnum(from: object, shouldIgnoreUnresolvedLiterals: true)
        case EcoreClassifier.eDataType.rawValue:
            guard let result = EDataType(object: object) else {
                throw XMIError.missingRequiredAttribute(
                    ErrorMessage.missingNameAttribute.rawValue)
            }
            return result
        default:
            throw XMIError.unknownElement("Unsupported classifier type: \(typeName)")
        }
    }

    /// Resolve the concrete EStructuralFeature type from a DynamicEObject.
    ///
    /// Dispatches to the appropriate factory method based on the object's metaclass name.
    /// This method handles UUID-based cross-reference resolution for type references.
    ///
    /// - Parameter object: The DynamicEObject to convert.
    /// - Returns: A concrete EStructuralFeature instance (EAttribute or EReference).
    /// - Throws: XMIError if the object type is unsupported or initialisation fails.
    public func resolvingFeature(_ object: any EObject) async throws -> any EStructuralFeature {
        guard let dynamicObj = object as? DynamicEObject else {
            throw XMIError.invalidObjectType("\(type(of: object))")
        }

        let eClass = dynamicObj.eClass
        let typeName = eClass.name

        switch typeName {
        case "EAttribute":
            return try await createEAttribute(from: object)
        case "EReference":
            return try await createEReference(from: object)
        default:
            throw XMIError.unsupportedFeature("Unsupported feature type: \(typeName)")
        }
    }

    /// Resolve a data type reference for an EAttribute.
    ///
    /// Creates a simple EDataType based on the name attribute. Falls back to EString
    /// if the type cannot be determined from the object.
    ///
    /// - Parameter object: The DynamicEObject containing eType reference.
    /// - Returns: The resolved EDataType.
    public func resolvingDataType(_ object: any EObject) -> any EClassifier {
        guard let dynamicObj = object as? DynamicEObject,
            let typeName: String = dynamicObj.eGet("name") as? String
        else {
            return EDataType(name: "EString")
        }

        return EDataType(name: typeName)
    }

    /// Resolve a reference type for an EReference.
    ///
    /// Creates a placeholder EClass with just the name from the type object.
    ///
    /// - Note: In a full implementation, this would use two-pass conversion to
    ///         resolve to the actual EClass from the package.
    ///
    /// - Parameter object: The DynamicEObject containing eType reference.
    /// - Returns: The resolved EClass.
    public func resolvingReferenceType(_ object: any EObject) -> any EClassifier {
        guard let dynamicObj = object as? DynamicEObject,
            let className: String = dynamicObj.eGet("name") as? String
        else {
            return EClass(name: "EObject")
        }

        return EClass(name: className)
    }

    // MARK: - Factory Methods

    /// Create an EPackage from a DynamicEObject with full cross-reference resolution.
    ///
    /// This method constructs a complete EPackage hierarchy by resolving all classifiers
    /// and subpackages through UUID-based cross-references. It serves as the primary
    /// factory method for loading Ecore metamodels from parsed XMI resources.
    ///
    /// - Parameters:
    ///   - object: The DynamicEObject representing an EPackage.
    ///   - shouldIgnoreUnresolvedClassifiers: If `true`, continues processing when classifier resolution fails; if `false`, throws on resolution failure (default: `false`).
    /// - Returns: A fully constructed EPackage with all classifiers and subpackages resolved.
    /// - Throws: XMIError if the object is invalid, missing required attributes, or classifier resolution fails when not ignored.
    public func createEPackage(from object: any EObject, shouldIgnoreUnresolvedClassifiers: Bool = false) async throws -> EPackage {
        guard let dynamicObj = object as? DynamicEObject else {
            throw XMIError.invalidObjectType("Expected DynamicEObject, got \(type(of: object))")
        }
        guard let name: String = dynamicObj.eGet("name") as? String else {
            throw XMIError.missingRequiredAttribute("name")
        }

        let nsURI: String = dynamicObj.eGet("nsURI") as? String ?? "http://\(name.lowercased())"
        let nsPrefix: String = dynamicObj.eGet("nsPrefix") as? String ?? name.lowercased()

        // Debug output to trace nsURI handling (commented out - needs debug flag)
        if debug {
            print("[DEBUG] Resource.createEPackage: name='\(name)', retrieved nsURI='\(dynamicObj.eGet("nsURI") as? String ?? "nil")', final nsURI='\(nsURI)'")
        }
        // Extract classifiers using type resolver
        var eClassifiers: [any EClassifier] = []
        if let classifierIds: [EUUID] = dynamicObj.eGet("eClassifiers") as? [EUUID] {
            for classifierId in classifierIds {
                if let classifierObj = resolve(classifierId) {
                    do {
                        let classifier = try await resolvingType(classifierObj)
                        eClassifiers.append(classifier)
                    } catch {
                        if shouldIgnoreUnresolvedClassifiers {
                            // Continue processing other classifiers
                            continue
                        } else {
                            throw error
                        }
                    }
                }
            }
        }

        // Extract subpackages recursively
        var eSubpackages: [EPackage] = []
        if let subpackageIds: [EUUID] = dynamicObj.eGet("eSubpackages") as? [EUUID] {
            for subpackageId in subpackageIds {
                if let subpackageObj = resolve(subpackageId) {
                    if let subpackage = try? await createEPackage(
                        from: subpackageObj,
                        shouldIgnoreUnresolvedClassifiers: shouldIgnoreUnresolvedClassifiers
                    ) {
                        eSubpackages.append(subpackage)
                    }
                }
            }
        }

        // Create the package
        return EPackage(
            name: name,
            nsURI: nsURI,
            nsPrefix: nsPrefix,
            eClassifiers: eClassifiers,
            eSubpackages: eSubpackages
        )
    }

    /// Create an EClass from a DynamicEObject with full cross-reference resolution.
    ///
    /// This method constructs an EClass by resolving structural features through UUID-based
    /// cross-references. It provides a clean factory interface for creating metamodel classes
    /// without polluting the EClass type with resource dependencies.
    ///
    /// - Parameters:
    ///   - object: The DynamicEObject representing an EClass.
    ///   - shouldIgnoreUnresolvedFeatures: If `true`, continues processing when feature resolution fails; if `false`, throws on resolution failure (default: `false`).
    /// - Returns: A fully constructed EClass with all structural features resolved.
    /// - Throws: XMIError if the object is invalid, missing required attributes, or feature resolution fails when not ignored.
    public func createEClass(
        from object: any EObject,
        shouldIgnoreUnresolvedFeatures: Bool = false
    ) async throws -> EClass {
        guard let dynamicObj = object as? DynamicEObject else {
            throw XMIError.invalidObjectType("Expected DynamicEObject, got \(type(of: object))")
        }
        guard let name: String = dynamicObj.eGet("name") as? String else {
            throw XMIError.missingRequiredAttribute("name")
        }

        let isAbstract: Bool = {
            if let boolValue = dynamicObj.eGet("abstract") as? Bool {
                return boolValue
            } else if let stringValue = dynamicObj.eGet("abstract") as? String {
                return stringValue.lowercased() == "true"
            }
            return false
        }()
        let isInterface: Bool = {
            if let boolValue = dynamicObj.eGet("interface") as? Bool {
                return boolValue
            } else if let stringValue = dynamicObj.eGet("interface") as? String {
                return stringValue.lowercased() == "true"
            }
            return false
        }()

        // Extract structural features
        var eStructuralFeatures: [any EStructuralFeature] = []
        if let featureIds: [EUUID] = dynamicObj.eGet("eStructuralFeatures") as? [EUUID] {
            for featureId in featureIds {
                if let featureObj = resolve(featureId) {
                    do {
                        let feature = try await resolvingFeature(featureObj)
                        eStructuralFeatures.append(feature)
                    } catch {
                        if !shouldIgnoreUnresolvedFeatures {
                            throw error
                        }
                    }
                }
            }
        }

        // Note: eSuperTypes left empty (TODO: two-pass conversion for type resolution)
        return EClass(
            name: name,
            isAbstract: isAbstract,
            isInterface: isInterface,
            eSuperTypes: [],
            eStructuralFeatures: eStructuralFeatures
        )
    }

    /// Create an EEnum from a DynamicEObject with full cross-reference resolution.
    ///
    /// This method constructs an EEnum by resolving enum literals through UUID-based
    /// cross-references when necessary.
    ///
    /// - Parameters:
    ///   - object: The DynamicEObject representing an EEnum.
    ///   - shouldIgnoreUnresolvedLiterals: If `true`, continues processing when literal resolution fails; if `false`, throws on resolution failure (default: `false`).
    /// - Returns: A fully constructed EEnum with all literals resolved.
    /// - Throws: XMIError if the object is invalid or missing required attributes.
    public func createEEnum(
        from object: any EObject,
        shouldIgnoreUnresolvedLiterals: Bool = false
    ) async throws -> EEnum {
        guard let dynamicObj = object as? DynamicEObject else {
            throw XMIError.invalidObjectType("Expected DynamicEObject, got \(type(of: object))")
        }
        guard let name: String = dynamicObj.eGet("name") as? String else {
            throw XMIError.missingRequiredAttribute("name")
        }

        // Extract enum literals
        var literals: [EEnumLiteral] = []
        if let literalIds: [EUUID] = dynamicObj.eGet("eLiterals") as? [EUUID] {
            for literalId in literalIds {
                if let literalObj = resolve(literalId) {
                    if let literal = EEnumLiteral(object: literalObj) {
                        literals.append(literal)
                    } else if !shouldIgnoreUnresolvedLiterals {
                        throw XMIError.missingRequiredAttribute("Failed to initialise EEnumLiteral")
                    }
                }
            }
        }

        return EEnum(name: name, literals: literals)
    }

    /// Create an EAttribute from a DynamicEObject with full cross-reference resolution.
    ///
    /// This method constructs an EAttribute by resolving type references through UUID-based
    /// cross-references when necessary.
    ///
    /// - Parameter object: The DynamicEObject representing an EAttribute.
    /// - Returns: A fully constructed EAttribute with type resolved.
    /// - Throws: XMIError if the object is invalid or missing required attributes.
    public func createEAttribute(from object: any EObject) async throws -> EAttribute {
        guard let dynamicObj = object as? DynamicEObject else {
            throw XMIError.invalidObjectType("Expected DynamicEObject, got \(type(of: object))")
        }
        guard let name: String = dynamicObj.eGet("name") as? String else {
            throw XMIError.missingRequiredAttribute("name")
        }

        let lowerBound: Int = {
            if let intValue = dynamicObj.eGet("lowerBound") as? Int {
                return intValue
            } else if let stringValue = dynamicObj.eGet("lowerBound") as? String,
                let intValue = Int(stringValue)
            {
                return intValue
            }
            return 0
        }()
        let upperBound: Int = {
            if let intValue = dynamicObj.eGet("upperBound") as? Int {
                return intValue
            } else if let stringValue = dynamicObj.eGet("upperBound") as? String,
                let intValue = Int(stringValue)
            {
                return intValue
            }
            return 1
        }()
        let changeable: Bool = {
            if let boolValue = dynamicObj.eGet("changeable") as? Bool {
                return boolValue
            } else if let stringValue = dynamicObj.eGet("changeable") as? String {
                return stringValue.lowercased() == "true"
            }
            return true
        }()
        let volatile: Bool = {
            if let boolValue = dynamicObj.eGet("volatile") as? Bool {
                return boolValue
            } else if let stringValue = dynamicObj.eGet("volatile") as? String {
                return stringValue.lowercased() == "true"
            }
            return false
        }()
        let transient: Bool = {
            if let boolValue = dynamicObj.eGet("transient") as? Bool {
                return boolValue
            } else if let stringValue = dynamicObj.eGet("transient") as? String {
                return stringValue.lowercased() == "true"
            }
            return false
        }()
        let isID: Bool = {
            if let boolValue = dynamicObj.eGet("iD") as? Bool {
                return boolValue
            } else if let stringValue = dynamicObj.eGet("iD") as? String {
                return stringValue.lowercased() == "true"
            }
            return false
        }()
        let defaultValueLiteral: String? = dynamicObj.eGet("defaultValueLiteral") as? String

        // Resolve eType
        let eType: any EClassifier
        if let eTypeId: EUUID = dynamicObj.eGet("eType") as? EUUID {
            if let eTypeObj = resolve(eTypeId) {
                eType = EClassifierResolver.resolvingDataType(eTypeObj)
            } else {
                eType = EDataType(name: "EString")
            }
        } else if let eTypeObj: any EObject = dynamicObj.eGet("eType") as? any EObject {
            eType = EClassifierResolver.resolvingDataType(eTypeObj)
        } else {
            eType = EDataType(name: "EString")
        }

        return EAttribute(
            name: name,
            eType: eType,
            lowerBound: lowerBound,
            upperBound: upperBound,
            changeable: changeable,
            volatile: volatile,
            transient: transient,
            defaultValueLiteral: defaultValueLiteral,
            isID: isID
        )
    }

    /// Create an EReference from a DynamicEObject with full cross-reference resolution.
    ///
    /// This method constructs an EReference by resolving type references through UUID-based
    /// cross-references when necessary.
    ///
    /// - Parameter object: The DynamicEObject representing an EReference.
    /// - Returns: A fully constructed EReference with type resolved.
    /// - Throws: XMIError if the object is invalid or missing required attributes.
    public func createEReference(from object: any EObject) async throws -> EReference {
        guard let dynamicObj = object as? DynamicEObject else {
            throw XMIError.invalidObjectType("Expected DynamicEObject, got \(type(of: object))")
        }
        guard let name: String = dynamicObj.eGet("name") as? String else {
            throw XMIError.missingRequiredAttribute("name")
        }

        let lowerBound: Int = {
            if let intValue = dynamicObj.eGet("lowerBound") as? Int {
                return intValue
            } else if let stringValue = dynamicObj.eGet("lowerBound") as? String,
                let intValue = Int(stringValue)
            {
                return intValue
            }
            return 0
        }()
        let upperBound: Int = {
            if let intValue = dynamicObj.eGet("upperBound") as? Int {
                return intValue
            } else if let stringValue = dynamicObj.eGet("upperBound") as? String,
                let intValue = Int(stringValue)
            {
                return intValue
            }
            return 1
        }()
        let containment: Bool = {
            if let boolValue = dynamicObj.eGet("containment") as? Bool {
                return boolValue
            } else if let stringValue = dynamicObj.eGet("containment") as? String {
                return stringValue.lowercased() == "true"
            }
            return false
        }()
        let changeable: Bool = {
            if let boolValue = dynamicObj.eGet("changeable") as? Bool {
                return boolValue
            } else if let stringValue = dynamicObj.eGet("changeable") as? String {
                return stringValue.lowercased() == "true"
            }
            return true
        }()
        let volatile: Bool = {
            if let boolValue = dynamicObj.eGet("volatile") as? Bool {
                return boolValue
            } else if let stringValue = dynamicObj.eGet("volatile") as? String {
                return stringValue.lowercased() == "true"
            }
            return false
        }()
        let transient: Bool = {
            if let boolValue = dynamicObj.eGet("transient") as? Bool {
                return boolValue
            } else if let stringValue = dynamicObj.eGet("transient") as? String {
                return stringValue.lowercased() == "true"
            }
            return false
        }()
        let resolveProxies: Bool = {
            if let boolValue = dynamicObj.eGet("resolveProxies") as? Bool {
                return boolValue
            } else if let stringValue = dynamicObj.eGet("resolveProxies") as? String {
                return stringValue.lowercased() == "true"
            }
            return true
        }()

        // Resolve eType
        let eType: any EClassifier
        if let eTypeId: EUUID = dynamicObj.eGet("eType") as? EUUID {
            if let eTypeObj = resolve(eTypeId) {
                eType = EClassifierResolver.resolvingReferenceType(eTypeObj)
            } else {
                eType = EClass(name: "EObject")
            }
        } else if let eTypeObj: any EObject = dynamicObj.eGet("eType") as? any EObject {
            eType = EClassifierResolver.resolvingReferenceType(eTypeObj)
        } else {
            eType = EClass(name: "EObject")
        }

        // eOpposite resolution deferred (TODO: two-pass conversion)
        let opposite: EUUID? = nil

        return EReference(
            name: name,
            eType: eType,
            lowerBound: lowerBound,
            upperBound: upperBound,
            changeable: changeable,
            volatile: volatile,
            transient: transient,
            containment: containment,
            opposite: opposite,
            resolveProxies: resolveProxies
        )
    }
}

// MARK: - CustomStringConvertible

extension Resource: CustomStringConvertible {
    /// Returns a string representation of this resource.
    nonisolated public var description: String {
        return "Resource(uri: \(uri))"
    }
}

// MARK: - Equatable

extension Resource: Equatable {
    /// Compares two resources for equality based on their URI.
    ///
    /// - Parameters:
    ///   - lhs: The first resource to compare.
    ///   - rhs: The second resource to compare.
    /// - Returns: `true` if the resources have the same URI, `false` otherwise.
    nonisolated public static func == (lhs: Resource, rhs: Resource) -> Bool {
        return lhs.uri == rhs.uri
    }
}

// MARK: - Hashable

extension Resource: Hashable {
    /// Hashes the resource based on its URI.
    ///
    /// - Parameter hasher: The hasher to use for combining hash values.
    nonisolated public func hash(into hasher: inout Hasher) {
        hasher.combine(uri)
    }
}
