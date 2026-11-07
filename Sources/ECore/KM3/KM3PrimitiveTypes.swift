//
// KM3PrimitiveTypes.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//

/// A primitive data type of KM3 and the Ecore data type it corresponds to.
///
/// KM3 has no built-in types: a document declares its primitive types, conventionally in
/// a package named `PrimitiveTypes`, as in `datatype String;`. A primitive type relates a
/// declared name to a built-in data type of Ecore and to the Java class that the annotation
/// files of the ATL tool chain give such a data type.
public struct KM3PrimitiveType: Sendable, Hashable {
    /// The name under which a KM3 document declares the type, such as `String`.
    public let name: String

    /// The built-in Ecore data type that the type corresponds to, such as `EString`.
    public let ecoreType: EcoreDataType

    /// The Java instance class name that the annotation files of the ATL tool chain give the
    /// type, such as `java.lang.String`.
    public let instanceClassName: String

    /// Creates a primitive type.
    ///
    /// - Parameters:
    ///   - name: The KM3 name of the type.
    ///   - ecoreType: The corresponding built-in Ecore data type.
    ///   - instanceClassName: The conventional Java instance class name.
    public init(name: String, ecoreType: EcoreDataType, instanceClassName: String) {
        self.name = name
        self.ecoreType = ecoreType
        self.instanceClassName = instanceClassName
    }
}

/// How a KM3 reader treats the data types that a document declares.
///
/// The raw value of each case is its name, such as `ecore`, which command-line tools and
/// configuration files use to choose the mapping.
public enum KM3PrimitiveTypeMapping: String, Sendable, Hashable, CaseIterable {
    /// A declared data type whose name is that of a primitive type (see
    /// ``KM3PrimitiveTypes/all``) or of a built-in Ecore data type stands for the built-in
    /// Ecore data type, such as `EString` for `String`. Such declarations produce no
    /// data type of their own, and a package that held nothing else is left out.
    case ecore

    /// Every declared data type becomes a data type of its package with nothing but its
    /// name, exactly as the KM32EMF transformation of the ATL tool chain makes it. (The
    /// ATL tool chain adds instance class names, such as those of ``KM3PrimitiveType``,
    /// from separate annotation files.)
    case declared
}

/// The primitive data types that KM3 documents conventionally declare.
public enum KM3PrimitiveTypes {
    /// The primitive types, in the order in which a writer prefers their names.
    ///
    /// Where several names correspond to the same Ecore type (`Double` and `Real`,
    /// `Character` and `Char`), the first one is the name that writing produces.
    public static let all: [KM3PrimitiveType] = [
        KM3PrimitiveType(name: "Boolean", ecoreType: .eBoolean, instanceClassName: "boolean"),
        KM3PrimitiveType(name: "Integer", ecoreType: .eInt, instanceClassName: "int"),
        KM3PrimitiveType(name: "String", ecoreType: .eString, instanceClassName: "java.lang.String"),
        KM3PrimitiveType(name: "Double", ecoreType: .eDouble, instanceClassName: "double"),
        KM3PrimitiveType(name: "Real", ecoreType: .eDouble, instanceClassName: "double"),
        KM3PrimitiveType(name: "Float", ecoreType: .eFloat, instanceClassName: "float"),
        KM3PrimitiveType(name: "Long", ecoreType: .eLong, instanceClassName: "long"),
        KM3PrimitiveType(name: "Short", ecoreType: .eShort, instanceClassName: "short"),
        KM3PrimitiveType(name: "Byte", ecoreType: .eByte, instanceClassName: "byte"),
        KM3PrimitiveType(name: "Character", ecoreType: .eChar, instanceClassName: "char"),
        KM3PrimitiveType(name: "Char", ecoreType: .eChar, instanceClassName: "char"),
        KM3PrimitiveType(name: "Date", ecoreType: .eDate, instanceClassName: "java.util.Date"),
        KM3PrimitiveType(
            name: "BigDecimal", ecoreType: .eBigDecimal, instanceClassName: "java.math.BigDecimal"),
        KM3PrimitiveType(
            name: "BigInteger", ecoreType: .eBigInteger, instanceClassName: "java.math.BigInteger"),
    ]

    /// The primitive types by KM3 name.
    private static let byName: [String: KM3PrimitiveType] = Dictionary(uniqueKeysWithValues: all.map { ($0.name, $0) })

    /// The preferred KM3 name of each Ecore data type that a primitive type corresponds to.
    private static let nameByEcoreType: [EcoreDataType: String] = Dictionary(
        all.map { ($0.ecoreType, $0.name) }, uniquingKeysWith: { first, _ in first })

    /// The primitive type that a KM3 name denotes.
    ///
    /// - Parameter name: A KM3 data type name, such as `Integer`.
    /// - Returns: The primitive type, or `nil` if the name is not that of a primitive type.
    public static func primitiveType(named name: String) -> KM3PrimitiveType? {
        byName[name]
    }

    /// The built-in Ecore data type that a declared KM3 data type stands for.
    ///
    /// The names of the primitive types and the names of the built-in Ecore data types
    /// themselves (such as `EString`, which documents extracted from Ecore declare) are
    /// recognised.
    ///
    /// - Parameter name: A KM3 data type name.
    /// - Returns: The Ecore data type, or `nil` if the name denotes none.
    public static func ecoreType(forName name: String) -> EcoreDataType? {
        byName[name]?.ecoreType ?? EcoreDataType(rawValue: name)
    }

    /// The name under which a KM3 document declares a built-in Ecore data type.
    ///
    /// Data types that no primitive type corresponds to keep their Ecore name, which
    /// reading maps back to the same Ecore data type.
    ///
    /// - Parameter type: A built-in Ecore data type.
    /// - Returns: The preferred KM3 name, such as `Integer` for `EInt`.
    public static func name(for type: EcoreDataType) -> String {
        nameByEcoreType[type] ?? type.rawValue
    }
}
