//
// MetaDepthWriter.swift
// MultiLevel
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase
import Foundation

/// Writes multi-level models in the MetaDepth notation that ``MetaDepthReader`` reads.
///
/// The writer is canonical: models are written from the top level down, and within each
/// clabject its features precede its slots and its constraints. By default only declared
/// potencies are written, so that reading the text yields an equal model; with
/// ``Options/explicitPotencies`` every model, clabject and feature carries its effective
/// potency, as MetaDepth's own `dump` command writes them.
public enum MetaDepthWriter {
    /// How a model is written.
    public struct Options: Hashable, Sendable {
        /// Whether effective potencies are written where none is declared.
        public var explicitPotencies: Bool

        /// The text of one level of indentation.
        public var indentation: String

        /// Creates options.
        ///
        /// - Parameters:
        ///   - explicitPotencies: Whether effective potencies are written (default `false`).
        ///   - indentation: One level of indentation (default two spaces).
        public init(explicitPotencies: Bool = false, indentation: String = "  ") {
            self.explicitPotencies = explicitPotencies
            self.indentation = indentation
        }
    }

    /// Writes a deep model as MetaDepth text.
    ///
    /// - Parameters:
    ///   - model: The model.
    ///   - options: How to write the model (default options).
    /// - Returns: The text and the problems found, such as an expression that contains the
    ///   expression delimiter.
    public static func write(_ model: DeepModel, options: Options = Options()) -> (
        text: String, diagnostics: [SourceDiagnostic]
    ) {
        var writer = Writer(model: model, options: options)
        writer.writeModel()
        return (writer.output, writer.diagnostics)
    }

    /// The state of one writing pass.
    private struct Writer {
        /// The model being written.
        let model: DeepModel
        /// The index of the model, used to resolve identifiers and potencies.
        let index: DeepIndex
        /// How the model is written.
        let options: Options
        /// The text written so far.
        var output = ""
        /// The problems found so far.
        var diagnostics: [SourceDiagnostic] = []

        /// Creates a writer.
        ///
        /// - Parameters:
        ///   - model: The model to write.
        ///   - options: How to write the model.
        init(model: DeepModel, options: Options) {
            self.model = model
            self.index = DeepIndex(model)
            self.options = options
        }

        /// The indentation for a nesting depth.
        ///
        /// - Parameter depth: The number of levels of indentation.
        /// - Returns: The indentation text.
        func indent(_ depth: Int) -> String { String(repeating: options.indentation, count: depth) }

        /// Appends an indented line of text to the output.
        ///
        /// - Parameters:
        ///   - depth: The number of levels of indentation.
        ///   - text: The text of the line, without a line terminator.
        mutating func line(_ depth: Int, _ text: String) {
            output += indent(depth) + text + "\n"
        }

        /// Writes every level model, from the top down, separated by blank lines.
        mutating func writeModel() {
            for (position, level) in model.levels.enumerated() {
                if position > 0 { output += "\n" }
                writeLevel(level, at: position)
            }
        }

        /// Writes a level model: its header, its clabjects and its constraints.
        ///
        /// - Parameters:
        ///   - level: The level model to write.
        ///   - position: The position of the level model in the chain, from the top.
        mutating func writeLevel(_ level: LevelModel, at position: Int) {
            var header = level.isExtensible ? "" : MultiLevelSyntax.strictKeyword + " "
            let potency = level.potency ?? (options.explicitPotencies ? Potency(model.levelNumber(ofModelAt: position)) : nil)
            if let typeModel = level.typeModel {
                header += "\(typeModel) \(level.name)"
            } else {
                header += "\(MultiLevelSyntax.modelKeyword) \(level.name)"
            }
            if let potency { header += "\(MultiLevelSyntax.potencyMarker)\(potency)" }
            if position == 0, model.potencyVariant != .metaDepth { header += " \(model.potencyVariant.rawValue)" }
            line(0, header + " {")
            for (clabjectPosition, clabject) in level.clabjects.enumerated() {
                if clabjectPosition > 0 { output += "\n" }
                writeClabject(clabject)
            }
            if !level.constraints.isEmpty, !level.clabjects.isEmpty { output += "\n" }
            for constraint in level.constraints { writeConstraint(constraint, depth: 1) }
            line(0, "}")
        }

        /// The name of a clabject.
        ///
        /// - Parameter id: The identifier of the clabject.
        /// - Returns: The clabject's name, or the identifier's text if the clabject is not found.
        func name(of id: EUUID) -> String {
            index.clabject(id)?.name ?? id.uuidString
        }

        /// Writes a clabject: its header, features, slots and constraints.
        ///
        /// - Parameter clabject: The clabject to write.
        mutating func writeClabject(_ clabject: Clabject) {
            var header = clabject.isAbstract ? MultiLevelSyntax.abstractKeyword + " " : ""
            let linguistic = clabject.isEdge ? MultiLevelSyntax.edgeKeyword : MultiLevelSyntax.nodeKeyword
            header += "\(clabject.type.map(name(of:)) ?? linguistic) \(clabject.name)"
            let potency = clabject.potency ?? (options.explicitPotencies ? index.potency(of: clabject.id) : nil)
            if let potency {
                header += clabject.isLeap
                    ? "\(MultiLevelSyntax.potencyMarker)(\(potency))" : "\(MultiLevelSyntax.potencyMarker)\(potency)"
            }
            if let ends = clabject.ends {
                header += "(\(end(ends.source)), \(end(ends.target)))"
            }
            if !clabject.supertypes.isEmpty {
                header += " : " + clabject.supertypes.map(name(of:)).joined(separator: ", ")
            }
            let members = clabject.features.count + clabject.slots.count + clabject.constraints.count
            guard members > 0 else {
                line(1, header + " {}")
                return
            }
            line(1, header + " {")
            for feature in clabject.features { writeFeature(feature, of: clabject) }
            for slot in clabject.slots { writeSlot(slot, of: clabject) }
            for constraint in clabject.constraints { writeConstraint(constraint, depth: 2) }
            line(1, "}")
        }

        /// The text of one end of an edge.
        ///
        /// - Parameter end: The edge end.
        /// - Returns: The clabject name, followed by the reference name if the end has one.
        func end(_ end: EdgeEnd) -> String {
            name(of: end.clabject) + (end.feature.map { "\(MultiLevelSyntax.memberSeparator)\($0)" } ?? "")
        }

        /// Writes a feature declaration.
        ///
        /// - Parameters:
        ///   - feature: The feature to write.
        ///   - clabject: The clabject that owns the feature.
        mutating func writeFeature(_ feature: DeepFeature, of clabject: Clabject) {
            var text = feature.isDerived ? String(MultiLevelSyntax.derivedMarker) : ""
            text += feature.name
            let effective = index.durability(of: feature, ownedBy: clabject.id)
            if let potency = feature.potency ?? (options.explicitPotencies ? effective.durability : nil) {
                text += "\(MultiLevelSyntax.potencyMarker)\(potency)"
                if let mutability = feature.mutability {
                    text += "\(MultiLevelSyntax.mutabilitySeparator)\(mutability)"
                }
            }
            switch feature.type {
            case .data(let dataType): text += " : \(dataType)"
            case .reference(let target): text += " : \(name(of: target))"
            }
            if let targetPotency = feature.targetPotency { text += "\(MultiLevelSyntax.potencyMarker)\(targetPotency)" }
            if feature.lowerBound != 0 || feature.upperBound != 1 {
                text += "[" + multiplicity(feature) + "]"
            }
            if let derivation = feature.derivation {
                text += " = " + expression(derivation)
            } else if !feature.defaultValues.isEmpty {
                text += " = " + values(feature.defaultValues, many: feature.isMany)
            }
            var modifiers: [String] = []
            if let typeReference = feature.ontologicalType, typeReference != inferredType(of: feature, in: clabject) {
                modifiers.append(typeReference.name)
            }
            if feature.isContainment { modifiers.append(MultiLevelSyntax.containmentModifier) }
            if let level = feature.targetLevel {
                modifiers.append("\(MultiLevelSyntax.levelModifier)\(MultiLevelSyntax.modifierValueSeparator)\(level)")
            }
            if !modifiers.isEmpty { text += " {" + modifiers.joined(separator: ", ") + "}" }
            line(2, text + ";")
        }

        /// The feature that the reader takes a feature to refine when no modifier names one: a
        /// feature of the same name that is still a definition at the type.
        func inferredType(of feature: DeepFeature, in clabject: Clabject) -> FeatureReference? {
            guard let type = clabject.type else { return nil }
            return index.visibleFeatures(of: type).first { $0.feature.name == feature.name && $0.role.isDefinition }?
                .reference
        }

        /// The text of a feature's multiplicity bounds.
        ///
        /// - Parameter feature: The feature.
        /// - Returns: A single bound if the bounds are equal, the unbounded marker for any number, and otherwise a range.
        func multiplicity(_ feature: DeepFeature) -> String {
            let upper = feature.upperBound < 0 ? MultiLevelSyntax.unboundedPotency : String(feature.upperBound)
            if feature.lowerBound == 0, feature.upperBound < 0 { return MultiLevelSyntax.unboundedPotency }
            if feature.upperBound >= 0, feature.lowerBound == feature.upperBound { return upper }
            return "\(feature.lowerBound)\(MultiLevelSyntax.rangeSeparator)\(upper)"
        }

        /// Writes a slot assignment.
        ///
        /// - Parameters:
        ///   - slot: The slot to write.
        ///   - clabject: The clabject that owns the slot.
        mutating func writeSlot(_ slot: DeepSlot, of clabject: Clabject) {
            let feature = index.visibleFeatures(of: clabject.id).first { $0.feature.name == slot.feature }
            let many = feature?.feature.isMany ?? (slot.values.count != 1)
            line(2, "\(slot.feature) = \(values(slot.values, many: many));")
        }

        /// Writes a constraint declaration.
        ///
        /// - Parameters:
        ///   - constraint: The constraint to write.
        ///   - depth: The number of levels of indentation.
        mutating func writeConstraint(_ constraint: DeepConstraint, depth: Int) {
            var text = constraint.name
            if let potency = constraint.potency { text += "\(MultiLevelSyntax.potencyMarker)\(potency)" }
            line(depth, text + " : " + expression(constraint.body))
        }

        /// The text of an expression between its delimiters.
        ///
        /// An expression that contains the delimiter is reported as a syntax problem.
        ///
        /// - Parameter body: The expression.
        /// - Returns: The delimited expression.
        mutating func expression(_ body: String) -> String {
            if body.contains(MultiLevelSyntax.expressionDelimiter) {
                diagnostics.append(
                    SourceDiagnostic(
                        severity: .error, code: MultiLevelDiagnosticCode.syntax,
                        message: "an expression cannot contain '\(MultiLevelSyntax.expressionDelimiter)'"))
            }
            let delimiter = String(MultiLevelSyntax.expressionDelimiter)
            return delimiter + body + delimiter
        }

        /// The text of the values of a feature or slot.
        ///
        /// - Parameters:
        ///   - values: The values to write.
        ///   - many: Whether the feature is multi-valued.
        /// - Returns: A single value without brackets if the feature is single-valued, and otherwise a bracketed list.
        func values(_ values: [DeepValue], many: Bool) -> String {
            let rendered = values.map(value)
            if !many, rendered.count == 1 { return rendered[0] }
            return "[" + rendered.joined(separator: ", ") + "]"
        }

        /// The text of a single value.
        ///
        /// - Parameter value: The value to write.
        /// - Returns: The literal, quoted string or clabject name.
        func value(_ value: DeepValue) -> String {
            switch value {
            case .string(let text): return "\"" + escaped(text) + "\""
            case .integer(let number): return String(number)
            case .real(let number): return String(number)
            case .boolean(let flag): return flag ? MultiLevelSyntax.trueLiteral : MultiLevelSyntax.falseLiteral
            case .literal(let name): return name
            case .object(let id): return name(of: id)
            }
        }

        /// Escapes a string for writing between quotation marks.
        ///
        /// - Parameter text: The text to escape.
        /// - Returns: The text with quotation marks, backslashes and line breaks escaped.
        func escaped(_ text: String) -> String {
            var result = ""
            for character in text {
                switch character {
                case "\"": result += "\\\""
                case "\\": result += "\\\\"
                case "\n": result += "\\n"
                case "\t": result += "\\t"
                case "\r": result += "\\r"
                default: result.append(character)
                }
            }
            return result
        }
    }
}
