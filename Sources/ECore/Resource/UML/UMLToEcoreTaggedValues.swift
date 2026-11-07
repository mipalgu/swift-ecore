//
// UMLToEcoreTaggedValues.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation

extension UMLToEcoreConverter {
    /// What a tagged value of the Ecore profile changes in a draft.
    enum TaggedValueEffect {
        /// The name of the element.
        case name
        /// The namespace prefix of a package.
        case nsPrefix
        /// The namespace URI of a package.
        case nsURI
        /// The instance class name of a classifier.
        case instanceClassName
        /// Whether a feature is transient.
        case transient
        /// Whether a feature is unsettable.
        case unsettable
        /// Whether a feature is volatile.
        case volatile
        /// Whether an attribute is an identifier.
        case iD
        /// Whether a reference resolves proxies.
        case resolveProxies
        /// The literal of an enumeration literal.
        case literal
        /// The extended metadata name of an element.
        case xmlName
        /// The extended metadata namespace of a feature.
        case xmlNamespace
        /// The extended metadata kind of a feature.
        case xmlFeatureKind
        /// The extended metadata content kind of a class.
        case xmlContentKind
        /// The suppressed visibility of a feature or operation.
        case visibility
        /// Annotations written as text.
        case annotations
        /// The key attributes of a reference.
        case keys
    }

    /// Applies or reports the tagged values of the Ecore profile of every converted element.
    func processTaggedValues() async {
        typealias Stereotype = UMLToEcore.Syntax.Stereotype
        typealias Tag = UMLToEcore.Syntax.Tag
        for (element, draft) in conversions {
            switch draft.kind {
            case .eClass, .eDataType:
                let isClass = draft.kind == .eClass
                guard let application = application(of: isClass ? Stereotype.eClass : Stereotype.eDataType, to: element)
                else { continue }
                await apply(application, to: draft, of: element, [
                    (isClass ? Tag.className : Tag.dataTypeName, .name),
                ] + (isClass ? [(Tag.xmlContentKind, .xmlContentKind)] : []) + [
                    (Tag.xmlName, .xmlName), (Tag.instanceClassName, .instanceClassName),
                    (Tag.annotations, .annotations),
                ])
            case .eEnum:
                guard let application = application(of: Stereotype.eEnum, to: element) else { continue }
                await apply(application, to: draft, of: element, [
                    (Tag.enumName, .name), (Tag.xmlName, .xmlName), (Tag.annotations, .annotations),
                ])
            case .literal:
                guard let application = application(of: Stereotype.eEnumLiteral, to: element) else { continue }
                await apply(application, to: draft, of: element, [
                    (Tag.enumLiteralName, .name), (Tag.annotations, .annotations), (Tag.literal, .literal),
                ])
            case .operation:
                guard let application = application(of: Stereotype.eOperation, to: element) else { continue }
                await apply(application, to: draft, of: element, [
                    (Tag.operationName, .name), (Tag.annotations, .annotations), (Tag.visibility, .visibility),
                ])
            case .package:
                guard let application = application(of: Stereotype.ePackage, to: element) else { continue }
                await apply(application, to: draft, of: element, [(Tag.packageName, .name), (Tag.nsPrefix, .nsPrefix)])
                if draft.nsPrefix.isEmpty {
                    await apply(application, to: draft, of: element, [(Tag.basePackage, .nsPrefix)])
                    if !draft.nsPrefix.isEmpty { draft.nsPrefix += "." + draft.name }
                }
                await apply(application, to: draft, of: element, [(Tag.nsURI, .nsURI), (Tag.annotations, .annotations)])
            case .parameter:
                guard let application = application(of: Stereotype.eParameter, to: element) else { continue }
                await apply(application, to: draft, of: element, [
                    (Tag.parameterName, .name), (Tag.annotations, .annotations),
                ])
            case .attribute, .reference:
                let isAttribute = draft.kind == .attribute
                guard let application = application(
                    of: isAttribute ? Stereotype.eAttribute : Stereotype.eReference, to: element)
                else { continue }
                let specific: [(String, TaggedValueEffect)] = isAttribute
                    ? [(Tag.attributeName, .name), (Tag.isID, .iD)]
                    : [(Tag.referenceName, .name), (Tag.isResolveProxies, .resolveProxies), (Tag.keys, .keys)]
                await apply(application, to: draft, of: element, specific + [
                    (Tag.isTransient, .transient), (Tag.isUnsettable, .unsettable), (Tag.isVolatile, .volatile),
                    (Tag.xmlName, .xmlName), (Tag.xmlNamespace, .xmlNamespace), (Tag.xmlFeatureKind, .xmlFeatureKind),
                    (Tag.visibility, .visibility), (Tag.annotations, .annotations),
                ])
            case .typeParameter:
                continue
            }
        }
    }

    /// Applies or reports the tagged values of a stereotype application, in order.
    ///
    /// - Parameters:
    ///   - application: The stereotype application.
    ///   - draft: The draft of the element.
    ///   - element: The UML element.
    ///   - tags: The tagged values to consider and what each changes.
    private func apply(
        _ application: StereotypeApplication, to draft: EcoreDraft, of element: EUUID,
        _ tags: [(String, TaggedValueEffect)]
    ) async {
        for (tag, effect) in tags {
            guard let value = application.values[tag] else { continue }
            let text = Self.text(of: value)
            report(options.ecoreTaggedValues, UMLToEcore.Diagnostic.ecoreTaggedValue,
                   "The Ecore tagged value '\(tag)' = '\(text)' of '\(draft.qualifiedName)'")
            guard options.ecoreTaggedValues == .process else { continue }
            await apply(effect, value: value, text: text, application: application, to: draft, of: element)
        }
    }

    /// Applies one tagged value of the Ecore profile to a draft.
    ///
    /// - Parameters:
    ///   - effect: What the tagged value changes.
    ///   - value: The value as read.
    ///   - text: The value as text.
    ///   - application: The stereotype application.
    ///   - draft: The draft of the element.
    ///   - element: The UML element.
    private func apply(
        _ effect: TaggedValueEffect, value: any EcoreValue, text: String, application: StereotypeApplication,
        to draft: EcoreDraft, of element: EUUID
    ) async {
        let flag = text.trimmingCharacters(in: .whitespaces) == "true"
        switch effect {
        case .name:
            if text != draft.name { draft.annotation(UMLToEcore.Syntax.umlAnnotationSource).details[UMLToEcore.Syntax.originalNameKey] = draft.name }
            setName(draft, text, validate: true)
        case .nsPrefix: draft.nsPrefix = text
        case .nsURI: draft.nsURI = text
        case .instanceClassName: draft.instanceClassName = text
        case .transient: draft.transient = flag
        case .unsettable: draft.unsettable = flag
        case .volatile: draft.volatile = flag
        case .iD: draft.iD = flag
        case .resolveProxies: draft.resolveProxies = flag
        case .literal: draft.literal = text
        case .xmlName:
            draft.annotation(AnnotationSource.extendedMetaData).details[AnnotationSource.ExtendedMetaDataKey.name] = text
        case .xmlNamespace:
            draft.annotation(AnnotationSource.extendedMetaData).details[AnnotationSource.ExtendedMetaDataKey.namespace] = text
        case .xmlFeatureKind:
            if let kind = UMLToEcore.Syntax.featureKinds[text] {
                draft.annotation(AnnotationSource.extendedMetaData).details[AnnotationSource.ExtendedMetaDataKey.kind] = kind
            }
        case .xmlContentKind:
            if let kind = UMLToEcore.Syntax.contentKinds[text] {
                draft.annotation(AnnotationSource.extendedMetaData).details[AnnotationSource.ExtendedMetaDataKey.kind] = kind
            }
        case .visibility:
            applyVisibility(text, to: draft)
        case .annotations:
            let texts = (value as? [any EcoreValue])?.map(Self.text(of:)) ?? [text]
            for annotationText in texts {
                guard let parsed = UMLToEcore.parseAnnotation(annotationText) else { continue }
                let annotation = draft.annotation(parsed.source)
                for (key, detail) in parsed.details { annotation.details[key] = detail }
            }
        case .keys:
            for key in await taggedReferences(application, UMLToEcore.Syntax.Tag.keys, of: element) {
                guard case .element(let property) = key,
                    let type = await reference(property, UMLToEcore.Syntax.Feature.type), !(await isEClass(type)),
                    let attribute = await doSwitch(property), attribute.kind == .attribute
                else { continue }
                draft.keys.append(attribute)
            }
        }
    }

    /// Suppresses the visibility of the accessors of a feature or of an operation as the
    /// `visibility` tagged value says.
    ///
    /// - Parameters:
    ///   - visibility: The visibility kind, such as `None` or `ReadOnly`.
    ///   - draft: The feature or operation.
    private func applyVisibility(_ visibility: String, to draft: EcoreDraft) {
        typealias Visibility = UMLToEcore.Syntax.Visibility
        typealias Key = AnnotationSource.GenModelKey
        func suppress(_ key: String) { draft.annotation(AnnotationSource.genModel).details[key] = "true" }
        if draft.kind == .operation {
            if visibility == Visibility.none { suppress(UMLToEcore.Syntax.suppressedVisibilityKey) }
            return
        }
        let changeable = draft.changeable
        let single = !draft.isMany
        switch visibility {
        case Visibility.none:
            suppress(Key.suppressedGetVisibility)
            if changeable && single { suppress(Key.suppressedSetVisibility) }
            if draft.unsettable {
                suppress(Key.suppressedIsSetVisibility)
                if changeable { suppress(Key.suppressedUnsetVisibility) }
            }
        case Visibility.readOnly:
            if single && changeable { suppress(Key.suppressedSetVisibility) }
            if draft.unsettable {
                suppress(Key.suppressedIsSetVisibility)
                if changeable { suppress(Key.suppressedUnsetVisibility) }
            }
        case Visibility.readWrite:
            if draft.unsettable {
                suppress(Key.suppressedIsSetVisibility)
                if changeable { suppress(Key.suppressedUnsetVisibility) }
            }
        case Visibility.readOnlyUnsettable:
            if single && changeable { suppress(Key.suppressedSetVisibility) }
            if draft.unsettable && changeable { suppress(Key.suppressedUnsetVisibility) }
        default:
            break
        }
    }
}
