//
// KM3Outline.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase

/// Builds the outline of a KM3 document from its syntax tree.
///
/// Packages hold their classifiers and nested packages, classes hold their attributes,
/// references and operations, and enumerations hold their literals. Each identifier is the
/// path of kinds and names from the root, such as `package:Library/class:Book/attribute:title`,
/// with `#2`, `#3` and so on appended to tell apart siblings of the same kind and name.
enum KM3Outline {
    /// The outline of the packages of a document.
    ///
    /// - Parameter packages: The package declarations.
    /// - Returns: One node per root package.
    static func nodes(for packages: [KM3PackageNode]) -> [OutlineNode] {
        var siblings = Siblings(parent: "")
        return packages.map { packageNode(siblings.next(KM3OutlineKind.package, package: $0)) }
    }

    /// Hands out identifiers that are unique among the children of one node.
    private struct Siblings {
        /// The identifier of the parent, or the empty text at the top.
        let parent: String

        /// How often each kind and name has been handed out.
        private var counts: [String: Int] = [:]

        /// Creates the identifier source for the children of a node.
        ///
        /// - Parameter parent: The identifier of the parent.
        init(parent: String) { self.parent = parent }

        /// The identifier of the next child.
        ///
        /// - Parameters:
        ///   - kind: The kind of the child.
        ///   - name: The name of the child.
        /// - Returns: The identifier.
        mutating func identifier(_ kind: String, _ name: String) -> String {
            let base = "\(kind):\(name)"
            let count = (counts[base] ?? 0) + 1
            counts[base] = count
            let local = count > 1 ? "\(base)#\(count)" : base
            return parent.isEmpty ? local : "\(parent)/\(local)"
        }

        /// The identifier of the next package together with the package.
        ///
        /// - Parameters:
        ///   - kind: The kind of the child.
        ///   - package: The package.
        /// - Returns: The identifier and the package.
        mutating func next(_ kind: String, package: KM3PackageNode) -> (String, KM3PackageNode) {
            (identifier(kind, package.name.text), package)
        }
    }

    /// The node of a package.
    ///
    /// - Parameter entry: The identifier and syntax of the package.
    /// - Returns: The node with its children.
    private static func packageNode(_ entry: (String, KM3PackageNode)) -> OutlineNode {
        let (identifier, node) = entry
        var siblings = Siblings(parent: identifier)
        let children = node.elements.map { element -> OutlineNode in
            switch element {
            case .package(let nested):
                return packageNode(siblings.next(KM3OutlineKind.package, package: nested))
            case .dataType(let dataType):
                return OutlineNode(
                    id: siblings.identifier(KM3OutlineKind.dataType, dataType.name.text), kind: KM3OutlineKind.dataType,
                    name: dataType.name.text, range: dataType.range, selectionRange: dataType.name.range)
            case .enumeration(let enumeration):
                return enumerationNode(enumeration, id: siblings.identifier(KM3OutlineKind.enumeration, enumeration.name.text))
            case .class(let eClass):
                return classNode(eClass, id: siblings.identifier(KM3OutlineKind.class, eClass.name.text))
            }
        }
        return OutlineNode(
            id: identifier, kind: KM3OutlineKind.package, name: node.name.text, detail: node.nsURI, range: node.range,
            selectionRange: node.name.range, children: children)
    }

    /// The node of an enumeration.
    ///
    /// - Parameters:
    ///   - node: The syntax of the enumeration.
    ///   - id: The identifier of the node.
    /// - Returns: The node with one child per literal.
    private static func enumerationNode(_ node: KM3EnumerationNode, id: String) -> OutlineNode {
        var siblings = Siblings(parent: id)
        let literals = node.literals.map {
            OutlineNode(
                id: siblings.identifier(KM3OutlineKind.literal, $0.name.text), kind: KM3OutlineKind.literal,
                name: $0.name.text, range: $0.range, selectionRange: $0.name.range)
        }
        return OutlineNode(
            id: id, kind: KM3OutlineKind.enumeration, name: node.name.text, range: node.range,
            selectionRange: node.name.range, children: literals)
    }

    /// The node of a class.
    ///
    /// The detail lists the supertypes; the children are the features and then the operations.
    ///
    /// - Parameters:
    ///   - node: The syntax of the class.
    ///   - id: The identifier of the node.
    /// - Returns: The node with its members.
    private static func classNode(_ node: KM3ClassNode, id: String) -> OutlineNode {
        var siblings = Siblings(parent: id)
        let features = node.features.map { feature -> OutlineNode in
            let kind = feature.kind == .attribute ? KM3OutlineKind.attribute : KM3OutlineKind.reference
            return OutlineNode(
                id: siblings.identifier(kind, feature.name.text), kind: kind, name: feature.name.text,
                detail: (feature.type?.text ?? "") + multiplicityText(feature.multiplicity), range: feature.range,
                selectionRange: feature.name.range)
        }
        let operations = node.operations.map { operation -> OutlineNode in
            let parameters = operation.parameters.map { "\($0.name.text) : \($0.type?.text ?? "")" }
            let result = operation.returnType.map { " : \($0.text)" } ?? ""
            return OutlineNode(
                id: siblings.identifier(KM3OutlineKind.operation, operation.name.text), kind: KM3OutlineKind.operation,
                name: operation.name.text, detail: "(" + parameters.joined(separator: ", ") + ")" + result,
                range: operation.range, selectionRange: operation.name.range)
        }
        let supertypes = node.supertypes.map(\.text).joined(separator: ", ")
        return OutlineNode(
            id: id, kind: KM3OutlineKind.class, name: node.name.text,
            detail: supertypes.isEmpty ? nil : "\(KM3Keyword.extends.rawValue) \(supertypes)", range: node.range,
            selectionRange: node.name.range, children: features + operations)
    }

    /// The text of a written multiplicity, or the empty text for an unwritten one.
    ///
    /// - Parameter multiplicity: The multiplicity.
    /// - Returns: The multiplicity in brackets, such as `[0-1]` or `[*]`.
    private static func multiplicityText(_ multiplicity: KM3MultiplicityNode) -> String {
        guard multiplicity.range != nil else { return "" }
        return KM3Writer.multiplicity(lower: multiplicity.lower, upper: multiplicity.upper)
    }
}
