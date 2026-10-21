//
// JSONSynthesisedClasses.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation

/// Finds the classes that the `eClass` entries of a JSON document name.
protocol JSONClassResolver: Sendable {
    /// Finds the class that a JSON `eClass` value names.
    ///
    /// - Parameter identifier: `"<nsURI>#//<Name>"` or a bare `"<Name>"`.
    /// - Returns: The class, or `nil` if none matches.
    func resolve(_ identifier: String) -> EClass?

    /// Finds the class that the `eClass` value of an object held by a reference names.
    ///
    /// - Parameters:
    ///   - identifier: `"<nsURI>#//<Name>"` or a bare `"<Name>"`.
    ///   - expected: The declared type of the reference.
    /// - Returns: The class, or `nil` if none matches.
    func resolve(_ identifier: String, below expected: EClass) -> EClass?

    /// The class of an object that names no class of its own.
    ///
    /// - Parameter expected: The declared type of the reference that holds the object.
    /// - Returns: The class to build the object from.
    func refined(_ expected: EClass) -> EClass
}

extension JSONClassResolver {
    /// The class of an object that names no class of its own.
    ///
    /// Registered classes carry their features, so the declared type is used as it is.
    ///
    /// - Parameter expected: The declared type of the reference that holds the object.
    /// - Returns: `expected`.
    func refined(_ expected: EClass) -> EClass { expected }
}

/// The name of the class that a JSON `eClass` value names.
///
/// - Parameter identifier: `"<nsURI>#//<Name>"`, `"#//<Name>"`, or a bare `"<Name>"`.
/// - Returns: The last segment of the fragment, or the identifier if it has no fragment.
func jsonClassName(of identifier: String) -> String {
    guard let fragment = URIReference.split(identifier).fragment else { return identifier }
    return fragment.split(separator: CrossReferenceSyntax.segmentSeparator).last.map(String.init) ?? fragment
}

/// The kinds of primitive values that a JSON document holds.
enum JSONScalarKind: Hashable, Sendable {
    /// `true` or `false`.
    case boolean

    /// A number without a fractional part.
    case integer

    /// A number with a fractional part or an exponent.
    case double

    /// A string.
    case string

    /// The Objective-C type encodings of `NSNumber` values that hold Booleans.
    private static let booleanEncodings: Set<String> = ["c", "B"]

    /// The Objective-C type encodings of `NSNumber` values that hold floating-point numbers.
    private static let floatingPointEncodings: Set<String> = ["f", "d"]

    /// The kind of a value that `JSONSerialization` produced.
    ///
    /// Booleans are told apart from numbers by their Core Foundation type where it exists,
    /// and by the type encoding of the number elsewhere; Swift values of the standard
    /// types are classified directly.
    ///
    /// - Parameter json: The JSON value.
    /// - Returns: The kind, or `nil` for arrays, objects, and `null`.
    static func of(_ json: Any) -> JSONScalarKind? {
        if json is String { return .string }
        if let number = json as? NSNumber {
            if isBoolean(number) { return .boolean }
            return floatingPointEncodings.contains(String(cString: number.objCType)) ? .double : .integer
        }
        switch json {
        case is Bool: return .boolean
        case is Int: return .integer
        case is Double, is Float: return .double
        default: return nil
        }
    }

    /// Whether a number that `JSONSerialization` produced is a Boolean.
    ///
    /// - Parameter number: The number.
    /// - Returns: `true` for `true` and `false`.
    private static func isBoolean(_ number: NSNumber) -> Bool {
        #if canImport(Darwin)
        return CFGetTypeID(number) == CFBooleanGetTypeID()
        #else
        return booleanEncodings.contains(String(cString: number.objCType))
        #endif
    }
}

/// Classes synthesised from the objects of JSON documents that no registered metamodel describes.
///
/// Every class named by an `eClass` entry receives the union of the keys of all objects of that
/// class, in alphabetical order. A key that holds nested objects becomes a containment
/// reference, a key that holds `$ref` objects a non-containment reference, and a key that holds
/// strings, numbers, or Booleans an attribute of the matching data type; a key that holds an
/// array becomes a many-valued feature, and a key that only ever holds empty arrays or `null`
/// becomes no feature. A nested object without an `eClass` entry takes the class of its typed
/// siblings if they agree, and otherwise the class named ``XMIDocumentSyntax/untypedClassName``.
struct SynthesisedClasses: JSONClassResolver {
    /// What the values of one key reveal about the feature.
    private struct Evidence {
        /// The kinds of primitive values found.
        var scalars: Set<JSONScalarKind> = []

        /// Whether a `$ref` object was found.
        var references = false

        /// The classes of the nested objects found.
        var containedClasses: Set<String> = []

        /// Whether an array was found.
        var many = false

        /// Whether any value was found that calls for a feature.
        var isEmpty: Bool { scalars.isEmpty && !references && containedClasses.isEmpty }
    }

    /// The synthesised classes by name.
    private let classes: [String: EClass]

    /// The names of the synthesised classes in the order in which the documents first use them.
    let names: [String]

    /// The name of the class of nested objects whose class cannot be told.
    static let defaultClassName = XMIDocumentSyntax.untypedClassName

    /// Synthesises the classes of JSON documents.
    ///
    /// - Parameter documents: The JSON objects of the roots.
    init(documents: [[String: Any]]) {
        var evidence: [String: [String: Evidence]] = [:]
        var order: [String] = []
        for document in documents {
            let name = (document[JSONSyntax.eClassKey] as? String).map(jsonClassName(of:)) ?? Self.defaultClassName
            Self.collect(document, as: name, into: &evidence, order: &order)
        }
        var built: [String: EClass] = [:]
        for name in order {
            let features = (evidence[name] ?? [:]).filter { !$0.value.isEmpty }.sorted { $0.key < $1.key }
                .map { key, found in Self.feature(named: key, from: found) }
            built[name] = EClass(name: name, eStructuralFeatures: features)
        }
        classes = built
        names = order
    }

    /// Finds the synthesised class that a JSON `eClass` value names.
    ///
    /// - Parameter identifier: `"<nsURI>#//<Name>"` or a bare `"<Name>"`.
    /// - Returns: The class synthesised for the name, or `nil` if the documents use no such class.
    func resolve(_ identifier: String) -> EClass? {
        classes[jsonClassName(of: identifier)]
    }

    /// Finds the synthesised class that the `eClass` value of a nested object names.
    ///
    /// Synthesised classes have no hierarchy, so the declared type of the reference does not
    /// narrow the search.
    ///
    /// - Parameters:
    ///   - identifier: `"<nsURI>#//<Name>"` or a bare `"<Name>"`.
    ///   - expected: The declared type of the reference that holds the object.
    /// - Returns: The class synthesised for the name, or `nil` if the documents use no such class.
    func resolve(_ identifier: String, below expected: EClass) -> EClass? {
        resolve(identifier)
    }

    /// The class of a nested object that names no class of its own.
    ///
    /// The declared type of a synthesised reference names the class of the nested objects
    /// without carrying its features, so the class is looked up by that name.
    ///
    /// - Parameter expected: The declared type of the reference that holds the object.
    /// - Returns: The synthesised class of that name, or `expected` if there is none.
    func refined(_ expected: EClass) -> EClass {
        classes[expected.name] ?? expected
    }

    // MARK: - Collecting

    /// Records the keys of an object and of the objects it contains.
    ///
    /// The evidence for each key is updated in place before nested objects are visited, so
    /// that an object nested in an object of the same class adds to the same evidence.
    ///
    /// - Parameters:
    ///   - document: The JSON object.
    ///   - name: The name of the object's class.
    ///   - evidence: The evidence of every class and key, updated.
    ///   - order: The class names in the order of first use, updated.
    private static func collect(
        _ document: [String: Any], as name: String, into evidence: inout [String: [String: Evidence]],
        order: inout [String]
    ) {
        if evidence[name] == nil {
            evidence[name] = [:]
            order.append(name)
        }
        for key in document.keys.sorted() where key != JSONSyntax.eClassKey {
            guard let json = document[key], !(json is NSNull) else { continue }
            let entries: [Any]
            if let array = json as? [Any] {
                evidence[name, default: [:]][key, default: Evidence()].many = true
                entries = array
            } else {
                entries = [json]
            }
            var nested: [[String: Any]] = []
            for entry in entries {
                if let object = entry as? [String: Any] {
                    if object[JSONSyntax.referenceKey] is String {
                        evidence[name, default: [:]][key, default: Evidence()].references = true
                    } else {
                        nested.append(object)
                    }
                } else if let kind = JSONScalarKind.of(entry) {
                    evidence[name, default: [:]][key, default: Evidence()].scalars.insert(kind)
                }
            }
            guard !nested.isEmpty else { continue }
            let typed = Set(nested.compactMap { ($0[JSONSyntax.eClassKey] as? String).map(jsonClassName(of:)) })
            let untypedName = typed.count == 1 ? typed.first ?? defaultClassName : defaultClassName
            let childNames = nested.map { ($0[JSONSyntax.eClassKey] as? String).map(jsonClassName(of:)) ?? untypedName }
            evidence[name, default: [:]][key, default: Evidence()].containedClasses.formUnion(childNames)
            for (object, childName) in zip(nested, childNames) {
                collect(object, as: childName, into: &evidence, order: &order)
            }
        }
    }

    // MARK: - Building

    /// The feature that the values of a key call for.
    ///
    /// - Parameters:
    ///   - name: The key.
    ///   - evidence: What the values of the key reveal.
    /// - Returns: A containment reference if nested objects were found, a non-containment
    ///   reference if `$ref` objects were found, and otherwise an attribute.
    private static func feature(named name: String, from evidence: Evidence) -> any EStructuralFeature {
        let upperBound = evidence.many ? -1 : 1
        if !evidence.containedClasses.isEmpty {
            let target = evidence.containedClasses.count == 1
                ? evidence.containedClasses.first ?? defaultClassName : defaultClassName
            return EReference(name: name, eType: EClass(name: target), upperBound: upperBound, containment: true)
        }
        if evidence.references {
            return EReference(name: name, eType: EClass(name: defaultClassName), upperBound: upperBound)
        }
        return EAttribute(name: name, eType: dataType(for: evidence.scalars), upperBound: upperBound)
    }

    /// The data type that holds every kind of value found.
    ///
    /// - Parameter kinds: The kinds of primitive values of a key.
    /// - Returns: `EBoolean`, `EInt`, or `EDouble` if the values agree (integers and
    ///   floating-point numbers together are `EDouble`), and `EString` otherwise.
    private static func dataType(for kinds: Set<JSONScalarKind>) -> EDataType {
        let type: EcoreDataType
        switch kinds {
        case [.boolean]: type = .eBoolean
        case [.integer]: type = .eInt
        case [.double], [.integer, .double]: type = .eDouble
        default: type = .eString
        }
        return EcorePackage.dataType(type) ?? EDataType(name: type.rawValue)
    }
}
