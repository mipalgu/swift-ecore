//
// LinguisticEncoding.swift
// MultiLevel
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import ECore
public import EMFBase
public import Foundation

/// Errors raised when a deep model cannot be decoded.
public enum MultiLevelError: Error, Sendable, Equatable, CustomStringConvertible {
    /// A resource holds no `DeepModel` object of the linguistic metamodel.
    ///
    /// The associated value is the URI of the resource.
    case notALinguisticModel(String)

    /// A deep model selects a potency variant for which no scheme is available.
    ///
    /// The associated value is the identifier of the variant.
    case unknownPotencyVariant(String)

    /// An object of the linguistic metamodel holds an invalid value.
    ///
    /// The associated value describes the value.
    case invalidValue(String)

    /// MetaDepth text could not be read.
    ///
    /// The associated values are the messages of the errors.
    case unreadableText([String])

    /// A sentence that describes the error.
    public var description: String {
        switch self {
        case .notALinguisticModel(let uri): return "\(uri) holds no multi-level model"
        case .unknownPotencyVariant(let variant): return "Unknown potency variant '\(variant)'"
        case .invalidValue(let value): return "Invalid value in a multi-level model: \(value)"
        case .unreadableText(let messages): return "Cannot read MetaDepth text: " + messages.joined(separator: "; ")
        }
    }
}

/// Encodes deep models as instances of the linguistic metamodel and decodes them again.
///
/// The encoding is lossless: decoding the encoding of a model yields an equal model,
/// including clabject identifiers, declared and default potencies, and the order of every
/// list. As the encoding is an ordinary resource, it is written and read as XMI or JSON by
/// ``ECore/ModelIO``; ``xmi(of:options:)``, ``json(of:)`` and ``model(from:uri:schemes:)`` do
/// so directly.
///
/// ```swift
/// let xmi = try await LinguisticEncoding.xmi(of: model)
/// let decoded = try await LinguisticEncoding.model(from: Data(xmi.utf8), uri: "model.xmi")
/// ```
public enum LinguisticEncoding {
    /// The value kinds of encoded values.
    enum ValueKind: String {
        /// The kinds of value, named by the `valueKind` feature of an encoded value.
        case string, integer, real, boolean, literal, object
    }

    /// The prefix of the URIs of encodings without a document location.
    static let resourceScheme = "multilevel:"

    // MARK: - Encoding

    /// Encodes a deep model as a resource of linguistic instances.
    ///
    /// The linguistic metamodel is registered with the resource set, so that serialisers
    /// write the namespace of the package. The resource set must be kept while the resource
    /// is written.
    ///
    /// - Parameters:
    ///   - model: The model.
    ///   - resourceSet: The resource set that receives the resource.
    ///   - uri: The URI of the resource (default derived from the name of the model).
    /// - Returns: The resource, whose single root is the `DeepModel` object.
    public static func resource(for model: DeepModel, in resourceSet: ResourceSet, uri: String? = nil) async -> Resource {
        var encoder = Encoder(model: model)
        encoder.encode()
        await resourceSet.registerMetamodel(MultiLevelPackage.package)
        let resource = await resourceSet.createResource(uri: uri ?? resourceScheme + model.name)
        await resource.add(contentsOf: encoder.objects)
        return resource
    }

    /// Writes a deep model as XMI.
    ///
    /// - Parameters:
    ///   - model: The model.
    ///   - options: The XMI options (default legacy options).
    /// - Returns: The XMI document.
    /// - Throws: The error of the serialiser.
    public static func xmi(of model: DeepModel, options: XMISerializationOptions = .legacy) async throws -> String {
        let resourceSet = ResourceSet()
        let resource = await resource(for: model, in: resourceSet)
        var diagnostics = ConversionDiagnostics()
        return try await XMISerializer(options: options).serialize(resource, diagnostics: &diagnostics)
    }

    /// Writes a deep model as JSON.
    ///
    /// - Parameter model: The model.
    /// - Returns: The JSON document.
    /// - Throws: The error of the serialiser.
    public static func json(of model: DeepModel) async throws -> String {
        let resourceSet = ResourceSet()
        let resource = await resource(for: model, in: resourceSet)
        return try await JSONSerializer().serialize(resource)
    }

    /// A resource set in which the linguistic metamodel is registered.
    ///
    /// - Returns: A new resource set.
    public static func resourceSet() async -> ResourceSet {
        let resourceSet = ResourceSet()
        await resourceSet.registerMetamodel(MultiLevelPackage.package)
        return resourceSet
    }

    /// Reads a deep model from an XMI or JSON document of linguistic instances.
    ///
    /// - Parameters:
    ///   - data: The document.
    ///   - uri: The URI of the document.
    ///   - schemes: The potency schemes that the model may select (default the built-in ones).
    /// - Returns: The model.
    /// - Throws: The error of the parser, or a ``MultiLevelError``.
    public static func model(
        from data: Data, uri: String, schemes: [any PotencyScheme] = PotencySchemes.builtIn
    ) async throws -> DeepModel {
        let loaded = try await ModelIO.load(data: data, uri: uri, resourceSet: await resourceSet())
        return try await model(from: loaded.resource, schemes: schemes)
    }

    // MARK: - Decoding

    /// Decodes a deep model from a resource of linguistic instances.
    ///
    /// - Parameters:
    ///   - resource: The resource, whose first `DeepModel` root is decoded.
    ///   - schemes: The potency schemes that the model may select (default the built-in ones).
    /// - Returns: The model.
    /// - Throws: A ``MultiLevelError`` if the resource holds no deep model or invalid values.
    public static func model(
        from resource: Resource, schemes: [any PotencyScheme] = PotencySchemes.builtIn
    ) async throws -> DeepModel {
        var objects: [EUUID: DynamicEObject] = [:]
        for object in await resource.getAllObjects() {
            if let dynamic = object as? DynamicEObject { objects[dynamic.id] = dynamic }
        }
        guard
            let root = await resource.getRootObjects().compactMap({ $0 as? DynamicEObject })
                .first(where: { $0.eClass.name == LinguisticClass.deepModel.rawValue })
        else { throw MultiLevelError.notALinguisticModel(resource.uri) }
        var decoder = Decoder(objects: objects)
        return try decoder.decode(root, schemes: schemes)
    }

    // MARK: - Encoder

    /// Builds the linguistic objects of a model, parents before children.
    struct Encoder {
        /// The model being encoded.
        let model: DeepModel
        /// The index of the model.
        let index: DeepIndex
        /// The linguistic objects created so far, parents before children.
        var objects: [DynamicEObject] = []

        /// Creates an encoder.
        ///
        /// - Parameter model: The model to encode.
        init(model: DeepModel) {
            self.model = model
            self.index = DeepIndex(model)
        }

        /// A deterministic identifier derived from the linguistic namespace.
        ///
        /// - Parameter components: The components that distinguish the identifier.
        /// - Returns: The identifier.
        static func id(_ components: String...) -> EUUID {
            MultiLevelIdentifiers.identifier(for: [MultiLevelSyntax.linguisticNamespaceURI] + components)
        }

        /// The identifier of the linguistic object of a clabject.
        ///
        /// - Parameter id: The identifier of the clabject.
        /// - Returns: The identifier of the object that encodes it.
        static func clabjectObject(_ id: EUUID) -> EUUID { Self.id("clabject", id.uuidString) }

        /// The identifier of the linguistic object of a feature.
        ///
        /// - Parameter reference: The reference to the feature.
        /// - Returns: The identifier of the object that encodes it.
        static func featureObject(_ reference: FeatureReference) -> EUUID {
            Self.id("feature", reference.clabject.uuidString, reference.name)
        }

        /// Encodes the model, its level models and everything they contain.
        mutating func encode() {
            var root = DynamicEObject(id: Self.id("model", model.name), eClass: MultiLevelPackage.eClass(.deepModel))
            set(&root, .name, model.name)
            set(&root, .potencyVariant, model.potencyVariant.rawValue)
            set(&root, .levelCrossing, model.levelCrossing.rawValue)
            let levelIDs = model.levels.indices.map { Self.id("level", model.name, String($0)) }
            root.eSet(LinguisticFeature.levels.rawValue, value: levelIDs)
            objects.append(root)
            for (position, level) in model.levels.enumerated() { encode(level, id: levelIDs[position]) }
        }

        /// Sets a feature of an object, leaving it unset if there is no value.
        ///
        /// - Parameters:
        ///   - object: The object to change.
        ///   - feature: The linguistic feature to set.
        ///   - value: The value, or `nil` to leave the feature unset.
        func set(_ object: inout DynamicEObject, _ feature: LinguisticFeature, _ value: (any EcoreValue)?) {
            guard let value else { return }
            object.eSet(feature.rawValue, value: value)
        }

        /// Encodes a level model and its clabjects and constraints.
        ///
        /// - Parameters:
        ///   - level: The level model.
        ///   - id: The identifier for the level model's object.
        mutating func encode(_ level: LevelModel, id: EUUID) {
            var object = DynamicEObject(id: id, eClass: MultiLevelPackage.eClass(.levelModel))
            set(&object, .name, level.name)
            set(&object, .potency, level.potency?.description)
            set(&object, .typeModel, level.typeModel)
            set(&object, .extensible, level.isExtensible)
            object.eSet(LinguisticFeature.clabjects.rawValue, value: level.clabjects.map { Self.clabjectObject($0.id) })
            let constraintIDs = level.constraints.indices.map { Self.id("constraint", id.uuidString, String($0)) }
            object.eSet(LinguisticFeature.constraints.rawValue, value: constraintIDs)
            objects.append(object)
            for clabject in level.clabjects { encode(clabject) }
            for (position, constraint) in level.constraints.enumerated() { encode(constraint, id: constraintIDs[position]) }
        }

        /// Encodes a clabject with its ends, features, slots and constraints.
        ///
        /// - Parameter clabject: The clabject.
        mutating func encode(_ clabject: Clabject) {
            let id = Self.clabjectObject(clabject.id)
            var object = DynamicEObject(id: id, eClass: MultiLevelPackage.eClass(.clabject))
            set(&object, .name, clabject.name)
            set(&object, .identifier, clabject.id.uuidString)
            set(&object, .kind, clabject.isEdge ? MultiLevelSyntax.edgeKeyword : MultiLevelSyntax.nodeKeyword)
            set(&object, .potency, clabject.potency?.description)
            set(&object, .leap, clabject.isLeap)
            set(&object, .isAbstract, clabject.isAbstract)
            set(&object, .type, clabject.type.map(Self.clabjectObject))
            object.eSet(LinguisticFeature.supertypes.rawValue, value: clabject.supertypes.map(Self.clabjectObject))
            let sourceID = Self.id("end", id.uuidString, LinguisticFeature.source.rawValue)
            let targetID = Self.id("end", id.uuidString, LinguisticFeature.target.rawValue)
            if clabject.ends != nil {
                set(&object, .source, sourceID)
                set(&object, .target, targetID)
            }
            let featureIDs = clabject.features.map { Self.featureObject(FeatureReference(clabject: clabject.id, name: $0.name)) }
            object.eSet(LinguisticFeature.features.rawValue, value: featureIDs)
            let slotIDs = clabject.slots.indices.map { Self.id("slot", id.uuidString, String($0)) }
            object.eSet(LinguisticFeature.slots.rawValue, value: slotIDs)
            let constraintIDs = clabject.constraints.indices.map { Self.id("constraint", id.uuidString, String($0)) }
            object.eSet(LinguisticFeature.constraints.rawValue, value: constraintIDs)
            objects.append(object)
            if let ends = clabject.ends {
                encode(ends.source, id: sourceID)
                encode(ends.target, id: targetID)
            }
            for (position, feature) in clabject.features.enumerated() { encode(feature, id: featureIDs[position]) }
            for (position, slot) in clabject.slots.enumerated() { encode(slot, id: slotIDs[position]) }
            for (position, constraint) in clabject.constraints.enumerated() {
                encode(constraint, id: constraintIDs[position])
            }
        }

        /// Encodes an edge end.
        ///
        /// - Parameters:
        ///   - end: The edge end.
        ///   - id: The identifier for the end's object.
        mutating func encode(_ end: EdgeEnd, id: EUUID) {
            var object = DynamicEObject(id: id, eClass: MultiLevelPackage.eClass(.edgeEnd))
            set(&object, .clabject, Self.clabjectObject(end.clabject))
            set(&object, .feature, end.feature)
            objects.append(object)
        }

        /// Encodes a feature and its default values.
        ///
        /// - Parameters:
        ///   - feature: The feature.
        ///   - id: The identifier for the feature's object.
        mutating func encode(_ feature: DeepFeature, id: EUUID) {
            var object = DynamicEObject(id: id, eClass: MultiLevelPackage.eClass(.feature))
            set(&object, .name, feature.name)
            set(&object, .potency, feature.potency?.description)
            set(&object, .mutability, feature.mutability?.description)
            switch feature.type {
            case .data(let dataType): set(&object, .dataType, dataType)
            case .reference(let target): set(&object, .targetClabject, Self.clabjectObject(target))
            }
            set(&object, .targetPotency, feature.targetPotency?.description)
            set(&object, .targetLevel, feature.targetLevel.map(String.init))
            set(&object, .lowerBound, feature.lowerBound)
            set(&object, .upperBound, feature.upperBound)
            set(&object, .containment, feature.isContainment)
            set(&object, .ordered, feature.isOrdered)
            set(&object, .unique, feature.isUnique)
            set(&object, .derived, feature.isDerived)
            set(&object, .derivation, feature.derivation)
            set(&object, .type, feature.ontologicalType.map(Self.featureObject))
            let valueIDs = feature.defaultValues.indices.map { Self.id("value", id.uuidString, String($0)) }
            object.eSet(LinguisticFeature.defaults.rawValue, value: valueIDs)
            objects.append(object)
            for (position, value) in feature.defaultValues.enumerated() { encode(value, id: valueIDs[position]) }
        }

        /// Encodes a slot and its values.
        ///
        /// - Parameters:
        ///   - slot: The slot.
        ///   - id: The identifier for the slot's object.
        mutating func encode(_ slot: DeepSlot, id: EUUID) {
            var object = DynamicEObject(id: id, eClass: MultiLevelPackage.eClass(.slot))
            set(&object, .feature, slot.feature)
            let valueIDs = slot.values.indices.map { Self.id("value", id.uuidString, String($0)) }
            object.eSet(LinguisticFeature.values.rawValue, value: valueIDs)
            objects.append(object)
            for (position, value) in slot.values.enumerated() { encode(value, id: valueIDs[position]) }
        }

        /// Encodes a value as its kind and its literal text or referenced clabject.
        ///
        /// - Parameters:
        ///   - value: The value.
        ///   - id: The identifier for the value's object.
        mutating func encode(_ value: DeepValue, id: EUUID) {
            var object = DynamicEObject(id: id, eClass: MultiLevelPackage.eClass(.value))
            let (kind, literal): (ValueKind, String?) =
                switch value {
                case .string(let text): (.string, text)
                case .integer(let number): (.integer, String(number))
                case .real(let number): (.real, String(number))
                case .boolean(let flag): (.boolean, String(flag))
                case .literal(let name): (.literal, name)
                case .object: (.object, nil)
                }
            set(&object, .valueKind, kind.rawValue)
            set(&object, .literal, literal)
            set(&object, .object, value.object.map(Self.clabjectObject))
            objects.append(object)
        }

        /// Encodes a constraint.
        ///
        /// - Parameters:
        ///   - constraint: The constraint.
        ///   - id: The identifier for the constraint's object.
        mutating func encode(_ constraint: DeepConstraint, id: EUUID) {
            var object = DynamicEObject(id: id, eClass: MultiLevelPackage.eClass(.constraint))
            set(&object, .name, constraint.name)
            set(&object, .potency, constraint.potency?.description)
            set(&object, .body, constraint.body)
            set(&object, .language, constraint.language)
            objects.append(object)
        }
    }

    // MARK: - Decoder

    /// Rebuilds a model from linguistic objects.
    struct Decoder {
        /// The linguistic objects to decode, by identifier.
        let objects: [EUUID: DynamicEObject]

        /// The clabject identifiers of the clabject objects.
        var clabjectIDs: [EUUID: EUUID] = [:]

        /// The clabject identifiers of the owners of the feature objects.
        var featureOwners: [EUUID: EUUID] = [:]

        /// Creates a decoder.
        ///
        /// - Parameter objects: The linguistic objects of an encoding, by identifier.
        init(objects: [EUUID: DynamicEObject]) {
            self.objects = objects
        }

        /// The identifiers that a reference value denotes.
        static func ids(_ value: (any EcoreValue)?) -> [EUUID] {
            switch value {
            case nil: return []
            case let id as EUUID: return [id]
            case let object as any EObject: return [object.id]
            case let ids as [EUUID]: return ids
            case let array as EcoreValueArray: return array.values.flatMap { ids($0) }
            case let objects as [any EcoreValue]: return objects.flatMap { ids($0) }
            default: return []
            }
        }

        /// The objects that a feature of an object refers to.
        ///
        /// - Parameters:
        ///   - object: The owning object.
        ///   - feature: The linguistic feature that holds the references.
        /// - Returns: The referenced objects that are present, in order.
        func children(_ object: DynamicEObject, _ feature: LinguisticFeature) -> [DynamicEObject] {
            Self.ids(object.eGet(feature.rawValue)).compactMap { objects[$0] }
        }

        /// The string value of a feature.
        ///
        /// - Parameters:
        ///   - object: The owning object.
        ///   - feature: The linguistic feature.
        /// - Returns: The string, or `nil` if the feature is unset or not a string.
        func string(_ object: DynamicEObject, _ feature: LinguisticFeature) -> String? {
            object.eGet(feature.rawValue) as? String
        }

        /// The Boolean value of a feature.
        ///
        /// - Parameters:
        ///   - object: The owning object.
        ///   - feature: The linguistic feature.
        /// - Returns: The value, or `false` if the feature is unset.
        func boolean(_ object: DynamicEObject, _ feature: LinguisticFeature) -> Bool {
            object.eGet(feature.rawValue) as? Bool ?? false
        }

        /// The integer value of a feature.
        ///
        /// - Parameters:
        ///   - object: The owning object.
        ///   - feature: The linguistic feature.
        /// - Returns: The value, or `0` if the feature is unset or not a number.
        func integer(_ object: DynamicEObject, _ feature: LinguisticFeature) -> Int {
            switch object.eGet(feature.rawValue) {
            case let value as Int: return value
            case let value as Int64: return Int(value)
            case let value as String: return Int(value) ?? 0
            default: return 0
            }
        }

        /// The potency stored in a feature as text.
        ///
        /// - Parameters:
        ///   - object: The owning object.
        ///   - feature: The linguistic feature.
        /// - Returns: The potency, or `nil` if the feature is unset.
        /// - Throws: ``MultiLevelError/invalidValue(_:)`` if the text is not a potency.
        func potency(_ object: DynamicEObject, _ feature: LinguisticFeature) throws -> Potency? {
            guard let text = string(object, feature) else { return nil }
            guard let potency = Potency(text: text) else { throw MultiLevelError.invalidValue("potency '\(text)'") }
            return potency
        }

        /// The identifier of the clabject that a feature refers to.
        ///
        /// - Parameters:
        ///   - object: The owning object.
        ///   - feature: The linguistic feature that holds the reference.
        /// - Returns: The clabject identifier, or `nil` if there is no such reference.
        func clabjectID(_ object: DynamicEObject, _ feature: LinguisticFeature) -> EUUID? {
            Self.ids(object.eGet(feature.rawValue)).first.flatMap { clabjectIDs[$0] }
        }

        /// Rebuilds the deep model from its root object.
        ///
        /// - Parameters:
        ///   - root: The object that encodes the model.
        ///   - schemes: The potency schemes that the model's variant can select.
        /// - Returns: The decoded model.
        /// - Throws: ``MultiLevelError/unknownPotencyVariant(_:)`` if no scheme matches, or ``MultiLevelError/invalidValue(_:)`` if the encoding is malformed.
        mutating func decode(_ root: DynamicEObject, schemes: [any PotencyScheme]) throws -> DeepModel {
            let variant = PotencyVariant(rawValue: string(root, .potencyVariant) ?? PotencyVariant.metaDepth.rawValue)
            guard let scheme = PotencySchemes.scheme(for: variant, among: schemes) else {
                throw MultiLevelError.unknownPotencyVariant(variant.rawValue)
            }
            let levelObjects = children(root, .levels)
            for level in levelObjects {
                for clabject in children(level, .clabjects) {
                    guard let text = string(clabject, .identifier), let id = EUUID(uuidString: text) else {
                        throw MultiLevelError.invalidValue("clabject identifier")
                    }
                    clabjectIDs[clabject.id] = id
                    for feature in children(clabject, .features) { featureOwners[feature.id] = id }
                }
            }
            var model = DeepModel(
                potencyScheme: scheme,
                levelCrossing: LevelCrossingPolicy(rawValue: string(root, .levelCrossing) ?? LevelCrossingPolicy.strict.rawValue))
            model.levels = try levelObjects.map { level in
                LevelModel(
                    name: string(level, .name) ?? "", potency: try potency(level, .potency),
                    typeModel: string(level, .typeModel), isExtensible: boolean(level, .extensible),
                    clabjects: try children(level, .clabjects).map(decodeClabject),
                    constraints: try children(level, .constraints).map(decodeConstraint))
            }
            return model
        }

        /// Rebuilds a clabject, with its ends, features, slots and constraints.
        ///
        /// - Parameter object: The object that encodes the clabject.
        /// - Returns: The clabject.
        /// - Throws: ``MultiLevelError/invalidValue(_:)`` if the encoding is malformed.
        func decodeClabject(_ object: DynamicEObject) throws -> Clabject {
            guard let id = clabjectIDs[object.id] else { throw MultiLevelError.invalidValue("clabject identifier") }
            var ends: EdgeEnds?
            if let source = children(object, .source).first, let target = children(object, .target).first {
                ends = EdgeEnds(source: try decodeEnd(source), target: try decodeEnd(target))
            }
            return Clabject(
                id: id, name: string(object, .name) ?? "", type: clabjectID(object, .type),
                potency: try potency(object, .potency), isLeap: boolean(object, .leap),
                isAbstract: boolean(object, .isAbstract),
                supertypes: Self.ids(object.eGet(LinguisticFeature.supertypes.rawValue)).compactMap { clabjectIDs[$0] },
                ends: ends, features: try children(object, .features).map { try decodeFeature($0, owner: id) },
                slots: try children(object, .slots).map(decodeSlot),
                constraints: try children(object, .constraints).map(decodeConstraint))
        }

        /// Rebuilds an edge end.
        ///
        /// - Parameter object: The object that encodes the end.
        /// - Returns: The edge end.
        /// - Throws: ``MultiLevelError/invalidValue(_:)`` if the end names no clabject.
        func decodeEnd(_ object: DynamicEObject) throws -> EdgeEnd {
            guard let clabject = clabjectID(object, .clabject) else { throw MultiLevelError.invalidValue("edge end") }
            return EdgeEnd(clabject: clabject, feature: string(object, .feature))
        }

        /// Rebuilds a feature.
        ///
        /// - Parameters:
        ///   - object: The object that encodes the feature.
        ///   - owner: The identifier of the clabject that owns the feature.
        /// - Returns: The feature.
        /// - Throws: ``MultiLevelError/invalidValue(_:)`` if the encoding is malformed.
        func decodeFeature(_ object: DynamicEObject, owner: EUUID) throws -> DeepFeature {
            let type: DeepFeatureType
            if let target = clabjectID(object, .targetClabject) {
                type = .reference(target)
            } else {
                type = .data(string(object, .dataType) ?? "")
            }
            var ontologicalType: FeatureReference?
            if let typeObject = Self.ids(object.eGet(LinguisticFeature.type.rawValue)).first.flatMap({ objects[$0] }),
                let typeOwnerID = featureOwners[typeObject.id], let name = string(typeObject, .name)
            {
                ontologicalType = FeatureReference(clabject: typeOwnerID, name: name)
            }
            var targetLevel: Int?
            if let text = string(object, .targetLevel) {
                guard let level = Int(text) else { throw MultiLevelError.invalidValue("target level '\(text)'") }
                targetLevel = level
            }
            return DeepFeature(
                name: string(object, .name) ?? "", type: type, potency: try potency(object, .potency),
                mutability: try potency(object, .mutability), lowerBound: integer(object, .lowerBound),
                upperBound: integer(object, .upperBound), isContainment: boolean(object, .containment),
                isOrdered: boolean(object, .ordered), isUnique: boolean(object, .unique),
                isDerived: boolean(object, .derived), derivation: string(object, .derivation),
                defaultValues: try children(object, .defaults).map(decodeValue), ontologicalType: ontologicalType,
                targetPotency: try potency(object, .targetPotency), targetLevel: targetLevel)
        }

        /// Rebuilds a slot.
        ///
        /// - Parameter object: The object that encodes the slot.
        /// - Returns: The slot.
        /// - Throws: ``MultiLevelError/invalidValue(_:)`` if a value is malformed.
        func decodeSlot(_ object: DynamicEObject) throws -> DeepSlot {
            DeepSlot(feature: string(object, .feature) ?? "", values: try children(object, .values).map(decodeValue))
        }

        /// Rebuilds a value from its kind and literal text or referenced clabject.
        ///
        /// - Parameter object: The object that encodes the value.
        /// - Returns: The value.
        /// - Throws: ``MultiLevelError/invalidValue(_:)`` if the kind or literal is invalid.
        func decodeValue(_ object: DynamicEObject) throws -> DeepValue {
            let literal = string(object, .literal) ?? ""
            switch ValueKind(rawValue: string(object, .valueKind) ?? "") {
            case .string?: return .string(literal)
            case .integer?:
                guard let number = Int(literal) else { throw MultiLevelError.invalidValue("integer '\(literal)'") }
                return .integer(number)
            case .real?:
                guard let number = Double(literal) else { throw MultiLevelError.invalidValue("real '\(literal)'") }
                return .real(number)
            case .boolean?: return .boolean(literal == String(true))
            case .literal?: return .literal(literal)
            case .object?:
                guard let id = clabjectID(object, .object) else { throw MultiLevelError.invalidValue("object value") }
                return .object(id)
            case nil: throw MultiLevelError.invalidValue("value kind")
            }
        }

        /// Rebuilds a constraint.
        ///
        /// - Parameter object: The object that encodes the constraint.
        /// - Returns: The constraint.
        /// - Throws: ``MultiLevelError/invalidValue(_:)`` if the potency is invalid.
        func decodeConstraint(_ object: DynamicEObject) throws -> DeepConstraint {
            DeepConstraint(
                name: string(object, .name) ?? "", potency: try potency(object, .potency),
                body: string(object, .body) ?? "",
                language: string(object, .language) ?? MultiLevelSyntax.constraintLanguage)
        }
    }
}
