//
// SDF3Reader.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase

/// Reads SDF3 syntax definitions and Stratego signatures into Ecore packages.
///
/// The reader takes the abstract syntax that a definition implies, which is
/// the ATerm signature that Spoofax generates from it, and represents it as a
/// metamodel. Concrete syntax (literals, layout, priorities, restrictions and
/// template options) does not affect the result. One source is one module and
/// yields one package; imported modules are recorded in the outline but not
/// resolved, so sorts that they define are reported and guessed.
///
/// ## Mapping
///
/// | SDF3 or Stratego | Ecore |
/// |---|---|
/// | `module a/b/c` | `EPackage` named `c`; namespace URI and prefix from the options, or `urn:sdf3:c` and `c` |
/// | context-free sort (`sorts`, `context-free sorts`, left-hand side of a context-free production, result of a signature constructor) | abstract `EClass` |
/// | `Sort.Cons = ...` or `Cons : T1 * T2 -> Sort` | concrete `EClass` `Cons` extending `Sort` |
/// | `Sort.Cons = "keyword"` or `Cons : Sort` | concrete `EClass` without features |
/// | placeholder `<Exp>` or symbol `Exp` (context-free) | containment `EReference` `[1..1]` |
/// | `Exp?`, `Option(Exp)` | bounds `[0..1]` |
/// | `Exp*`, `{Exp ","}*`, `List(Exp)` | bounds `[0..*]`, ordered |
/// | `Exp+`, `{Exp ","}+` | bounds `[1..*]`, ordered |
/// | lexical sort (`lexical sorts`, left-hand side of a lexical production, `: string -> Sort`) | `EDataType` with instance class `java.lang.String`, or `EString` when ``SDF3ImportOptions/lexicalSortsAsDataTypes`` is off |
/// | argument of a lexical sort | `EAttribute` typed by that data type |
/// | `string`, `int`, `real` (Stratego) | `EAttribute` typed `EString`, `EInt`, `EDouble` |
/// | type variable such as `a` (Stratego) | containment `EReference` to `EObject` |
/// | literals, character classes, `LAYOUT` | nothing |
/// | `Exp = Term` (context-free injection), `: Term -> Exp` | `Term` extends `Exp` |
/// | `Exp = INT` (lexical injection) | concrete `EClass` `ExpINT` extending `Exp` with attribute `value`, and an information diagnostic |
/// | `{bracket}` and `{reject}` productions | nothing |
/// | `{cons("Name")}` on an unnamed production (SDF2 style) | constructor `Name` |
/// | priorities, restrictions, template options, start symbols, Stratego rules, strategies and overlays | skipped |
///
/// ## Feature names
///
/// The ATerm signature is positional, so arguments get generated names by
/// default: the sort of the argument (of its elements, for lists and options)
/// in lower case, followed by its occurrence among the arguments of that sort,
/// such as `exp1` and `exp2`. This is the convention of the generated code in
/// the [ASDL paper](https://www.usenix.org/conference/dsl-97/zephyr-abstract-syntax-description-language)
/// of Wang, Appel, Korn and Serra (1997). With
/// ``SDF3ImportOptions/useLabels``, labelled arguments such as `<lhs:Exp>` are
/// named after their labels.
///
/// ## Sorts and names
///
/// Kernel suffixes `-CF` and `-LEX` are removed, and characters that cannot
/// occur in Ecore names become underscores, so `STRING-CHAR` becomes
/// `STRING_CHAR`. A sort with both lexical and context-free definitions is
/// treated as context-free with a warning. A sort that is used but not
/// defined is reported; it is assumed to be lexical when it is spelt in
/// capitals, such as `ID` or `INT`, and context-free otherwise.
///
/// A constructor that is declared again for the same sort with the same
/// number of arguments (another concrete syntax for the same constructor) is
/// read once. A constructor whose name clashes with a sort or with a
/// constructor of another sort or arity is renamed by appending its sort,
/// such as `AddType`, with a warning.
public enum SDF3Reader {
    /// Reads an SDF3 definition or a Stratego signature.
    ///
    /// Reading never fails: problems are reported as diagnostics, and the
    /// package holds everything that could be read.
    ///
    /// - Parameters:
    ///   - text: The source text.
    ///   - sourceName: The name of the source document, such as a file path;
    ///     used as the document of diagnostics and, without a module
    ///     declaration, for the package name.
    ///   - options: The settings of the import.
    /// - Returns: The package, the diagnostics ordered by position, the tokens and the outline.
    public static func parse(
        _ text: String, sourceName: String? = nil, options: SDF3ImportOptions = .init()
    ) -> SDF3ParseResult {
        var lexer = SDF3Lexer(text)
        let scanned = lexer.tokenise()
        var parser = SDF3Parser(tokens: scanned, endRange: lexer.endRange, document: sourceName)
        parser.parse()
        var collector = parser.collector
        for comment in scanned where comment.isTrivia && !comment.isTerminated {
            collector.error(
                SDF3DiagnosticCode.unterminatedComment.rawValue, "The comment has no closing '*/'", at: comment.range)
        }
        let draft = SDF3Mapper(options: options, sourceName: sourceName).map(parser.definition, collector: &collector)
        let assembled = GrammarMetamodelAssembler(codePrefix: SDF3Language.notation, document: sourceName).assemble([draft])
        collector.append(contentsOf: assembled.diagnostics)
        return SDF3ParseResult(
            packages: assembled.packages, diagnostics: collector.sorted, tokens: SDF3Syntax.classify(scanned),
            outline: parser.outline)
    }
}
