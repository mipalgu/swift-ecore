//
// UMLNamespaces.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import Foundation

/// The namespace URIs under which UML models are written, and how they map onto Eclipse UML2.
///
/// UML models are exchanged under several namespace URIs: the Eclipse UML2 project changed
/// its namespace with each major release of its metamodel, and the Object Management Group
/// (OMG) publishes a namespace for each version of the UML specification. A UML model is
/// read with the bundled Eclipse UML2 5.x metamodel (see ``UMLMetamodel``) whichever of these
/// namespaces it uses, as Eclipse UML2 itself reads older and OMG documents.
///
/// ## Metamodel namespaces
///
/// | Namespace URI | Origin | Read as |
/// |---|---|---|
/// | `http://www.eclipse.org/uml2/5.0.0/UML` | Eclipse UML2 5.x | itself |
/// | `http://www.eclipse.org/uml2/4.0.0/UML` | Eclipse UML2 4.x | Eclipse UML2 5.x |
/// | `http://www.eclipse.org/uml2/3.0.0/UML` | Eclipse UML2 3.x | Eclipse UML2 5.x |
/// | `http://www.eclipse.org/uml2/2.1.0/UML` | Eclipse UML2 2.1 and 2.2 | Eclipse UML2 5.x |
/// | `http://www.eclipse.org/uml2/2.0.0/UML` | Eclipse UML2 2.0 | Eclipse UML2 5.x |
/// | `http://www.omg.org/spec/UML/20161101` | OMG UML 2.5.1 | Eclipse UML2 5.x |
/// | `http://www.omg.org/spec/UML/20131001` | OMG UML 2.5 | Eclipse UML2 5.x |
/// | `http://www.omg.org/spec/UML/20110701` | OMG UML 2.4.1 | Eclipse UML2 5.x |
/// | `http://www.omg.org/spec/UML/20100901` | OMG UML 2.4 | Eclipse UML2 5.x |
/// | `http://schema.omg.org/spec/UML/2.2` | OMG UML 2.2 | Eclipse UML2 5.x |
/// | `http://schema.omg.org/spec/UML/2.1.1` | OMG UML 2.1.1 | Eclipse UML2 5.x |
/// | `http://schema.omg.org/spec/UML/2.1` | OMG UML 2.1 | Eclipse UML2 5.x |
///
/// Older metamodels differ from Eclipse UML2 5.x in a few classes and features. A value of
/// a feature that the 5.x metamodel does not declare is kept under its name, as for any
/// document, so nothing is lost, but it is not typed by the metamodel.
///
/// ## Standard profile namespaces
///
/// The namespaces of the standard profile of each version map onto that of Eclipse UML2 5.x,
/// `http://www.eclipse.org/uml2/5.0.0/UML/Profile/Standard`: those of OMG UML 2.5 and 2.5.1
/// (`.../StandardProfile`), of OMG UML 2.1 to 2.4.1 (`.../StandardProfileL2` and
/// `.../StandardProfileL3`), of Eclipse UML2 4.x (`.../4.0.0/UML/Profile/L2` and `L3`), and
/// of Eclipse UML2 2.x and 3.x (`http://www.eclipse.org/uml2/schemas/Standard/1`).
///
/// ## Documents
///
/// References into the documents that the OMG publishes for UML 2.4 to 2.5.1 are read as
/// references into the corresponding Eclipse UML2 libraries:
///
/// | OMG document | Eclipse UML2 document |
/// |---|---|
/// | `http://www.omg.org/spec/UML/<version>/PrimitiveTypes.xmi` | `pathmap://UML_LIBRARIES/UMLPrimitiveTypes.library.uml` |
/// | `http://www.omg.org/spec/UML/<version>/UML.xmi` | `pathmap://UML_METAMODELS/UML.metamodel.uml` |
/// | `http://www.omg.org/spec/UML/<version>/StandardProfile.xmi` | `pathmap://UML_PROFILES/Standard.profile.uml` |
///
/// The fragments of these references, such as `String` or `Integer`, are kept unchanged.
public enum UMLNamespaces {
    /// The namespace URI of the Eclipse UML2 5.x metamodel.
    public static let uml = "http://www.eclipse.org/uml2/5.0.0/UML"

    /// The namespace URI of the primitive types of the Eclipse UML2 5.x metamodel.
    public static let types = "http://www.eclipse.org/uml2/5.0.0/Types"

    /// The namespace URI of the standard profile of Eclipse UML2 5.x.
    public static let standardProfile = "http://www.eclipse.org/uml2/5.0.0/UML/Profile/Standard"

    /// The namespace URI of the Ecore profile of Eclipse UML2 5.x.
    public static let ecoreProfile = "http://www.eclipse.org/uml2/schemas/Ecore/5"

    /// The source of the annotations with which Eclipse UML2 relates profiles and their
    /// Ecore definitions to model elements.
    public static let annotationSource = "http://www.eclipse.org/uml2/2.0.0/UML"

    /// The conventional file extension of UML models, without the leading dot.
    public static let fileExtension = "uml"

    /// The versions of the OMG UML specification that are published under `www.omg.org`,
    /// by the date in their namespace URIs.
    static let omgVersionDates = ["20100901", "20110701", "20131001", "20161101"]

    /// The older Eclipse UML2 metamodel namespaces whose documents are read as Eclipse UML2 5.x.
    public static let olderEclipseMetamodels = [
        "http://www.eclipse.org/uml2/4.0.0/UML",
        "http://www.eclipse.org/uml2/3.0.0/UML",
        "http://www.eclipse.org/uml2/2.1.0/UML",
        "http://www.eclipse.org/uml2/2.0.0/UML",
    ]

    /// The OMG UML metamodel namespaces whose documents are read as Eclipse UML2 5.x.
    public static let omgMetamodels =
        omgVersionDates.reversed().map { "http://www.omg.org/spec/UML/\($0)" } + [
            "http://schema.omg.org/spec/UML/2.2",
            "http://schema.omg.org/spec/UML/2.1.1",
            "http://schema.omg.org/spec/UML/2.1",
        ]

    /// Every namespace URI that is read as the Eclipse UML2 5.x metamodel, other than its own.
    public static var metamodelAliases: [String] { olderEclipseMetamodels + omgMetamodels }

    /// The namespace URIs of standard profiles that are read as the Eclipse UML2 5.x standard profile.
    public static let standardProfileAliases: [String] = {
        var aliases = omgVersionDates.filter { $0 >= "20131001" }.map {
            "http://www.omg.org/spec/UML/\($0)/StandardProfile"
        }
        let levelled = ["http://schema.omg.org/spec/UML/2.1", "http://schema.omg.org/spec/UML/2.1.1",
            "http://schema.omg.org/spec/UML/2.2"] + omgVersionDates.filter { $0 < "20131001" }.map {
                "http://www.omg.org/spec/UML/\($0)"
            }
        for base in levelled {
            aliases += [base + "/StandardProfileL2", base + "/StandardProfileL3"]
        }
        aliases += [
            "http://www.eclipse.org/uml2/4.0.0/UML/Profile/L2",
            "http://www.eclipse.org/uml2/4.0.0/UML/Profile/L3",
            "http://www.eclipse.org/uml2/schemas/Standard/1",
        ]
        return aliases
    }()

    /// The Eclipse UML2 libraries that stand for the documents the OMG publishes, by file name.
    static let omgDocuments: [String: String] = [
        "PrimitiveTypes.xmi": "pathmap://UML_LIBRARIES/UMLPrimitiveTypes.library.uml",
        "UML.xmi": "pathmap://UML_METAMODELS/UML.metamodel.uml",
        "StandardProfile.xmi": "pathmap://UML_PROFILES/Standard.profile.uml",
    ]

    /// The namespace URI of the Eclipse UML2 5.x package that stands for another namespace.
    ///
    /// - Parameter namespaceURI: A namespace URI as declared in a document.
    /// - Returns: ``uml`` for a metamodel alias, ``standardProfile`` for a standard profile
    ///   alias, or `nil` if the namespace is not one of the aliases.
    public static func eclipseNamespace(for namespaceURI: String) -> String? {
        if metamodelAliases.contains(namespaceURI) { return uml }
        if standardProfileAliases.contains(namespaceURI) { return standardProfile }
        return nil
    }

    /// The Eclipse UML2 document that stands for a document the OMG publishes.
    ///
    /// - Parameter documentURI: The URI of a document without a fragment.
    /// - Returns: The `pathmap:` URI of the Eclipse UML2 library, metamodel or profile, or
    ///   `nil` if the document is not one that the OMG publishes for UML 2.4 to 2.5.1.
    public static func eclipseDocument(for documentURI: String) -> String? {
        for date in omgVersionDates {
            let base = "http://www.omg.org/spec/UML/\(date)/"
            guard documentURI.hasPrefix(base) else { continue }
            return omgDocuments[String(documentURI.dropFirst(base.count))]
        }
        return nil
    }
}
