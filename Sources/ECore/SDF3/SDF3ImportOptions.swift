//
// SDF3ImportOptions.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//

/// Settings that control how SDF3 definitions and Stratego signatures become Ecore packages.
///
/// The namespace settings only apply when the source does not determine them:
/// SDF3 and Stratego modules have a name but neither a namespace URI nor a
/// prefix, so the URI and prefix always come from these options or from the
/// defaults derived from the package name.
public struct SDF3ImportOptions: Sendable, Hashable {
    /// The package name to use when the source has no `module` declaration.
    ///
    /// When both are missing, the stem of the source name is used, and failing
    /// that a generic name.
    public var packageName: String?

    /// The namespace URI of the package.
    ///
    /// When `nil`, a URN of the form `urn:sdf3:<package>` is used.
    public var nsURI: String?

    /// The namespace prefix of the package.
    ///
    /// When `nil`, the package name in lower case is used.
    public var nsPrefix: String?

    /// Whether features take their names from SDF3 labels such as `<lhs:Exp>`.
    ///
    /// The abstract syntax that SDF3 defines (its ATerm signature) is
    /// positional, so by default features get generated names that follow the
    /// convention of the ASDL paper: the argument's sort in lower case followed
    /// by its occurrence, such as `exp1` and `exp2`. With this option a labelled
    /// argument takes its label as its name, and unlabelled arguments keep
    /// generated names.
    public var useLabels: Bool

    /// Whether each lexical sort becomes an `EDataType` of its own.
    ///
    /// When `true` (the default), a lexical sort such as `ID` becomes a data
    /// type named `ID` whose instances are strings, so the metamodel keeps the
    /// distinction between lexical sorts. When `false`, every lexical sort is
    /// mapped to Ecore's `EString`.
    public var lexicalSortsAsDataTypes: Bool

    /// Creates import options.
    ///
    /// - Parameters:
    ///   - packageName: The package name to use when the source has no module name.
    ///   - nsURI: The namespace URI, or `nil` for a URN derived from the package name.
    ///   - nsPrefix: The namespace prefix, or `nil` for the package name in lower case.
    ///   - useLabels: Whether labelled arguments are named after their labels.
    ///   - lexicalSortsAsDataTypes: Whether lexical sorts become data types of their own.
    public init(
        packageName: String? = nil, nsURI: String? = nil, nsPrefix: String? = nil,
        useLabels: Bool = false, lexicalSortsAsDataTypes: Bool = true
    ) {
        self.packageName = packageName
        self.nsURI = nsURI
        self.nsPrefix = nsPrefix
        self.useLabels = useLabels
        self.lexicalSortsAsDataTypes = lexicalSortsAsDataTypes
    }
}
