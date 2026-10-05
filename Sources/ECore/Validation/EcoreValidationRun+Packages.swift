//
// EcoreValidationRun+Packages.swift
// ECore
//
//  Created by Rene Hexel on 5/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase

extension EcoreValidationRun {
    /// Checks a package.
    func checkPackage(_ value: EPackage) {
        checkName(of: value.id, value.name)
        if isEnabled(.wellFormedNsURI), !EcoreValidationSyntax.isWellFormedURI(value.nsURI) {
            report(
                .wellFormedNsURI, .nsURINotWellFormed, element: value.id, feature: .nsURI,
                arguments: [value.nsURI])
        }
        if isEnabled(.wellFormedNsPrefix), !isWellFormedPrefix(of: value) {
            report(
                .wellFormedNsPrefix, .nsPrefixNotWellFormed, element: value.id, feature: .nsPrefix,
                arguments: [value.nsPrefix])
        }
        checkSubpackageNames(of: value)
        reportNameClashes(
            in: value.id, feature: .eClassifiers,
            items: value.eClassifiers.map { (id: $0.id, name: $0.name) },
            code: .uniqueClassifierNames, duplicate: .duplicateClassifierName,
            similar: .similarClassifierNames)
        if isEnabled(.uniqueNsURIs), !value.nsURI.isEmpty {
            let sharing = packagesSharingNamespace(with: value)
            if sharing.count > 1 {
                report(
                    .uniqueNsURIs, .duplicateNsURI, element: value.id, feature: .nsURI,
                    arguments: [value.nsURI], related: sharing.filter { $0 != value.id })
            }
        }
    }

    /// Whether a package's namespace prefix is empty or a valid XML name that is not reserved.
    private func isWellFormedPrefix(of value: EPackage) -> Bool {
        let prefix = value.nsPrefix
        if prefix.isEmpty { return true }
        guard EcoreValidationSyntax.isNCName(prefix) else { return false }
        return !prefix.lowercased().hasPrefix(EcoreValidationSyntax.reservedPrefix)
            || value.nsURI == EcoreValidationSyntax.xmlNamespaceURI
    }

    /// Checks that the subpackages of a package have different names.
    private func checkSubpackageNames(of value: EPackage) {
        guard isEnabled(.uniqueSubpackageNames), value.eSubpackages.count > 1 else { return }
        var order: [String] = []
        var groups: [String: [EUUID]] = [:]
        for subpackage in value.eSubpackages {
            if groups[subpackage.name] == nil { order.append(subpackage.name) }
            groups[subpackage.name, default: []].append(subpackage.id)
        }
        for name in order {
            guard let group = groups[name], group.count > 1 else { continue }
            report(
                .uniqueSubpackageNames, .duplicateSubpackageName, element: value.id,
                feature: .eSubpackages, arguments: [name], related: group)
        }
    }

    /// Checks an enumeration.
    func checkEnum(_ value: EEnum) {
        checkName(of: value.id, value.name)
        reportNameClashes(
            in: value.id, feature: .eLiterals,
            items: value.literals.map { (id: $0.id, name: $0.name) },
            code: .uniqueEnumeratorNames, duplicate: .duplicateEnumeratorName,
            similar: .similarEnumeratorNames)
        guard isEnabled(.uniqueEnumeratorLiterals), value.literals.count > 1 else { return }
        var order: [String] = []
        var groups: [String: [EUUID]] = [:]
        for literal in value.literals {
            let text = literal.literal ?? literal.name
            if groups[text] == nil { order.append(text) }
            groups[text, default: []].append(literal.id)
        }
        for text in order {
            guard let group = groups[text], group.count > 1 else { continue }
            report(
                .uniqueEnumeratorLiterals, .duplicateEnumeratorLiteral, element: value.id,
                feature: .eLiterals, arguments: [text], related: group)
        }
    }
}
