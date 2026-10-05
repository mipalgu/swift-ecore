//
// EcoreFragmentResolver.swift
// GenModel
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation

/// Resolves textual `ecore*` references against native Ecore packages.
///
/// The resolver walks the fragment path of an ``EcoreReference`` through a loaded
/// package: name segments select subpackages, classifiers, structural features and
/// enumeration literals, and positional segments such as `@eClassifiers.0` select by
/// index. The result is the identifier of the native element, which is how
/// ``GenModelContext`` finds it.
///
/// This is a self-contained step that does not rely on cross-document support in the
/// resource set, so it can be used before, and instead of, general reference resolution.
///
/// ## Example
///
/// ```swift
/// let resolver = EcoreFragmentResolver(packages: [libraryURL: libraryPackage])
/// let id = resolver.resolve("library.ecore#//Book", relativeTo: genModelURL)
/// ```
public struct EcoreFragmentResolver: Sendable {
    private let packages: [String: EPackage]

    /// Creates a resolver.
    ///
    /// - Parameter packages: The root package of each document, keyed by the absolute
    ///   location of the document.
    public init(packages: [URL: EPackage]) {
        self.packages = Dictionary(
            uniqueKeysWithValues: packages.map { (Self.canonical($0.key), $0.value) })
    }

    /// Resolves a textual reference.
    ///
    /// - Parameters:
    ///   - text: The reference text, for example `ecore:EAttribute library.ecore#//Book/title`.
    ///   - base: The location of the referring document, against which the reference's
    ///     location is resolved.
    /// - Returns: The identifier of the referenced native element, or `nil` if the text is not
    ///   a reference, the document is unknown, or the path does not lead to an element.
    public func resolve(_ text: String, relativeTo base: URL) -> EUUID? {
        guard let reference = EcoreReference(text) else { return nil }
        let documentURL =
            reference.location.isEmpty
            ? base : URL(string: reference.location, relativeTo: base)?.absoluteURL
        guard let documentURL, let root = packages[Self.canonical(documentURL)] else { return nil }
        return Self.walk(reference.segments, from: root)
    }

    private static func canonical(_ url: URL) -> String {
        URIReference.canonicalise(url.standardizedFileURL.absoluteString)
    }

    private enum Node {
        case package(EPackage)
        case eClass(EClass)
        case eEnum(EEnum)
        case other(EUUID)

        var identifier: EUUID {
            switch self {
            case .package(let value): return value.id
            case .eClass(let value): return value.id
            case .eEnum(let value): return value.id
            case .other(let id): return id
            }
        }
    }

    private static func walk(_ segments: [String], from root: EPackage) -> EUUID? {
        var current = Node.package(root)
        for segment in segments {
            guard let next = step(from: current, segment: segment) else { return nil }
            current = next
        }
        return current.identifier
    }

    private static func step(from node: Node, segment: String) -> Node? {
        if segment.first == GenModelConstants.positionalSegmentPrefix {
            return positionalStep(from: node, segment: segment)
        }
        switch node {
        case .package(let package):
            if let subpackage = package.eSubpackages.first(where: { $0.name == segment }) {
                return .package(subpackage)
            }
            return package.eClassifiers.first { $0.name == segment }.flatMap(classifierNode)
        case .eClass(let eClass):
            return eClass.eStructuralFeatures.first { $0.name == segment }.map { .other($0.id) }
        case .eEnum(let eEnum):
            return eEnum.literals.first { $0.name == segment }.map { .other($0.id) }
        case .other:
            return nil
        }
    }

    private static func positionalStep(from node: Node, segment: String) -> Node? {
        let body = segment.dropFirst()
        guard let dot = body.lastIndex(of: GenModelConstants.positionSeparator),
            let index = Int(body[body.index(after: dot)...]), index >= 0
        else { return nil }
        let feature = String(body[..<dot])
        switch (node, feature) {
        case (.package(let package), GenModelConstants.classifiersFeature):
            guard package.eClassifiers.indices.contains(index) else { return nil }
            return classifierNode(package.eClassifiers[index])
        case (.package(let package), GenModelConstants.subpackagesFeature):
            guard package.eSubpackages.indices.contains(index) else { return nil }
            return .package(package.eSubpackages[index])
        case (.eClass(let eClass), GenModelConstants.structuralFeaturesFeature):
            guard eClass.eStructuralFeatures.indices.contains(index) else { return nil }
            return .other(eClass.eStructuralFeatures[index].id)
        case (.eEnum(let eEnum), GenModelConstants.literalsFeature):
            guard eEnum.literals.indices.contains(index) else { return nil }
            return .other(eEnum.literals[index].id)
        default:
            return nil
        }
    }

    private static func classifierNode(_ classifier: any EClassifier) -> Node {
        switch classifier {
        case let eClass as EClass: return .eClass(eClass)
        case let eEnum as EEnum: return .eEnum(eEnum)
        default: return .other(classifier.id)
        }
    }
}
