//
// DeepConstraintEvaluation.swift
// MultiLevel
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import ECore
public import EMFBase

/// What a ``DeepConstraintEvaluator`` evaluates: one constraint for one object, or once for a
/// level, with the views in which its body is evaluated.
public struct DeepConstraintContext: Sendable {
    /// The constraint.
    public let constraint: DeepConstraint

    /// The qualified name of the clabject or model that holds the constraint.
    public let holder: String

    /// The object of the deep view that `self` denotes, or `nil` for a model constraint.
    public let object: (any EObject)?

    /// The deep view of the level at which the constraint is evaluated.
    public let view: DeepLevelView

    /// The deep views of every level, which share one resource set, from the top level down.
    public let views: [DeepLevelView]

    /// Creates a context.
    ///
    /// - Parameters:
    ///   - constraint: The constraint.
    ///   - holder: The qualified name of its holder.
    ///   - object: The object that `self` denotes, or `nil`.
    ///   - view: The view of the level of evaluation.
    ///   - views: The views of every level.
    public init(
        constraint: DeepConstraint, holder: String, object: (any EObject)?, view: DeepLevelView, views: [DeepLevelView]
    ) {
        self.constraint = constraint
        self.holder = holder
        self.object = object
        self.view = view
        self.views = views
    }
}

/// Evaluates the bodies of deep constraints.
///
/// The MultiLevel module defines when and on what a constraint is evaluated; an evaluator,
/// such as the AQL evaluator of the swift-aql package, supplies the language. Bodies are
/// evaluated against deep level views, so that `self.price` reads the slot of a level-0
/// object and type names denote all their deep instances.
public protocol DeepConstraintEvaluator: Sendable {
    /// Evaluates a constraint.
    ///
    /// - Parameter context: The constraint, its `self` object and its views.
    /// - Returns: `true` if the constraint holds.
    /// - Throws: An error if the body cannot be evaluated, for example because it is not
    ///   valid in the language of the evaluator.
    func evaluate(_ context: DeepConstraintContext) async throws -> Bool
}

extension DeepModel {
    /// Checks the structure of the model and evaluates its constraints.
    ///
    /// - Parameter evaluator: The evaluator of constraint bodies, or `nil` to check the
    ///   structure only.
    /// - Returns: The structural problems followed by the violated and failing constraints.
    public func validate(evaluator: (any DeepConstraintEvaluator)? = nil) async -> [SourceDiagnostic] {
        let structural = validateStructure()
        guard let evaluator else { return structural }
        return structural + (await evaluateConstraints(evaluator: evaluator))
    }

    /// Evaluates the constraints of the model.
    ///
    /// A constraint of potency *p* held by a clabject at level *L* is evaluated on each deep
    /// instance at level *L* − *p* of that clabject (on the clabject itself if *p* is zero),
    /// so that subclabjects inherit it. A constraint held by a level model is evaluated once
    /// at level *L* − *p*. A constraint without an explicit potency takes that of its holder.
    ///
    /// - Parameters:
    ///   - level: The level whose evaluations are performed, or `nil` for every level.
    ///   - evaluator: The evaluator of constraint bodies.
    /// - Returns: A diagnostic for every violated constraint and for every constraint that
    ///   could not be evaluated.
    public func evaluateConstraints(atLevel level: Int? = nil, evaluator: any DeepConstraintEvaluator) async
        -> [SourceDiagnostic]
    {
        let resourceSet = ResourceSet()
        guard let views = try? await deepLevelViews(in: resourceSet) else { return [] }
        var viewsByLevel: [Int: DeepLevelView] = [:]
        for view in views { viewsByLevel[view.level] = view }
        let index = DeepIndex(self)
        var diagnostics: [SourceDiagnostic] = []

        func evaluate(_ constraint: DeepConstraint, holder: String, object: EUUID?, at target: Int) async {
            guard level == nil || level == target, let view = viewsByLevel[target] else { return }
            var subject: (any EObject)?
            if let object {
                subject = await view.resource.resolve(object)
                guard subject != nil else { return }
            }
            let context = DeepConstraintContext(
                constraint: constraint, holder: holder, object: subject, view: view, views: views)
            let on = object.map { " on '\(qualifiedName(of: $0, index: index))'" } ?? " at level \(target)"
            do {
                if try await !evaluator.evaluate(context) {
                    diagnostics.append(
                        SourceDiagnostic(
                            severity: .error, code: MultiLevelDiagnosticCode.constraintViolated,
                            message: "constraint '\(constraint.name)' of '\(holder)' is violated\(on)"))
                }
            } catch {
                diagnostics.append(
                    SourceDiagnostic(
                        severity: .error, code: MultiLevelDiagnosticCode.constraintError,
                        message: "constraint '\(constraint.name)' of '\(holder)' cannot be evaluated\(on): \(error)"))
            }
        }

        for (position, levelModel) in levels.enumerated() {
            let number = levelNumber(ofModelAt: position)
            let modelPotency = levelModel.potency ?? Potency(number)
            for constraint in levelModel.constraints {
                guard let potency = (constraint.potency ?? modelPotency).finiteValue else { continue }
                await evaluate(constraint, holder: levelModel.name, object: nil, at: number - potency)
            }
            for clabject in levelModel.clabjects {
                let holder = qualifiedName(of: clabject.id, index: index)
                for constraint in clabject.constraints {
                    guard let potency = (constraint.potency ?? index.potency(of: clabject.id))?.finiteValue else { continue }
                    let target = number - potency
                    let subjects = potency == 0 ? [clabject.id] : instances(of: clabject.id, atLevel: target).map(\.id)
                    for subject in subjects { await evaluate(constraint, holder: holder, object: subject, at: target) }
                }
            }
        }
        return diagnostics
    }

    /// The name of a clabject qualified by its level model.
    func qualifiedName(of id: EUUID, index: DeepIndex) -> String {
        guard let location = index.location[id] else { return id.uuidString }
        let level = levels[location.model]
        return "\(level.name).\(level.clabjects[location.position].name)"
    }
}
