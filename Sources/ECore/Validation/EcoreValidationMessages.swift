//
// EcoreValidationMessages.swift
// ECore
//
//  Created by Rene Hexel on 5/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//

/// The kinds of message that ``EcoreValidator`` can report.
///
/// A constraint can report more than one kind of problem; the message kind identifies the
/// wording and the meaning of each argument, so that a host application can look up its own
/// localised text for it.
public enum EcoreValidationMessage: String, Sendable, Hashable, CaseIterable {
    /// Arguments: the name.
    case nameNotWellFormed
    /// Arguments: the namespace URI.
    case nsURINotWellFormed
    /// Arguments: the namespace prefix.
    case nsPrefixNotWellFormed
    /// Arguments: the name.
    case duplicateSubpackageName
    /// Arguments: the name.
    case duplicateClassifierName
    /// Arguments: the similar names, in order of appearance.
    case similarClassifierNames
    /// Arguments: the namespace URI.
    case duplicateNsURI
    /// Arguments: the source.
    case sourceURINotWellFormed
    /// Arguments: the instance class name.
    case instanceTypeNameNotWellFormed
    /// No arguments.
    case interfaceNotAbstract
    /// Arguments: the names of the first two identifier attributes.
    case multipleIDs
    /// Arguments: the name.
    case duplicateFeatureName
    /// Arguments: the similar names, in order of appearance.
    case similarFeatureNames
    /// Arguments: the signatures of the two operations.
    case duplicateOperationSignature
    /// Arguments: the signature of the operation and the name of the feature.
    case operationClashesWithAccessor
    /// No arguments.
    case circularSuperTypes
    /// Arguments: the name of the missing feature.
    case mapEntryMissingFeature
    /// No arguments.
    case mapEntryInstanceClassName
    /// Arguments: the lower bound.
    case lowerBoundNegative
    /// Arguments: the upper bound.
    case upperBoundInvalid
    /// Arguments: the lower bound and the upper bound.
    case boundsInconsistent
    /// No arguments.
    case typeMissing
    /// No arguments.
    case attributeTypeIsClass
    /// No arguments.
    case referenceTypeIsDataType
    /// Arguments: the upper bound.
    case voidOperationRepeats
    /// Arguments: the name.
    case duplicateParameterName
    /// Arguments: the literal.
    case defaultValueInvalid
    /// Arguments: the qualified name of the attribute.
    case transientRequired
    /// Arguments: the name of the reference and of its opposite.
    case oppositeNotMatching
    /// Arguments: the name of the reference and of its opposite.
    case oppositeNotFromType
    /// Arguments: the name of the reference.
    case selfOpposite
    /// Arguments: the name of the reference and of its opposite.
    case oppositeNotTransient
    /// Arguments: the name of the reference and of its opposite.
    case oppositeBothContainment
    /// Arguments: the upper bound.
    case containerNotSingle
    /// Arguments: the name of the container reference that needs a container.
    case containerRequiresContainer
    /// No arguments.
    case containmentNotUnique
    /// Arguments: the name.
    case duplicateEnumeratorName
    /// Arguments: the similar names, in order of appearance.
    case similarEnumeratorNames
    /// Arguments: the literal text.
    case duplicateEnumeratorLiteral
    /// Arguments: the name of the invalid reference key.
    case keyNotFromType
    /// Arguments: the duplicate type parameter name.
    case duplicateTypeParameterName
    /// No arguments.
    case genericTypeConflictingTargets
    /// No arguments.
    case typeParameterOutOfScope
    /// No arguments.
    case genericClassifierInvalid
    /// No arguments.
    case genericWildcardInvalid
    /// No arguments.
    case genericBoundsInvalid
    /// Arguments: the actual and expected number of arguments.
    case genericArgumentsInvalid
    /// No arguments.
    case genericSubstitutionInvalid
    /// Arguments: the name of the conflicting superclass.
    case genericSuperTypesInconsistent
    /// Arguments: the unresolved reference text.
    case unresolvedProxy
    /// Arguments: the message that a delegate reported.
    case delegateMessage
}

/// The catalogue of message texts for metamodel validation.
///
/// Each text is a template whose placeholders `{0}`, `{1}`, and so on take the arguments of a
/// diagnostic in order. All wording lives in this file so that it can be reviewed and
/// translated in one place, and so that argument formatting is decided in one place.
public enum EcoreValidationMessages {
    /// The template of a kind of message.
    ///
    /// - Parameter message: The kind of message.
    /// - Returns: The template text, with numbered placeholders for the arguments.
    public static func template(for message: EcoreValidationMessage) -> String {
        switch message {
        case .nameNotWellFormed: "The name '{0}' is not well formed."
        case .nsURINotWellFormed: "The namespace URI '{0}' is not well formed."
        case .nsPrefixNotWellFormed: "The namespace prefix '{0}' is not well formed."
        case .duplicateSubpackageName: "There is more than one subpackage named '{0}'."
        case .duplicateClassifierName: "There is more than one classifier named '{0}'."
        case .similarClassifierNames:
            "The classifier names '{0}' and '{1}' differ only by case or underscores."
        case .duplicateNsURI: "More than one package has the namespace URI '{0}'."
        case .sourceURINotWellFormed: "The annotation source '{0}' is not a well-formed URI."
        case .instanceTypeNameNotWellFormed: "The instance class name '{0}' is not well formed."
        case .interfaceNotAbstract: "An interface must also be abstract."
        case .multipleIDs: "The attributes '{0}' and '{1}' cannot both be identifiers."
        case .duplicateFeatureName: "There is more than one feature named '{0}'."
        case .similarFeatureNames:
            "The feature names '{0}' and '{1}' differ only by case or underscores."
        case .duplicateOperationSignature:
            "The operations '{0}' and '{1}' have the same signature."
        case .operationClashesWithAccessor:
            "The operation '{0}' has the same signature as an accessor of the feature '{1}'."
        case .circularSuperTypes: "A class cannot be its own supertype."
        case .mapEntryMissingFeature: "A map entry class needs a feature named '{0}'."
        case .mapEntryInstanceClassName:
            "A class that inherits from a map entry class must itself be a map entry class."
        case .lowerBoundNegative: "The lower bound {0} must not be negative."
        case .upperBoundInvalid: "The upper bound {0} must be positive, -1 (unbounded), or -2 (unspecified)."
        case .boundsInconsistent: "The lower bound {0} must not exceed the upper bound {1}."
        case .typeMissing: "A typed element must have a type."
        case .attributeTypeIsClass: "The type of an attribute must be a data type, not a class."
        case .referenceTypeIsDataType: "The type of a reference must be a class, not a data type."
        case .voidOperationRepeats: "An operation without a type must have an upper bound of 1, not {0}."
        case .duplicateParameterName: "There is more than one parameter named '{0}'."
        case .defaultValueInvalid: "The default value '{0}' is not a valid literal of the attribute's type."
        case .transientRequired:
            "The attribute '{0}' must be transient because its type is not serialisable."
        case .oppositeNotMatching:
            "The opposite '{1}' of '{0}' must name '{0}' as its own opposite."
        case .oppositeNotFromType: "The opposite '{1}' of '{0}' must belong to the type of '{0}'."
        case .selfOpposite: "The reference '{0}' cannot be its own opposite."
        case .oppositeNotTransient:
            "The opposite '{1}' of the transient reference '{0}' must also be transient."
        case .oppositeBothContainment:
            "The references '{0}' and '{1}' are opposites, so they cannot both be containments."
        case .containerNotSingle: "A container reference must have an upper bound of 1, not {0}."
        case .containerRequiresContainer:
            "The type of this containment requires a container through '{0}' that is not its opposite, so it cannot be populated."
        case .containmentNotUnique:
            "A many-valued containment or bidirectional reference must be unique."
        case .duplicateEnumeratorName: "There is more than one literal named '{0}'."
        case .similarEnumeratorNames:
            "The literal names '{0}' and '{1}' differ only by case or underscores."
        case .duplicateEnumeratorLiteral: "More than one literal has the text '{0}'."
        case .keyNotFromType: "The key '{0}' is not an attribute of the reference's type."
        case .duplicateTypeParameterName: "There is more than one type parameter named '{0}'."
        case .genericTypeConflictingTargets: "A generic type cannot name both a classifier and a type parameter."
        case .typeParameterOutOfScope: "The referenced type parameter is outside this type's declaration scope."
        case .genericClassifierInvalid: "The generic classifier is not suitable for this use."
        case .genericWildcardInvalid: "A wildcard is only permitted as a type argument outside a generic supertype."
        case .genericBoundsInvalid: "Only a wildcard type argument may have one upper or lower bound."
        case .genericArgumentsInvalid: "The generic type has {0} arguments but requires {1}."
        case .genericSubstitutionInvalid: "A type argument does not satisfy its parameter's bounds."
        case .genericSuperTypesInconsistent: "The generic superclass '{0}' is repeated or has inconsistent arguments."
        case .unresolvedProxy: "The reference '{0}' cannot be resolved."
        case .delegateMessage: "{0}"
        }
    }

    /// Builds the text of a message.
    ///
    /// Each placeholder is replaced by the argument of that number. A placeholder without a
    /// matching argument is left as written, and text inside an argument is never
    /// interpreted as a placeholder.
    ///
    /// - Parameters:
    ///   - message: The kind of message.
    ///   - arguments: The values for the placeholders, in order.
    /// - Returns: The text with the placeholders filled in.
    public static func message(_ message: EcoreValidationMessage, arguments: [String]) -> String {
        let template = template(for: message)
        var result = ""
        var index = template.startIndex
        while index < template.endIndex {
            let character = template[index]
            if character == "{", let close = template[index...].firstIndex(of: "}"),
                let number = Int(template[template.index(after: index)..<close]),
                arguments.indices.contains(number)
            {
                result += arguments[number]
                index = template.index(after: close)
            } else {
                result.append(character)
                index = template.index(after: index)
            }
        }
        return result
    }

    /// The names of a group of similar names, as message arguments.
    ///
    /// - Parameter names: The names, in order of appearance.
    /// - Returns: The names without repeats, which are the arguments of a "similar names"
    ///   message.
    static func arguments(forNames names: [String]) -> [String] {
        var seen: Set<String> = []
        return names.filter { seen.insert($0).inserted }
    }

    /// The label of an operation signature, as a message argument.
    ///
    /// - Parameters:
    ///   - name: The operation name.
    ///   - parameterTypes: The names of the parameter types, with `nil` for an untyped parameter.
    /// - Returns: The name followed by the parameter types in parentheses.
    static func signatureLabel(name: String, parameterTypes: [String?]) -> String {
        "\(name)(\(parameterTypes.map { $0 ?? "?" }.joined(separator: ", ")))"
    }

    /// The label of a bound, as a message argument.
    ///
    /// - Parameter bound: A lower or upper bound.
    /// - Returns: The bound in decimal.
    static func argument(forBound bound: Int) -> String { String(bound) }
}
