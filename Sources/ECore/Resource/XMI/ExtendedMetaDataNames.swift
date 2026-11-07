//
// ExtendedMetaDataNames.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation

/// The XML names that the extended metadata of a metamodel gives its features.
///
/// A feature whose annotation with the source ``AnnotationSource/extendedMetaData`` has a
/// ``AnnotationSource/ExtendedMetaDataKey/name`` detail is written and read under that name
/// instead of its own, as EMF does. Eclipse UML2 relies on this: the containment
/// `Activity.ownedNode`, for example, is written as `node`, a name that the derived feature
/// `Activity.node` also has. A name given by extended metadata therefore takes precedence over
/// the name of a feature when a document is read.
///
/// The names of each class are computed once and cached.
struct ExtendedMetaDataNames: Sendable {
    /// The XML names given by extended metadata, by class identifier and then by XML name.
    private var featuresByXMLName: [EUUID: [String: String]] = [:]

    /// The XML name of a feature: its name in extended metadata, or else its own name.
    ///
    /// - Parameter feature: The structural feature.
    /// - Returns: The name under which the feature is written.
    static func xmlName(of feature: any EStructuralFeature) -> String {
        let annotations = (feature as? any EModelElement)?.eAnnotations ?? []
        let annotation = annotations.first { $0.source == AnnotationSource.extendedMetaData }
        guard let name = annotation?.details[AnnotationSource.ExtendedMetaDataKey.name], !name.isEmpty else {
            return feature.name
        }
        return name
    }

    /// The name of the feature that an XML attribute or element of an object denotes.
    ///
    /// - Parameters:
    ///   - xmlName: The name of the XML attribute or child element.
    ///   - eClass: The class of the object.
    /// - Returns: The name of the feature whose extended metadata gives it the XML name, or the
    ///   XML name itself if no feature is renamed to it.
    mutating func featureName(forXMLName xmlName: String, in eClass: EClass) -> String {
        if let names = featuresByXMLName[eClass.id] { return names[xmlName] ?? xmlName }
        var names: [String: String] = [:]
        for feature in eClass.allStructuralFeatures {
            let name = Self.xmlName(of: feature)
            if name != feature.name && names[name] == nil { names[name] = feature.name }
        }
        featuresByXMLName[eClass.id] = names
        return names[xmlName] ?? xmlName
    }
}
