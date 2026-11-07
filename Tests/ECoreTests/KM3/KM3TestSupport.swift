//
// KM3TestSupport.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation

/// Neutral, self-authored KM3 documents for the tests.
enum KM3Fixtures {
    /// A library metamodel that uses every construct of KM3.
    ///
    /// It has directives, several packages with forward and cross-package references,
    /// multiple inheritance, every multiplicity form, ordered, unique and container modifiers,
    /// opposites, quoted names, an attribute of a class type, enumerations, data types,
    /// operations with and without results, and a trailing package of primitive types.
    static let library = """
        -- @name Library
        -- @version 1.0
        -- @nsURI http://example.org/library
        -- @nsPrefix lib
        package Library {

        \tabstract class NamedElement {
        \t\tattribute name : String;
        \t}

        \tclass Library extends NamedElement {
        \t\treference books[*] ordered container : Book oppositeOf library;
        \t\treference members[0-*] container : Member;
        \t\tattribute address : Address;
        \t}

        \tclass Book extends NamedElement, Lendable {
        \t\tattribute isbn[0-1] : String;
        \t\tattribute pages : Integer;
        \t\tattribute keywords[*] ordered unique : String;
        \t\tattribute genre : Genre;
        \t\tattribute price[0-1] : Money;
        \t\treference library : Library oppositeOf books;
        \t\treference authors[1-*] ordered : Person;
        \t\treference "class"[0-1] : Category;
        \t\toperation lend(borrower : Member, days : Integer) : Boolean;
        \t\toperation reset();
        \t}

        \tabstract class Lendable {
        \t\tattribute available : Boolean;
        \t\tattribute rating[2-5] : Double;
        \t}

        \tclass Category extends NamedElement {}

        \tclass Address {
        \t\tattribute street : String;
        \t}

        \tenumeration Genre {
        \t\tliteral fiction;
        \t\tliteral science;
        \t\tliteral "package";
        \t}

        \tdatatype Money;
        }

        -- @nsURI http://example.org/people
        -- @nsPrefix people
        package People {

        \tclass Person {
        \t\tattribute name : String;
        \t}

        \tclass Member extends Person {
        \t\treference loans[*] : Book;
        \t}
        }

        package PrimitiveTypes {
        \tdatatype Boolean;
        \tdatatype Double;
        \tdatatype Integer;
        \tdatatype String;
        }

        """

    /// A document with a nested package.
    static let nested = """
        -- @nsURI http://example.org/outer
        -- @nsPrefix outer
        package Outer {

        \tclass Holder {
        \t\treference items[*] container : Item;
        \t}

        \t-- @nsURI http://example.org/inner
        \t-- @nsPrefix inner
        \tpackage Inner {

        \t\tclass Item {
        \t\t\tattribute label : String;
        \t\t}
        \t}
        }

        package PrimitiveTypes {
        \tdatatype String;
        }

        """
}

/// A canonical, identifier-free description of packages for structural comparisons.
///
/// The description lists every property that KM3 can express: names, namespaces, the
/// abstract flag and supertypes of classes, the kind, bounds, flags, type and opposite of
/// features, operations with their parameters and result types, enumeration literals with
/// their values, and data types with their instance class names.
enum KM3Structure {
    /// Describes packages.
    ///
    /// - Parameters:
    ///   - packages: The packages.
    ///   - includingOpposites: Whether references list their opposites and container flags.
    /// - Returns: One line per element, indented by nesting.
    static func describe(_ packages: [EPackage], includingOpposites: Bool = true) -> String {
        var features: [EUUID: String] = [:]
        func index(_ package: EPackage) {
            for case let eClass as EClass in package.eClassifiers {
                for feature in eClass.eStructuralFeatures { features[feature.id] = "\(eClass.name).\(feature.name)" }
            }
            package.eSubpackages.forEach(index)
        }
        packages.forEach(index)
        var lines: [String] = []
        func describe(_ package: EPackage, indent: String) {
            lines.append("\(indent)package \(package.name) <\(package.nsURI)> <\(package.nsPrefix)>")
            for classifier in package.eClassifiers {
                switch classifier {
                case let eClass as EClass:
                    let supers = eClass.eSuperTypes.map(\.name).joined(separator: ",")
                    lines.append("\(indent)  class \(eClass.name) abstract=\(eClass.isAbstract) extends=[\(supers)]")
                    for feature in eClass.eStructuralFeatures {
                        switch feature {
                        case let attribute as EAttribute:
                            lines.append(
                                "\(indent)    attribute \(attribute.name) \(attribute.lowerBound)..\(attribute.upperBound)"
                                    + " ordered=\(attribute.ordered) unique=\(attribute.unique)"
                                    + " type=\(typeName(attribute.eType))")
                        case let reference as EReference:
                            let opposite = reference.opposite.map { features[$0] ?? "?" } ?? "-"
                            let link = includingOpposites
                                ? " container=\(reference.container) opposite=\(opposite)" : ""
                            lines.append(
                                "\(indent)    reference \(reference.name) \(reference.lowerBound)..\(reference.upperBound)"
                                    + " ordered=\(reference.ordered) unique=\(reference.unique)"
                                    + " containment=\(reference.containment) type=\(typeName(reference.eType))" + link)
                        default:
                            lines.append("\(indent)    feature \(feature.name)")
                        }
                    }
                    for operation in eClass.eOperations {
                        let parameters = operation.eParameters.map {
                            "\($0.name):\($0.eType.map(typeName) ?? "-")"
                        }.joined(separator: ",")
                        lines.append(
                            "\(indent)    operation \(operation.name)(\(parameters))"
                                + " -> \(operation.eType.map(typeName) ?? "-")")
                    }
                case let eEnum as EEnum:
                    let literals = eEnum.literals.map { "\($0.name)=\($0.value)" }.joined(separator: ",")
                    lines.append("\(indent)  enum \(eEnum.name) [\(literals)]")
                case let dataType as EDataType:
                    lines.append("\(indent)  datatype \(dataType.name) class=\(dataType.instanceClassName ?? "-")")
                default:
                    lines.append("\(indent)  classifier \(classifier.name)")
                }
            }
            for subpackage in package.eSubpackages { describe(subpackage, indent: indent + "  ") }
        }
        for package in packages { describe(package, indent: "") }
        return lines.joined(separator: "\n")
    }

    /// The description of a type: its name, marked when it is a built-in Ecore data type.
    ///
    /// - Parameter type: The type.
    /// - Returns: The name, prefixed with `ecore:` for a built-in data type.
    static func typeName(_ type: any EClassifier) -> String {
        if let builtIn = EcoreDataType(rawValue: type.name), EcorePackage.dataType(builtIn)?.id == type.id {
            return "ecore:" + type.name
        }
        return type.name
    }
}

/// Helpers for finding elements of packages in tests.
extension Array where Element == EPackage {
    /// The package of a name, searching nested packages too.
    ///
    /// - Parameter name: The name.
    /// - Returns: The package, or `nil`.
    func package(named name: String) -> EPackage? {
        for package in self {
            if package.name == name { return package }
            if let nested = package.eSubpackages.package(named: name) { return nested }
        }
        return nil
    }

    /// The class of a name in any package.
    ///
    /// - Parameter name: The name.
    /// - Returns: The class, or `nil`.
    func eClass(named name: String) -> EClass? {
        for package in self {
            if let eClass = package.getEClass(name) { return eClass }
            if let nested = package.eSubpackages.eClass(named: name) { return nested }
        }
        return nil
    }
}

/// Reads text with the ISO-8859-1 fallback of `DecodedText` for files that are not UTF-8.
///
/// - Parameter url: The file.
/// - Returns: The text.
/// - Throws: The error of the file system.
func readText(at url: URL) throws -> String {
    try DecodedText(contentsOf: url).text
}
