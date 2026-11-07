//
// OCLConstraintAnnotations.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import OCL
import OrderedCollections

/// An OCL constraint as text, with its optional name and message.
public struct OCLConstraintText: Sendable, Hashable {
    /// The name of the constraint, or `nil` if it has none.
    public var name: String?

    /// The OCL expression of the constraint, verbatim.
    public var expression: String

    /// The OCL expression of the message reported when the constraint fails, if any.
    public var message: String?

    /// Creates a constraint.
    ///
    /// - Parameters:
    ///   - name: The name of the constraint.
    ///   - expression: The OCL expression of the constraint.
    ///   - message: The OCL expression of the failure message.
    public init(name: String? = nil, expression: String, message: String? = nil) {
        self.name = name
        self.expression = expression
        self.message = message
    }
}

/// Reads and writes the OCL constraints that Ecore elements carry as annotations.
///
/// Both the OCLinEcore reader and the Complete OCL applier use these functions, so that the
/// same constraint yields the same annotations whichever syntax declared it. The layout is
/// that of Eclipse OCL (see ``OCLAnnotation``). A constraint with a message is stored in the
/// tuple form that Eclipse OCL uses:
///
/// ```
/// Tuple {
///     message : String = <message>,
///     status : Boolean = <expression>
/// }.status
/// ```
public enum OCLConstraintAnnotations {
    /// The name of the message part of a constraint tuple.
    public static let messagePart = "message"

    /// The name of the status part of a constraint tuple.
    public static let statusPart = "status"

    // MARK: - Writing

    /// Adds an invariant to a classifier.
    ///
    /// The invariant's name is appended to the `constraints` detail of the Ecore annotation and
    /// its expression is stored under the name in the OCL annotation. An unnamed invariant is
    /// stored under ``OCLAnnotation/unnamedInvariantKey``.
    ///
    /// - Parameters:
    ///   - invariant: The invariant.
    ///   - element: The classifier that declares it.
    public static func addInvariant(_ invariant: OCLConstraintText, to element: inout some EModelElement) {
        let key = invariant.name ?? OCLAnnotation.unnamedInvariantKey
        var names = constraintNames(of: element)
        if !names.contains(key) { names.append(key) }
        setDetail(
            AnnotationSource.EcoreKey.constraints, names.joined(separator: OCLAnnotation.constraintNameSeparator),
            source: AnnotationSource.ecore, on: &element, before: OCLAnnotation.pivotSource)
        setDetail(key, value(of: invariant), source: OCLAnnotation.pivotSource, on: &element)
    }

    /// Adds a precondition to an operation.
    ///
    /// - Parameters:
    ///   - condition: The precondition.
    ///   - operation: The operation.
    public static func addPrecondition(_ condition: OCLConstraintText, to operation: inout EOperation) {
        setDetail(OCLAnnotation.preconditionKey(named: condition.name), value(of: condition), source: OCLAnnotation.pivotSource, on: &operation)
    }

    /// Adds a postcondition to an operation.
    ///
    /// - Parameters:
    ///   - condition: The postcondition.
    ///   - operation: The operation.
    public static func addPostcondition(_ condition: OCLConstraintText, to operation: inout EOperation) {
        setDetail(OCLAnnotation.postconditionKey(named: condition.name), value(of: condition), source: OCLAnnotation.pivotSource, on: &operation)
    }

    /// Sets the body of an operation.
    ///
    /// - Parameters:
    ///   - expression: The OCL expression that computes the result.
    ///   - operation: The operation.
    public static func setBody(_ expression: String, of operation: inout EOperation) {
        setDetail(OCLAnnotation.bodyKey, expression, source: OCLAnnotation.pivotSource, on: &operation)
    }

    /// Sets the derivation of a structural feature.
    ///
    /// - Parameters:
    ///   - expression: The OCL expression that computes the value.
    ///   - feature: The feature.
    public static func setDerivation(_ expression: String, of feature: inout some EModelElement) {
        setDetail(OCLAnnotation.derivationKey, expression, source: OCLAnnotation.pivotSource, on: &feature)
    }

    /// Sets the initial value of a structural feature.
    ///
    /// - Parameters:
    ///   - expression: The OCL expression that computes the initial value.
    ///   - feature: The feature.
    public static func setInitial(_ expression: String, of feature: inout some EModelElement) {
        setDetail(OCLAnnotation.initialKey, expression, source: OCLAnnotation.pivotSource, on: &feature)
    }

    /// Names the OCL Pivot delegates in the Ecore annotation of a root package.
    ///
    /// - Parameter package: The root package.
    public static func installDelegates(on package: inout EPackage) {
        for key in OCLAnnotation.delegateKeys {
            setDetail(key, OCLAnnotation.pivotSource, source: AnnotationSource.ecore, on: &package)
        }
    }

    /// Records an import in the import annotation of a package.
    ///
    /// - Parameters:
    ///   - alias: The name under which the import is known.
    ///   - uri: The URI of the imported package.
    ///   - package: The package that imports it.
    public static func addImport(alias: String, uri: String, to package: inout EPackage) {
        setDetail(alias, uri, source: OCLAnnotation.importSource, on: &package, before: AnnotationSource.ecore)
    }

    /// Whether a package or anything in it carries OCL expressions.
    ///
    /// - Parameter package: The package.
    /// - Returns: `true` if any element has an annotation with an OCL source.
    public static func hasExpressions(_ package: EPackage) -> Bool {
        /// Whether an element carries an OCL expression annotation.
        ///
        /// - Parameter element: The element.
        /// - Returns: `true` if the element has an annotation with an OCL source.
        func annotated(_ element: some EModelElement) -> Bool {
            element.eAnnotations.contains { OCLAnnotation.expressionSources.contains($0.source) }
        }
        for classifier in package.eClassifiers {
            if let eClass = classifier as? EClass {
                if annotated(eClass) || eClass.eOperations.contains(where: annotated) { return true }
                for feature in eClass.eStructuralFeatures {
                    if let attribute = feature as? EAttribute, annotated(attribute) { return true }
                    if let reference = feature as? EReference, annotated(reference) { return true }
                }
            } else if let dataType = classifier as? EDataType, annotated(dataType) {
                return true
            } else if let eEnum = classifier as? EEnum, annotated(eEnum) {
                return true
            }
        }
        return package.eSubpackages.contains(where: hasExpressions)
    }

    /// The text stored for a constraint: its expression, or the tuple form with its message.
    ///
    /// - Parameter constraint: The constraint.
    /// - Returns: The detail value.
    public static func value(of constraint: OCLConstraintText) -> String {
        guard let message = constraint.message else { return constraint.expression }
        return "Tuple {\n\t\(messagePart) : String = \(message),\n\t\(statusPart) : Boolean = \(constraint.expression)\n}.\(statusPart)"
    }

    /// Sets a detail of the annotation with a source, creating the annotation if needed.
    ///
    /// - Parameters:
    ///   - key: The detail key.
    ///   - value: The detail value.
    ///   - source: The source of the annotation.
    ///   - element: The annotated element.
    ///   - successor: The source of an annotation before which a new annotation is inserted.
    public static func setDetail(
        _ key: String, _ value: String, source: String, on element: inout some EModelElement, before successor: String? = nil
    ) {
        if let index = element.eAnnotations.firstIndex(where: { $0.source == source }) {
            element.eAnnotations[index].details[key] = value
            return
        }
        let annotation = EAnnotation(source: source, orderedDetails: [key: value])
        if let successor, let index = element.eAnnotations.firstIndex(where: { $0.source == successor }) {
            element.eAnnotations.insert(annotation, at: index)
        } else {
            element.eAnnotations.append(annotation)
        }
    }

    // MARK: - Reading

    /// The names in the `constraints` detail of an element, in order.
    ///
    /// - Parameter element: The element.
    /// - Returns: The names, or none if the detail is absent.
    public static func constraintNames(of element: some EModelElement) -> [String] {
        guard let names = element.getEAnnotationDetail(source: AnnotationSource.ecore, key: AnnotationSource.EcoreKey.constraints) else {
            return []
        }
        return names.split(whereSeparator: OCLAnnotation.constraintNameSeparators.contains).map(String.init)
    }

    /// The OCL details of an element, from the Pivot and the legacy annotations, in order.
    ///
    /// - Parameter element: The element.
    /// - Returns: The details, the Pivot ones first.
    public static func expressionDetails(of element: some EModelElement) -> OrderedDictionary<String, String> {
        var result: OrderedDictionary<String, String> = [:]
        for source in OCLAnnotation.expressionSources {
            for annotation in element.eAnnotations where annotation.source == source {
                for (key, value) in annotation.details where result[key] == nil { result[key] = value }
            }
        }
        return result
    }

    /// The invariants of a classifier, in the order of its `constraints` detail.
    ///
    /// Details of the OCL annotation that the `constraints` detail does not name follow in their
    /// own order. A detail named ``OCLAnnotation/unnamedInvariantKey`` is an unnamed invariant.
    ///
    /// - Parameter element: The classifier.
    /// - Returns: The invariants.
    public static func invariants(of element: some EModelElement) -> [OCLConstraintText] {
        let details = expressionDetails(of: element)
        var keys = constraintNames(of: element).filter { details[$0] != nil }
        for key in details.keys where !keys.contains(key) { keys.append(key) }
        return keys.compactMap { key in
            details[key].map { constraint(named: key == OCLAnnotation.unnamedInvariantKey ? nil : key, value: $0) }
        }
    }

    /// The preconditions of an operation, in order.
    ///
    /// - Parameter operation: The operation.
    /// - Returns: The preconditions.
    public static func preconditions(of operation: EOperation) -> [OCLConstraintText] {
        conditions(of: operation, prefix: OCLAnnotation.preconditionKey)
    }

    /// The postconditions of an operation, in order.
    ///
    /// - Parameter operation: The operation.
    /// - Returns: The postconditions.
    public static func postconditions(of operation: EOperation) -> [OCLConstraintText] {
        conditions(of: operation, prefix: OCLAnnotation.postconditionKey)
    }

    /// The body of an operation, if it has one.
    ///
    /// - Parameter operation: The operation.
    /// - Returns: The OCL expression of the body.
    public static func body(of operation: EOperation) -> String? {
        expressionDetails(of: operation)[OCLAnnotation.bodyKey]
    }

    /// The derivation of a structural feature, if it has one.
    ///
    /// - Parameter feature: The feature.
    /// - Returns: The OCL expression of the derivation.
    public static func derivation(of feature: some EModelElement) -> String? {
        expressionDetails(of: feature)[OCLAnnotation.derivationKey]
    }

    /// The initial value of a structural feature, if it has one.
    ///
    /// - Parameter feature: The feature.
    /// - Returns: The OCL expression of the initial value.
    public static func initial(of feature: some EModelElement) -> String? {
        expressionDetails(of: feature)[OCLAnnotation.initialKey]
    }

    /// The conditions of an operation whose keys start with a prefix.
    private static func conditions(of operation: EOperation, prefix: String) -> [OCLConstraintText] {
        let namedPrefix = prefix + OCLAnnotation.conditionNameSeparator
        return expressionDetails(of: operation).compactMap { key, value in
            if key == prefix { return constraint(named: nil, value: value) }
            guard key.hasPrefix(namedPrefix) else { return nil }
            return constraint(named: String(key.dropFirst(namedPrefix.count)), value: value)
        }
    }

    /// A constraint from a detail value, separating the message of the tuple form.
    ///
    /// - Parameters:
    ///   - name: The name of the constraint.
    ///   - value: The detail value.
    /// - Returns: The constraint.
    public static func constraint(named name: String?, value: String) -> OCLConstraintText {
        guard value.hasPrefix(OCLSyntax.tupleTypeName),
            let expression = OCLExpressionParser().parse(value).expression,
            case .call(let call) = expression.kind, call.name == statusPart, call.navigation == ".",
            call.arguments == nil, let source = call.source, case .tupleLiteral(let parts) = source.kind, parts.count == 2,
            let message = parts.first(where: { $0.name == messagePart })?.initialiser,
            let status = parts.first(where: { $0.name == statusPart })?.initialiser
        else {
            return OCLConstraintText(name: name, expression: value)
        }
        let bytes = Array(value.utf8)
        /// The text of an expression part.
        ///
        /// - Parameter part: The expression part.
        /// - Returns: The source text of the part.
        func text(_ part: OCLExpression) -> String {
            String(decoding: bytes[part.range.start.utf8Offset..<part.range.end.utf8Offset], as: UTF8.self)
        }
        return OCLConstraintText(name: name, expression: text(status), message: text(message))
    }
}
