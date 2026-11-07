//
// UMLToEcoreConverter.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation

/// Converts the packages of UML models into Ecore packages, element by element, as the
/// Eclipse UML2 converter does.
///
/// The converter visits the packages it is given and everything they contain. Each kind of
/// UML element is converted when it is first visited, or earlier if an element that is being
/// converted needs it (as a type, an owner or an opposite), so that the order of the
/// resulting classifiers and features follows that of Eclipse UML2. Types of other documents
/// are read through the resource set and their packages converted too. Afterwards, the
/// options are applied in the order in which Eclipse UML2 applies them (see
/// ``processOptions()``).
final class UMLToEcoreConverter {
    /// What a reference of a UML element resolves to.
    enum Target {
        /// A UML element that the converter can read.
        case element(EUUID)
        /// A type of a library or metamodel that stands for an Ecore type.
        case library(EcoreDraftType)
        /// A reference that cannot be resolved, with the metaclass its document names, if any.
        case unresolved(metaclass: String?, description: String)
    }

    /// An application of a stereotype of the Ecore profile to a UML element.
    struct StereotypeApplication {
        /// The name of the stereotype, such as `EPackage`.
        let stereotype: String
        /// The tagged values that the application sets, by property name.
        let values: [String: any EcoreValue]
    }

    /// The options of the conversion.
    let options: UMLToEcore.Options

    /// The resource set through which references to other documents are resolved.
    let resourceSet: ResourceSet?

    /// The URI of the document being converted, for diagnostics.
    let document: String?

    /// What the conversion reported, in order.
    private(set) var diagnostics: [SourceDiagnostic] = []

    /// The drafts of the converted UML elements, by element.
    private(set) var converted: [EUUID: EcoreDraft] = [:]

    /// The converted UML elements in the order of their conversion.
    private(set) var conversionOrder: [EUUID] = []

    /// The resource that holds each UML element that the converter has met.
    private var owners: [EUUID: Resource] = [:]

    /// The resources whose objects the converter has indexed.
    private var indexedResources: Set<ObjectIdentifier> = []

    /// The names of each UML metaclass and its super classes, by the identifier of the metaclass.
    private var metaclassNames: [EUUID: Set<String>] = [:]

    /// The applications of the Ecore profile to each UML element.
    private var applications: [EUUID: [StereotypeApplication]] = [:]

    /// The association of each association end, as the associations list their member ends.
    private var associationOfEnd: [EUUID: EUUID] = [:]

    /// What each reference to another document resolves to.
    private var proxyTargets: [ResourceProxy: Target] = [:]

    /// The UML elements that have been visited.
    private var visited: Set<EUUID> = []

    /// The packages that the conversion was asked to convert.
    private var inputPackages: Set<EUUID> = []

    /// The options whose unsupported choices have been reported.
    private var reportedOptions: Set<String> = []

    /// Creates a converter.
    ///
    /// - Parameters:
    ///   - options: The options of the conversion.
    ///   - resourceSet: The resource set through which other documents are read.
    ///   - document: The URI of the document being converted, for diagnostics.
    init(options: UMLToEcore.Options, resourceSet: ResourceSet?, document: String?) {
        self.options = options
        self.resourceSet = resourceSet
        self.document = document
    }

    // MARK: - Entry

    /// Converts packages of a resource and applies the options.
    ///
    /// - Parameters:
    ///   - packages: The UML packages to convert, in order.
    ///   - resource: The resource that holds them.
    /// - Returns: The root packages of the conversion, in the order of their creation.
    func convert(_ packages: [EUUID], in resource: Resource) async -> [EcoreDraft] {
        await index(resource)
        inputPackages = Set(packages)
        for (name, choice) in options.unsupported where reportedOptions.insert(name).inserted {
            report(.warning, UMLToEcore.Diagnostic.unsupportedOption,
                   "The option \(name) is only implemented for the choice \(UMLToEcore.Choice.ignore.rawValue); "
                   + "\(choice.rawValue) is treated as \(UMLToEcore.Choice.ignore.rawValue)")
        }
        for package in packages { _ = await doSwitch(package) }
        await processOptions()
        var roots: [EcoreDraft] = []
        for element in conversionOrder {
            guard let draft = converted[element], draft.kind == .package else { continue }
            let root = draft.root
            if !roots.contains(where: { $0 === root }) { roots.append(root) }
        }
        return roots
    }

    /// The identifier that the document of a UML element gives it, if any.
    ///
    /// - Parameter element: The UML element.
    /// - Returns: Its `xmi:id`.
    func xmlIdentifier(of element: EUUID) async -> String? {
        await owners[element]?.xmlIdentifier(of: element)
    }

    // MARK: - Reporting

    /// Records a diagnostic.
    ///
    /// - Parameters:
    ///   - severity: The severity.
    ///   - code: The code, one of ``UMLToEcore/Diagnostic``.
    ///   - message: The message.
    func report(_ severity: DiagnosticSeverity, _ code: String, _ message: String) {
        diagnostics.append(SourceDiagnostic(severity: severity, code: code, message: message, document: document))
    }

    /// Records what an option did or found, according to its choice.
    ///
    /// - Parameters:
    ///   - choice: The choice of the option.
    ///   - code: The code of the diagnostic.
    ///   - message: What was found; the choice is appended to it.
    func report(_ choice: UMLToEcore.Choice, _ code: String, _ message: String) {
        switch choice {
        case .process: report(.information, code, message + " (processed)")
        case .report: report(.warning, code, message)
        case .discard: report(.warning, code, message + " (discarded)")
        case .ignore: break
        }
    }

    // MARK: - Reading UML elements

    /// Indexes the objects of a resource: their resource, the applications of the Ecore
    /// profile among its roots, and the member ends of its associations.
    ///
    /// - Parameter resource: The resource.
    private func index(_ resource: Resource) async {
        guard indexedResources.insert(ObjectIdentifier(resource)).inserted else { return }
        for object in await resource.getAllObjects() where owners[object.id] == nil {
            owners[object.id] = resource
        }
        for object in await resource.getAllObjects() where kinds(of: object).contains(UMLToEcore.Syntax.Metaclass.association) {
            for end in await referenceTargets(object.id, UMLToEcore.Syntax.Feature.memberEnd, in: resource) {
                if case .element(let id) = end, associationOfEnd[id] == nil { associationOfEnd[id] = object.id }
            }
        }
        for root in await resource.getRootObjects() where UMLToEcore.Syntax.Stereotype.all.contains(root.eClass.name) {
            var values: [String: any EcoreValue] = [:]
            var base: EUUID?
            for feature in await resource.getFeatureNames(objectId: root.id) {
                guard let value = await resource.eGet(objectId: root.id, feature: feature) else { continue }
                if feature.hasPrefix(UMLToEcore.Syntax.metaclassRolePrefix) {
                    base = await identifier(of: value, in: resource) ?? base
                } else {
                    values[feature] = value
                }
            }
            if let base {
                applications[base, default: []].append(StereotypeApplication(stereotype: root.eClass.name, values: values))
            }
        }
    }

    /// The UML element that a value of a stereotype application or a tagged value refers to.
    ///
    /// - Parameters:
    ///   - value: An identifier, or the `xmi:id` of an element as text.
    ///   - resource: The resource that holds the application.
    /// - Returns: The element, or `nil` if the value refers to none.
    private func identifier(of value: any EcoreValue, in resource: Resource) async -> EUUID? {
        if let id = value as? EUUID { return id }
        if let text = value as? String { return await resource.object(identifiedBy: text) }
        return nil
    }

    /// The names of the metaclass of an object and of all its super classes.
    ///
    /// - Parameter object: The object.
    /// - Returns: The names.
    private func kinds(of object: any EObject) -> Set<String> {
        guard let eClass = object.eClass as? EClass else { return [object.eClass.name] }
        if let names = metaclassNames[eClass.id] { return names }
        let names = Set([eClass.name] + eClass.allSuperTypes.map(\.name))
        metaclassNames[eClass.id] = names
        return names
    }

    /// The names of the metaclass of a UML element and of all its super classes.
    ///
    /// - Parameter element: The element.
    /// - Returns: The names, or none if the element cannot be read.
    func kinds(_ element: EUUID) async -> Set<String> {
        guard let object = await object(element) else { return [] }
        return kinds(of: object)
    }

    /// Whether a UML element is an instance of a metaclass or of one of its subclasses.
    ///
    /// - Parameters:
    ///   - element: The element.
    ///   - metaclass: The name of the metaclass.
    /// - Returns: `true` if the element is a kind of the metaclass.
    func isKind(_ element: EUUID?, _ metaclass: String) async -> Bool {
        guard let element else { return false }
        return await kinds(element).contains(metaclass)
    }

    /// The object of a UML element.
    ///
    /// - Parameter element: The element.
    /// - Returns: The object, or `nil` if the element is not known.
    func object(_ element: EUUID) async -> (any EObject)? {
        if let resource = owners[element] { return await resource.resolve(element) }
        guard let found = await resourceSet?.resolve(element) else { return nil }
        await index(found.resource)
        return found.object
    }

    /// A value of a UML element.
    ///
    /// - Parameters:
    ///   - element: The element.
    ///   - feature: The name of the feature.
    /// - Returns: The value, or `nil` if it is not set.
    func value(_ element: EUUID, _ feature: String) async -> (any EcoreValue)? {
        if owners[element] == nil { _ = await object(element) }
        return await owners[element]?.eGet(objectId: element, feature: feature)
    }

    /// A text value of a UML element.
    ///
    /// - Parameters:
    ///   - element: The element.
    ///   - feature: The name of the feature.
    /// - Returns: The text, or `nil` if the value is not set.
    func string(_ element: EUUID, _ feature: String) async -> String? {
        guard let value = await value(element, feature) else { return nil }
        return Self.text(of: value)
    }

    /// The text of a value.
    ///
    /// - Parameter value: The value.
    /// - Returns: The value as text.
    static func text(of value: any EcoreValue) -> String {
        if let text = value as? String { return text }
        if let flag = value as? Bool { return flag ? "true" : "false" }
        if let values = value as? [any EcoreValue] { return values.map(text(of:)).joined(separator: " ") }
        return String(describing: value)
    }

    /// A Boolean value of a UML element.
    ///
    /// - Parameters:
    ///   - element: The element.
    ///   - feature: The name of the feature.
    ///   - defaultValue: The value if the feature is not set.
    /// - Returns: The value.
    func bool(_ element: EUUID, _ feature: String, default defaultValue: Bool = false) async -> Bool {
        guard let value = await value(element, feature) else { return defaultValue }
        if let flag = value as? Bool { return flag }
        return Self.text(of: value).trimmingCharacters(in: .whitespaces) == "true"
    }

    /// The text values of a multi-valued feature of a UML element.
    ///
    /// - Parameters:
    ///   - element: The element.
    ///   - feature: The name of the feature.
    /// - Returns: The values in order.
    func strings(_ element: EUUID, _ feature: String) async -> [String] {
        guard let value = await value(element, feature) else { return [] }
        if let values = value as? [any EcoreValue] { return values.map(Self.text(of:)) }
        return [Self.text(of: value)]
    }

    /// The elements that a reference of a UML element refers to.
    ///
    /// - Parameters:
    ///   - element: The element.
    ///   - feature: The name of the reference.
    /// - Returns: What each value resolves to, in order.
    func references(_ element: EUUID, _ feature: String) async -> [Target] {
        if owners[element] == nil { _ = await object(element) }
        guard let resource = owners[element] else { return [] }
        return await referenceTargets(element, feature, in: resource)
    }

    /// The elements that a reference of a UML element of a known resource refers to.
    ///
    /// - Parameters:
    ///   - element: The element.
    ///   - feature: The name of the reference.
    ///   - resource: The resource that holds the element.
    /// - Returns: What each value resolves to, in order.
    private func referenceTargets(_ element: EUUID, _ feature: String, in resource: Resource) async -> [Target] {
        guard let value = await resource.eGet(objectId: element, feature: feature) else { return [] }
        let values: [any EcoreValue]
        if let list = value as? [EUUID] { values = list }
        else if let list = value as? [ResourceProxy] { values = list }
        else if let list = value as? [any EcoreValue] { values = list }
        else { values = [value] }
        var targets: [Target] = []
        for value in values {
            if let id = value as? EUUID {
                targets.append(.element(id))
            } else if let proxy = value as? ResourceProxy {
                targets.append(await resolve(proxy))
            } else if let text = value as? String {
                for word in text.split(whereSeparator: \.isWhitespace) {
                    if let id = await resource.object(identifiedBy: String(word)) { targets.append(.element(id)) }
                }
            }
        }
        return targets
    }

    /// The single element that a reference of a UML element refers to.
    ///
    /// - Parameters:
    ///   - element: The element.
    ///   - feature: The name of the reference.
    /// - Returns: What the first value resolves to, or `nil` if the reference is not set.
    func reference(_ element: EUUID, _ feature: String) async -> Target? {
        await references(element, feature).first
    }

    /// The single UML element that a reference refers to, if it resolves to one.
    ///
    /// - Parameters:
    ///   - element: The element.
    ///   - feature: The name of the reference.
    /// - Returns: The element, or `nil`.
    func referencedElement(_ element: EUUID, _ feature: String) async -> EUUID? {
        if case .element(let id)? = await reference(element, feature) { return id }
        return nil
    }

    /// The UML elements that a reference refers to, where they resolve to elements.
    ///
    /// - Parameters:
    ///   - element: The element.
    ///   - feature: The name of the reference.
    /// - Returns: The elements in order.
    func referencedElements(_ element: EUUID, _ feature: String) async -> [EUUID] {
        await references(element, feature).compactMap { if case .element(let id) = $0 { return id } else { return nil } }
    }

    /// Resolves a reference to another document.
    ///
    /// References into the primitive type libraries and metamodels of Eclipse UML2 stand for
    /// Ecore types (see ``libraryType(document:fragment:metaclass:)``). Other documents are
    /// read through the resource set.
    ///
    /// - Parameter proxy: The reference.
    /// - Returns: What the reference resolves to.
    func resolve(_ proxy: ResourceProxy) async -> Target {
        if let known = proxyTargets[proxy] { return known }
        let metaclass = proxy.qualifier.map { String($0.split(separator: ":").last ?? "") }
        let document = UMLNamespaces.eclipseDocument(for: proxy.uri) ?? proxy.uri
        let fragment = proxy.fragment.hasPrefix(String(CrossReferenceSyntax.fragmentSeparator))
            ? String(proxy.fragment.dropFirst()) : proxy.fragment
        var target: Target
        if let type = libraryType(document: document, fragment: fragment, metaclass: metaclass) {
            target = .library(type)
        } else if let resourceSet, let resource = await proxy.targetResource(in: resourceSet),
            let id = await proxy.resolve(in: resourceSet)
        {
            await index(resource)
            target = .element(id)
        } else {
            target = .unresolved(metaclass: metaclass, description: proxy.uri + "#" + fragment)
        }
        proxyTargets[proxy] = target
        return target
    }

    /// The Ecore type that a type of a primitive type library or metamodel of Eclipse UML2 stands for.
    ///
    /// - Parameters:
    ///   - document: The URI of the library or metamodel.
    ///   - fragment: The fragment of the type, which is its name.
    ///   - metaclass: The metaclass that the reference names, if any.
    /// - Returns: The Ecore type, or `nil` if the document is not a known library or metamodel.
    func libraryType(document: String, fragment: String, metaclass: String?) -> EcoreDraftType? {
        typealias Library = UMLToEcore.Syntax.Library
        let name = fragment.split(separator: "/").last.map(String.init) ?? fragment
        switch document {
        case Library.umlPrimitiveTypes:
            if options.primitiveTypes == .umlTypes {
                return .external(
                    reference: "ecore:EDataType " + UMLNamespaces.types + "#//" + name, isClass: false, name: name,
                    arguments: [])
            }
            return ecoreType(UMLToEcore.Syntax.umlPrimitiveTypes[name] ?? .eString)
        case Library.javaPrimitiveTypes:
            return UMLToEcore.Syntax.javaPrimitiveTypes[name].map(ecoreType)
        case Library.ecorePrimitiveTypes, Library.ecoreMetamodel, EcoreURI.ecoreNamespace.rawValue:
            return ecoreClassifier(named: name)
        case Library.xmlPrimitiveTypes:
            return xmlType(named: name)
        case Library.umlMetamodel, UMLNamespaces.uml:
            let isClass = metaclass.map { $0 == UMLToEcore.Syntax.Metaclass.class } ?? true
            let qualifier = isClass ? EcoreClassifier.eClass : EcoreClassifier.eDataType
            return .external(
                reference: CrossReferenceSyntax.ecorePrefix + ":" + qualifier.rawValue + " " + UMLNamespaces.uml + "#//"
                    + name, isClass: isClass, name: name, arguments: [])
        default:
            return nil
        }
    }

    /// The type that stands for an XML Schema primitive type.
    ///
    /// - Parameter name: The name of the XML Schema type.
    /// - Returns: The Ecore data type with the same values, `EString` for types without one.
    func xmlType(named name: String) -> EcoreDraftType {
        if let type = UMLToEcore.Syntax.xmlPrimitiveTypes[name] { return ecoreType(type) }
        report(.warning, UMLToEcore.Diagnostic.unsupported,
               "The XML primitive type '\(name)' has no Ecore counterpart and is converted to EString")
        return ecoreType(.eString)
    }

    /// The type that stands for an Ecore data type.
    ///
    /// - Parameter type: The Ecore data type.
    /// - Returns: The reference to the data type.
    func ecoreType(_ type: EcoreDataType) -> EcoreDraftType {
        .external(reference: EcoreURI.ecoreDataTypePrefix.rawValue + type.rawValue, isClass: false, name: type.rawValue,
                  arguments: [])
    }

    /// The type that stands for a classifier of the Ecore metamodel.
    ///
    /// - Parameter name: The name of the classifier.
    /// - Returns: The reference to the classifier, or `nil` if Ecore has no classifier of that name.
    func ecoreClassifier(named name: String) -> EcoreDraftType? {
        guard let classifier = EcorePackage.classifier(named: name) else {
            return EcoreDataType(rawValue: name).map(ecoreType)
        }
        if classifier is EClass {
            return .external(reference: EcoreURI.ecoreClassPrefix.rawValue + name, isClass: true, name: name, arguments: [])
        }
        return .external(reference: EcoreURI.ecoreDataTypePrefix.rawValue + name, isClass: false, name: name, arguments: [])
    }

    /// The UML element that contains another.
    ///
    /// - Parameter element: The element.
    /// - Returns: Its container, or `nil` for a root.
    func owner(of element: EUUID) async -> EUUID? {
        guard let resource = owners[element], let object = await resource.resolve(element) else { return nil }
        return await resource.eContainer(of: object)?.id
    }

    /// The UML elements that an element contains, in the order of its containment features.
    ///
    /// - Parameter element: The element.
    /// - Returns: The contained elements.
    func contents(of element: EUUID) async -> [EUUID] {
        guard let resource = owners[element], let object = await resource.resolve(element) else { return [] }
        let children = await resource.eContents(of: object)
        for child in children where owners[child.id] == nil { owners[child.id] = resource }
        return children.map(\.id)
    }

    /// The nearest package that contains a UML element, or the element itself if it is a package.
    ///
    /// - Parameter element: The element.
    /// - Returns: The package, or `nil` if no package contains the element.
    func nearestPackage(of element: EUUID) async -> EUUID? {
        var current: EUUID? = element
        while let candidate = current {
            if await isKind(candidate, UMLToEcore.Syntax.Metaclass.package) { return candidate }
            current = await owner(of: candidate)
        }
        return nil
    }

    /// The applications of a stereotype of the Ecore profile to a UML element.
    ///
    /// - Parameters:
    ///   - element: The element.
    ///   - stereotype: The name of the stereotype.
    /// - Returns: The first application of that stereotype, or `nil`.
    func application(of stereotype: String, to element: EUUID) -> StereotypeApplication? {
        applications[element]?.first { $0.stereotype == stereotype }
    }

    // MARK: - Dispatch

    /// Converts a UML element if it has not been converted yet.
    ///
    /// The element is converted as the most specific of the conversions of its metaclass
    /// that applies, as the Eclipse UML2 converter switches on the metaclass.
    ///
    /// - Parameter element: The element.
    /// - Returns: The draft of the element, or `nil` if it does not become an Ecore element.
    @discardableResult
    func doSwitch(_ element: EUUID) async -> EcoreDraft? {
        if let draft = converted[element] { return draft }
        guard visited.insert(element).inserted else { return converted[element] }
        typealias Metaclass = UMLToEcore.Syntax.Metaclass
        let kinds = await kinds(element)
        if kinds.contains(Metaclass.package) {
            await convertPackage(element)
        } else if kinds.contains(Metaclass.enumeration) {
            await convertEnumeration(element)
        } else if kinds.contains(Metaclass.primitiveType) {
            await convertPrimitiveType(element)
        } else if kinds.contains(Metaclass.dataType) || kinds.contains(Metaclass.interface)
            || kinds.contains(Metaclass.class)
        {
            await convertClass(element, kinds: kinds)
        } else if kinds.contains(Metaclass.enumerationLiteral) {
            await convertLiteral(element)
        } else if kinds.contains(Metaclass.property) {
            await convertProperty(element)
        } else if kinds.contains(Metaclass.parameter) {
            await convertParameter(element)
        } else if kinds.contains(Metaclass.operation) {
            await convertOperation(element)
        } else if kinds.contains(Metaclass.generalization) {
            await convertGeneralization(element)
        } else if kinds.contains(Metaclass.interfaceRealization) {
            await convertRealization(element)
        } else if kinds.contains(Metaclass.comment) {
            await convertComment(element)
        } else if kinds.contains(Metaclass.constraint) {
            await convertConstraint(element)
        } else if kinds.contains(Metaclass.templateSignature) || kinds.contains(Metaclass.templateParameter) {
            await traverse(element)
        } else if kinds.contains(Metaclass.templateBinding) {
            report(.warning, UMLToEcore.Diagnostic.unsupported,
                   "The template binding of '\(await qualifiedName(of: await owner(of: element)))' is converted "
                   + "as a class without type arguments")
        } else if kinds.contains(Metaclass.association) {
            await convertAssociation(element)
        }
        if converted[element] == nil, kinds.contains(Metaclass.parameterableElement) {
            await convertTypeParameter(element)
        }
        return converted[element]
    }

    /// Converts the contents of a UML element.
    ///
    /// - Parameter element: The element.
    func traverse(_ element: EUUID) async {
        for child in await contents(of: element) { await doSwitch(child) }
    }

    /// Records the draft of a UML element.
    ///
    /// - Parameters:
    ///   - element: The element.
    ///   - draft: Its draft.
    func record(_ element: EUUID, _ draft: EcoreDraft) {
        converted[element] = draft
        conversionOrder.append(element)
    }

    /// The qualified name of a UML element, for messages.
    ///
    /// - Parameter element: The element.
    /// - Returns: The names of the element and its named containers, joined by `::`.
    func qualifiedName(of element: EUUID?) async -> String {
        var names: [String] = []
        var current = element
        while let candidate = current {
            if let name = await string(candidate, UMLToEcore.Syntax.Feature.name), !name.isEmpty {
                names.insert(name, at: 0)
            }
            current = await owner(of: candidate)
        }
        return names.joined(separator: UMLToEcore.Syntax.qualifiedNameSeparator)
    }

    // MARK: - Names

    /// Names a draft after a UML element, qualifying the name of a nested classifier by the
    /// name of the classifier that contains it.
    ///
    /// - Parameters:
    ///   - draft: The draft.
    ///   - element: The UML element.
    func setName(_ draft: EcoreDraft, of element: EUUID) async {
        setName(draft, await string(element, UMLToEcore.Syntax.Feature.name), validate: true)
        guard await isKind(element, UMLToEcore.Syntax.Metaclass.classifier), let namespace = await owner(of: element),
            await isKind(namespace, UMLToEcore.Syntax.Metaclass.classifier)
        else { return }
        let qualifier = UMLToEcore.validIdentifier(await string(namespace, UMLToEcore.Syntax.Feature.name) ?? "")
        let name = draft.name
        let prefix = UMLToEcore.Syntax.metaclassRolePrefix
        draft.name = name.hasPrefix(prefix)
            ? prefix + qualifier + String(UMLToEcore.wordSeparator) + name.dropFirst(prefix.count)
            : qualifier + String(UMLToEcore.wordSeparator) + name
        recordOriginalName(draft, name)
    }

    /// Names a draft, converting the name into camel case and into a valid identifier as the options say.
    ///
    /// - Parameters:
    ///   - draft: The draft.
    ///   - name: The UML name.
    ///   - validate: Whether the name is made a valid identifier.
    func setName(_ draft: EcoreDraft, _ name: String?, validate: Bool) {
        var ecoreName = name ?? ""
        if let name, !name.isEmpty, options.camelCaseNames != .ignore {
            let camel = UMLToEcore.camelCase(name, capitalised: draft.kind.isClassifier || draft.kind == .typeParameter)
            if options.camelCaseNames == .process { ecoreName = camel }
            if camel != name {
                report(options.camelCaseNames, UMLToEcore.Diagnostic.camelCaseName,
                       "The name '\(name)' is not in camel case ('\(camel)')")
            }
        }
        if validate { ecoreName = UMLToEcore.validIdentifier(ecoreName) }
        if let name, ecoreName != name { recordOriginalName(draft, name) }
        draft.name = ecoreName
    }

    /// Records the original name of a renamed draft, unless one is recorded already.
    ///
    /// - Parameters:
    ///   - draft: The draft.
    ///   - name: The original name.
    func recordOriginalName(_ draft: EcoreDraft, _ name: String) {
        let annotation = draft.annotation(UMLToEcore.Syntax.umlAnnotationSource)
        if annotation.details[UMLToEcore.Syntax.originalNameKey]?.isEmpty ?? true {
            annotation.details[UMLToEcore.Syntax.originalNameKey] = name
        }
    }

    // MARK: - Packages and classifiers

    /// Converts a package into an `EPackage`.
    ///
    /// A package that the conversion was not asked for becomes a subpackage of the package
    /// that contains it. Its namespace prefix is that of its super package, a dot and its
    /// name; its namespace URI is the URI of the package or else derived from the prefix.
    ///
    /// - Parameter element: The package.
    private func convertPackage(_ element: EUUID) async {
        let draft = EcoreDraft(.package, source: element)
        record(element, draft)
        if !inputPackages.contains(element), let nesting = await owner(of: element),
            await isKind(nesting, UMLToEcore.Syntax.Metaclass.package), let parent = await doSwitch(nesting),
            parent.kind == .package
        {
            parent.subpackages.append(draft)
            draft.container = parent
        }
        await setName(draft, of: element)
        draft.nsPrefix = (draft.container.map { $0.nsPrefix + "." } ?? "") + draft.name
        if let uri = await string(element, UMLToEcore.Syntax.Feature.uri), !uri.isEmpty {
            draft.nsURI = uri
        } else {
            draft.nsURI = UMLToEcore.Syntax.derivedNamespacePrefix + draft.nsPrefix.replacingOccurrences(of: ".", with: "/")
                + UMLToEcore.Syntax.derivedNamespaceSuffix
        }
        await traverse(element)
    }

    /// Adds a classifier draft to the draft of the nearest package of its UML element.
    ///
    /// - Parameters:
    ///   - draft: The classifier draft.
    ///   - element: The UML classifier.
    /// - Returns: `false` if the classifier is in no package.
    private func addToPackage(_ draft: EcoreDraft, of element: EUUID) async -> Bool {
        guard let packageElement = await nearestPackage(of: element) else { return false }
        record(element, draft)
        guard let package = await doSwitch(packageElement) else { return true }
        package.classifiers.append(draft)
        draft.container = package
        return true
    }

    /// Whether a UML element is the parametered element of a template parameter.
    ///
    /// - Parameter element: The element.
    /// - Returns: `true` if it stands for a template parameter.
    private func isTemplateParameter(_ element: EUUID) async -> Bool {
        if await value(element, UMLToEcore.Syntax.Feature.templateParameter) != nil { return true }
        return await isKind(await owner(of: element), UMLToEcore.Syntax.Metaclass.templateParameter)
    }

    /// Whether a classifier stands for a generic type: the `EGenericType` stereotype of the
    /// Ecore profile is applied to it and tagged values are not ignored.
    ///
    /// Such a classifier does not become a classifier of its own; where it is used as a type,
    /// it stands for the template that it binds, with the actual parameters as type arguments.
    ///
    /// - Parameter element: The classifier.
    /// - Returns: `true` if the classifier stands for a generic type.
    func isEGenericType(_ element: EUUID) -> Bool {
        options.ecoreTaggedValues != .ignore
            && application(of: UMLToEcore.Syntax.Stereotype.eGenericType, to: element) != nil
    }

    /// Converts a class, an interface or a data type into an `EClass`.
    ///
    /// - Parameters:
    ///   - element: The classifier.
    ///   - kinds: The names of its metaclass and super classes.
    private func convertClass(_ element: EUUID, kinds: Set<String>) async {
        guard !isEGenericType(element), !(await isTemplateParameter(element)) else { return }
        let draft = EcoreDraft(.eClass, source: element)
        guard await addToPackage(draft, of: element) else { return }
        await setName(draft, of: element)
        if kinds.contains(UMLToEcore.Syntax.Metaclass.interface) {
            draft.isAbstract = true
            draft.isInterface = true
        } else if kinds.contains(UMLToEcore.Syntax.Metaclass.class) {
            draft.isAbstract = await bool(element, UMLToEcore.Syntax.Feature.isAbstract)
        }
        await traverse(element)
    }

    /// Converts an enumeration into an `EEnum`, with a nullable data type if the options ask for one.
    ///
    /// - Parameter element: The enumeration.
    private func convertEnumeration(_ element: EUUID) async {
        let draft = EcoreDraft(.eEnum, source: element)
        guard await addToPackage(draft, of: element) else { return }
        await setName(draft, of: element)
        if options.nullableEnumAttributes == .process, let package = draft.container {
            let optional = EcoreDraft(.eDataType)
            optional.name = draft.name + UMLToEcore.Syntax.optionalEnumSuffix
            optional.instanceClassName = UMLToEcore.Syntax.enumeratorTypeName
            optional.annotation(AnnotationSource.extendedMetaData).details[UMLToEcore.Syntax.baseTypeKey] = draft.name
            optional.container = package
            package.classifiers.append(optional)
            nullableTypes[ObjectIdentifier(draft)] = optional
        }
        await traverse(element)
    }

    /// The nullable data types of the enumerations, by enumeration draft.
    var nullableTypes: [ObjectIdentifier: EcoreDraft] = [:]

    /// Converts a primitive type into an `EDataType` whose instance class name is its name.
    ///
    /// - Parameter element: The primitive type.
    private func convertPrimitiveType(_ element: EUUID) async {
        guard !isEGenericType(element), !(await isTemplateParameter(element)) else { return }
        let draft = EcoreDraft(.eDataType, source: element)
        guard await addToPackage(draft, of: element) else { return }
        await setName(draft, of: element)
        draft.instanceClassName = draft.name
        await traverse(element)
    }

    /// Converts an enumeration literal into an `EEnumLiteral`.
    ///
    /// Its value is its position among the literals, or the integer value of its specification.
    ///
    /// - Parameter element: The literal.
    private func convertLiteral(_ element: EUUID) async {
        guard let enumeration = await owner(of: element),
            await isKind(enumeration, UMLToEcore.Syntax.Metaclass.enumeration)
        else { return }
        let draft = EcoreDraft(.literal, source: element)
        record(element, draft)
        guard let eEnum = await doSwitch(enumeration), eEnum.kind == .eEnum else { return }
        eEnum.literals.append(draft)
        draft.container = eEnum
        await setName(draft, of: element)
        var value = await referencedElements(enumeration, UMLToEcore.Syntax.Feature.ownedLiteral)
            .firstIndex(of: element) ?? 0
        if let specification = await referencedElement(element, UMLToEcore.Syntax.Feature.specification) {
            value = await integerValue(of: specification)
        }
        draft.value = value
        await traverse(element)
    }

    /// Converts a generalization into a super type of the class of its specific classifier,
    /// or into the base type of a data type.
    ///
    /// - Parameter element: The generalization.
    private func convertGeneralization(_ element: EUUID) async {
        guard let specific = await owner(of: element), let specificDraft = await doSwitch(specific),
            let general = await reference(element, UMLToEcore.Syntax.Feature.general)
        else { return }
        if specificDraft.kind == .eClass {
            guard let type = await genericType(of: general), type.isClass else { return }
            if case .classifier(let generalDraft, _) = type {
                guard !specificDraft.isSuperType(of: generalDraft), !generalDraft.isSuperType(of: specificDraft) else {
                    return
                }
            } else if specificDraft.superTypes.contains(where: { $0.isSame(as: type) }) {
                return
            }
            specificDraft.superTypes.append(type)
        } else if specificDraft.kind == .eDataType, case .element(let generalElement) = general,
            let generalDraft = await doSwitch(generalElement), generalDraft.kind == .eDataType
        {
            let baseType = generalDraft.package === specificDraft.package
                ? generalDraft.name : generalDraft.package.map { $0.nsURI + "#" + generalDraft.name } ?? generalDraft.name
            specificDraft.annotation(AnnotationSource.extendedMetaData).details[UMLToEcore.Syntax.baseTypeKey] = baseType
        }
    }

    /// Converts an interface realization into a super type of the implementing class.
    ///
    /// - Parameter element: The interface realization.
    private func convertRealization(_ element: EUUID) async {
        guard let implementing = await owner(of: element), let implementingDraft = await doSwitch(implementing),
            implementingDraft.kind == .eClass,
            let contract = await reference(element, UMLToEcore.Syntax.Feature.contract),
            let type = await genericType(of: contract), type.isClass
        else { return }
        if case .classifier(let contractDraft, _) = type {
            guard !implementingDraft.isSuperType(of: contractDraft) else { return }
        } else if implementingDraft.superTypes.contains(where: { $0.isSame(as: type) }) {
            return
        }
        implementingDraft.superTypes.append(type)
    }

    // MARK: - Types

    /// Whether a namespace becomes an `EClass`: a class, a structured data type or an interface.
    ///
    /// - Parameter element: The namespace, or `nil`.
    /// - Returns: `true` if the namespace becomes a class.
    func isEClass(_ element: EUUID?) async -> Bool {
        guard let element else { return false }
        return Self.isEClass(kinds: await kinds(element))
    }

    /// Whether a metaclass becomes an `EClass`.
    ///
    /// - Parameter kinds: The names of the metaclass and its super classes.
    /// - Returns: `false` for enumerations, primitive types and other namespaces.
    static func isEClass(kinds: Set<String>) -> Bool {
        typealias Metaclass = UMLToEcore.Syntax.Metaclass
        if kinds.contains(Metaclass.enumeration) || kinds.contains(Metaclass.primitiveType) { return false }
        return kinds.contains(Metaclass.dataType) || kinds.contains(Metaclass.class)
            || kinds.contains(Metaclass.interface)
    }

    /// Whether a type becomes an `EClass`, for a type that may not resolve to a UML element.
    ///
    /// - Parameter target: The type.
    /// - Returns: `true` if the type is or stands for a class.
    func isEClass(_ target: Target) async -> Bool {
        switch target {
        case .element(let element): return await isEClass(element)
        case .library(let type): return type.isClass
        case .unresolved(let metaclass, _):
            return metaclass.map { Self.isEClass(kinds: [$0]) } ?? false
        }
    }

    /// The Ecore type of a UML type.
    ///
    /// Primitive types of the Java, Ecore and XML primitive type libraries become Ecore data
    /// types by their qualified names; other classifiers become their drafts, and classifiers
    /// that stand for template parameters become those type parameters.
    ///
    /// - Parameter target: The type.
    /// - Returns: The Ecore type, or `nil` if the type cannot be converted.
    func genericType(of target: Target) async -> EcoreDraftType? {
        switch target {
        case .library(let type):
            return type
        case .unresolved(_, let description):
            report(.warning, UMLToEcore.Diagnostic.unsupported, "The type '\(description)' cannot be resolved")
            return nil
        case .element(let element):
            guard await isKind(element, UMLToEcore.Syntax.Metaclass.classifier) else { return nil }
            if await isKind(element, UMLToEcore.Syntax.Metaclass.primitiveType),
                let type = await qualifiedLibraryType(element)
            {
                return type
            }
            if let type = await wellKnownType(element) { return type }
            if let draft = await doSwitch(element) {
                if draft.kind.isClassifier { return .classifier(draft, arguments: []) }
                if draft.kind == .typeParameter { return .typeParameter(draft) }
                return nil
            }
            return isEGenericType(element) ? await boundType(element) : nil
        }
    }

    /// The type that a classifier with the `EGenericType` stereotype stands for: the template
    /// that it binds, with the actual parameters (or the defaults of the formal ones) as type arguments.
    ///
    /// - Parameter element: The classifier.
    /// - Returns: The generic type, or `nil` if the classifier binds no template that can be converted.
    private func boundType(_ element: EUUID) async -> EcoreDraftType? {
        typealias Feature = UMLToEcore.Syntax.Feature
        typealias Metaclass = UMLToEcore.Syntax.Metaclass
        for binding in await contents(of: element) where await isKind(binding, Metaclass.templateBinding) {
            guard case .element(let signature)? = await reference(binding, Feature.signature),
                let template = await owner(of: signature)
            else { continue }
            var arguments: [EcoreDraftType] = []
            for substitution in await contents(of: binding)
            where await isKind(substitution, Metaclass.templateParameterSubstitution) {
                var actual = await reference(substitution, Feature.actual)
                if actual == nil, let formal = await referencedElement(substitution, Feature.formal) {
                    actual = await reference(formal, Feature.default)
                }
                if let actual, let argument = await genericType(of: actual) { arguments.append(argument) }
            }
            switch await genericType(of: .element(template)) {
            case .classifier(let classifier, _)?: return .classifier(classifier, arguments: arguments)
            case .external(let reference, let isClass, let name, _)?:
                return .external(reference: reference, isClass: isClass, name: name, arguments: arguments)
            default: continue
            }
        }
        report(.warning, UMLToEcore.Diagnostic.unsupported,
               "The generic type '\(await qualifiedName(of: element))' binds no template that can be converted")
        return nil
    }

    /// The type of a well-known metamodel that a classifier of a UML model of that metamodel stands for.
    ///
    /// A UML model whose root package has the namespace URI of Ecore, of the UML metamodel or
    /// of the UML primitive types (as its `URI` or as the `nsURI` of the Ecore profile) describes
    /// a metamodel that is available natively, so its classifiers stand for those of the native
    /// metamodel instead of being converted, as Eclipse UML2 refers to the generated packages.
    /// The packages that the conversion was asked to convert are always converted.
    ///
    /// - Parameter element: The classifier.
    /// - Returns: The type of the native metamodel, or `nil` if the classifier is not of a well-known metamodel.
    private func wellKnownType(_ element: EUUID) async -> EcoreDraftType? {
        guard let name = await string(element, UMLToEcore.Syntax.Feature.name) else { return nil }
        var root = await nearestPackage(of: element)
        while let current = root, let parent = await owner(of: current), let package = await nearestPackage(of: parent) {
            root = package
        }
        guard let root, !inputPackages.contains(root) else { return nil }
        var namespace = await string(root, UMLToEcore.Syntax.Feature.uri)
        if let application = application(of: UMLToEcore.Syntax.Stereotype.ePackage, to: root),
            let value = application.values[UMLToEcore.Syntax.Tag.nsURI]
        {
            namespace = Self.text(of: value)
        }
        typealias Metaclass = UMLToEcore.Syntax.Metaclass
        switch namespace {
        case EcoreURI.ecoreNamespace.rawValue?:
            return ecoreClassifier(named: name)
        case UMLNamespaces.types?:
            if options.primitiveTypes == .ecore { return UMLToEcore.Syntax.umlPrimitiveTypes[name].map(ecoreType) }
            return .external(
                reference: CrossReferenceSyntax.ecorePrefix + ":" + EcoreClassifier.eDataType.rawValue + " "
                    + UMLNamespaces.types + "#//" + name, isClass: false, name: name, arguments: [])
        case UMLNamespaces.uml?:
            let kinds = await kinds(element)
            let isClass = Self.isEClass(kinds: kinds)
            let qualifier: EcoreClassifier = isClass ? .eClass : kinds.contains(Metaclass.enumeration) ? .eEnum : .eDataType
            return .external(
                reference: CrossReferenceSyntax.ecorePrefix + ":" + qualifier.rawValue + " " + UMLNamespaces.uml + "#//"
                    + name, isClass: isClass, name: name, arguments: [])
        default:
            return nil
        }
    }

    /// The Ecore type that a primitive type stands for by its qualified name, as Eclipse UML2
    /// recognises the types of its Java, Ecore and XML primitive type libraries.
    ///
    /// - Parameter element: The primitive type.
    /// - Returns: The Ecore type, or `nil` if the type is not one of those libraries.
    private func qualifiedLibraryType(_ element: EUUID) async -> EcoreDraftType? {
        guard let name = await string(element, UMLToEcore.Syntax.Feature.name),
            let package = await owner(of: element), await owner(of: package) == nil,
            let model = await string(package, UMLToEcore.Syntax.Feature.name)
        else { return nil }
        typealias LibraryModel = UMLToEcore.Syntax.LibraryModel
        switch model {
        case LibraryModel.javaPrimitiveTypes: return UMLToEcore.Syntax.javaPrimitiveTypes[name].map(ecoreType)
        case LibraryModel.ecorePrimitiveTypes: return ecoreClassifier(named: name)
        case LibraryModel.xmlPrimitiveTypes: return xmlType(named: name)
        default: return nil
        }
    }

    /// The Ecore type of the type of a typed UML element.
    ///
    /// - Parameter element: The typed element.
    /// - Returns: The type and what the reference resolved to, or `nil` if the element has no type.
    func type(of element: EUUID) async -> (type: EcoreDraftType?, target: Target)? {
        guard let target = await reference(element, UMLToEcore.Syntax.Feature.type) else { return nil }
        return (await genericType(of: target), target)
    }

    // MARK: - Values

    /// The integer value of a value specification, as `integerValue()` of Eclipse UML2 computes it.
    ///
    /// - Parameter specification: The value specification.
    /// - Returns: The value of an integer or unlimited natural literal, `-1` for `*`, otherwise 0.
    func integerValue(of specification: EUUID) async -> Int {
        typealias Metaclass = UMLToEcore.Syntax.Metaclass
        let kinds = await kinds(specification)
        guard kinds.contains(Metaclass.literalInteger) || kinds.contains(Metaclass.literalUnlimitedNatural) else {
            return 0
        }
        guard let text = await string(specification, UMLToEcore.Syntax.Feature.value) else { return 0 }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return trimmed == UMLToEcore.Syntax.Literal.unlimited ? -1 : Int(trimmed) ?? 0
    }

    /// The text of a value specification, as `stringValue()` of Eclipse UML2 computes it.
    ///
    /// - Parameter specification: The value specification.
    /// - Returns: The value as text, or `nil` if the specification has none.
    func stringValue(of specification: EUUID) async -> String? {
        typealias Metaclass = UMLToEcore.Syntax.Metaclass
        typealias Feature = UMLToEcore.Syntax.Feature
        let kinds = await kinds(specification)
        if kinds.contains(Metaclass.opaqueExpression) { return await strings(specification, Feature.body).first }
        if kinds.contains(Metaclass.literalString) { return await string(specification, Feature.value) }
        if kinds.contains(Metaclass.literalInteger) { return await string(specification, Feature.value) ?? "0" }
        if kinds.contains(Metaclass.literalUnlimitedNatural) {
            return await string(specification, Feature.value) ?? "0"
        }
        if kinds.contains(Metaclass.literalBoolean) {
            return await bool(specification, Feature.value) ? "true" : "false"
        }
        if kinds.contains(Metaclass.literalReal) {
            guard let text = await string(specification, Feature.value) else { return "0.0" }
            return Double(text).map { String($0) } ?? text
        }
        if kinds.contains(Metaclass.instanceValue) {
            guard let instance = await referencedElement(specification, Feature.instance) else { return nil }
            return await string(instance, Feature.name)
        }
        return nil
    }

    /// The bounds, ordering and uniqueness of a multiplicity element.
    ///
    /// - Parameter element: The multiplicity element, or `nil` for the defaults of an
    ///   operation without a result.
    /// - Returns: The lower and upper bounds (1 by default, `-1` for unbounded), whether the
    ///   element is ordered (`false` by default) and whether it is unique (`true` by default).
    func multiplicity(of element: EUUID?) async -> (lower: Int, upper: Int, ordered: Bool, unique: Bool) {
        guard let element else { return (1, 1, false, true) }
        typealias Feature = UMLToEcore.Syntax.Feature
        var lower = 1
        var upper = 1
        if let lowerValue = await referencedElement(element, Feature.lowerValue) {
            lower = await integerValue(of: lowerValue)
        }
        if let upperValue = await referencedElement(element, Feature.upperValue) {
            upper = await integerValue(of: upperValue)
        }
        return (lower, upper, await bool(element, Feature.isOrdered), await bool(element, Feature.isUnique, default: true))
    }

    /// Sets the bounds, ordering and uniqueness of a typed draft from a multiplicity element.
    ///
    /// - Parameters:
    ///   - draft: The typed draft.
    ///   - element: The multiplicity element, or `nil` for the defaults of an operation without a result.
    func applyMultiplicity(_ draft: EcoreDraft, of element: EUUID?) async {
        let multiplicity = await multiplicity(of: element)
        draft.lowerBound = multiplicity.lower
        draft.upperBound = multiplicity.upper
        draft.ordered = multiplicity.ordered
        draft.unique = multiplicity.unique
    }

    // MARK: - Features

    /// Converts a property of a class, structured data type or interface into an `EAttribute`
    /// or an `EReference`.
    ///
    /// A property whose type becomes a class is a reference, which is a containment if the
    /// property is composite or typed by a data type; any other property is an attribute.
    /// The other end of a binary association becomes the opposite if it is navigable. A
    /// navigable end that its association owns becomes a feature of the class at the other
    /// end only if ``UMLToEcore/Options/navigableAssociationOwnedEnds`` says so.
    ///
    /// - Parameter element: The property.
    private func convertProperty(_ element: EUUID) async {
        typealias Feature = UMLToEcore.Syntax.Feature
        guard let namespace = await featureNamespace(of: element) else { return }
        let typeTarget = await reference(element, Feature.type)
        let draft: EcoreDraft
        if typeTarget == nil && options.untypedProperties == .process {
            draft = EcoreDraft(.reference, source: element)
            record(element, draft)
            draft.containment = await isComposite(element)
            draft.type = ecoreClassifier(named: EcoreClassifier.eObject.rawValue)
        } else if let typeTarget, await isEClass(typeTarget) {
            draft = EcoreDraft(.reference, source: element)
            record(element, draft)
            var isDataType = false
            if case .element(let typeElement) = typeTarget {
                isDataType = await isKind(typeElement, UMLToEcore.Syntax.Metaclass.dataType)
            }
            draft.containment = await isComposite(element) || isDataType
        } else {
            draft = EcoreDraft(.attribute, source: element)
            record(element, draft)
            let defaultValue = await referencedElement(element, Feature.defaultValue)
            let isExpression = await isKind(defaultValue, UMLToEcore.Syntax.Metaclass.opaqueExpression)
            if let defaultValue, !(isExpression && options.propertyDefaultExpressions == .process),
                var literal = await stringValue(of: defaultValue)
            {
                if literal.trimmingCharacters(in: .whitespaces) == UMLToEcore.Syntax.Literal.unlimited,
                    let typeTarget, await isUnlimitedNatural(typeTarget)
                {
                    literal = "-1"
                }
                draft.defaultValueLiteral = literal
            }
            draft.iD = await bool(element, Feature.isID)
        }
        guard let eClass = await doSwitch(namespace), eClass.kind == .eClass else { return }
        eClass.features.append(draft)
        draft.container = eClass
        await setName(draft, of: element)
        draft.changeable = !(await bool(element, Feature.isReadOnly))
        draft.derived = await bool(element, Feature.isDerived)
        if let opposite = await otherEnd(of: element), await isNavigable(opposite) {
            if let eOpposite = await doSwitch(opposite), eOpposite.kind == .reference, draft.kind == .reference {
                if draft.derived && !eOpposite.derived { eOpposite.derived = true }
                draft.opposite = eOpposite
            }
        } else if draft.kind == .reference, options.oppositeRoleNames == .process,
            let otherEnd = await otherEnd(of: element), let explicit = await string(otherEnd, Feature.name),
            !explicit.isEmpty, explicit != (await string(namespace, Feature.name))
        {
            draft.annotation(UMLToEcore.Syntax.oppositeRoleNameAnnotation).details[UMLToEcore.Syntax.bodyKey] = explicit
            report(.information, UMLToEcore.Diagnostic.oppositeRoleName,
                   "The opposite role name '\(explicit)' of '\(draft.qualifiedName)' is recorded (processed)")
        }
        if let typeTarget { draft.type = await genericType(of: typeTarget) }
        await applyMultiplicity(draft, of: element)
        await checkOptionalAttribute(draft, of: element)
        await traverse(element)
    }

    /// The namespace whose class a property becomes a feature of.
    ///
    /// - Parameter property: The property.
    /// - Returns: The classifier that owns the property and becomes a class, the classifier at
    ///   the other end of a navigable end that its association owns if the options ask for
    ///   such ends to be converted, or `nil`.
    private func featureNamespace(of property: EUUID) async -> EUUID? {
        guard let namespace = await owner(of: property) else { return nil }
        if await isEClass(namespace) { return namespace }
        guard options.navigableAssociationOwnedEnds == .process,
            await isKind(namespace, UMLToEcore.Syntax.Metaclass.association), await isNavigable(property),
            let otherEnd = await otherEnd(of: property),
            let otherType = await referencedElement(otherEnd, UMLToEcore.Syntax.Feature.type),
            await isEClass(otherType)
        else { return nil }
        return otherType
    }

    /// Reports or converts the navigable ends that an association owns.
    ///
    /// - Parameter element: The association.
    private func convertAssociation(_ element: EUUID) async {
        guard options.navigableAssociationOwnedEnds != .ignore else { return }
        for end in await contents(of: element) where await isNavigable(end) {
            if options.navigableAssociationOwnedEnds == .process {
                await doSwitch(end)
            } else {
                report(.warning, UMLToEcore.Diagnostic.associationOwnedEnd,
                       "The navigable end '\(await qualifiedName(of: end))' is owned by its association and is "
                       + "not converted, as in Eclipse UML2")
            }
        }
    }

    /// Whether a property is composite.
    ///
    /// - Parameter property: The property.
    /// - Returns: `true` if its aggregation is `composite`.
    func isComposite(_ property: EUUID) async -> Bool {
        await string(property, UMLToEcore.Syntax.Feature.aggregation) == UMLToEcore.Syntax.Literal.composite
    }

    /// The association of a property, as the property names it or as the association lists it.
    ///
    /// - Parameter property: The property.
    /// - Returns: The association, or `nil`.
    func association(of property: EUUID) async -> EUUID? {
        if let association = await referencedElement(property, UMLToEcore.Syntax.Feature.association) {
            return association
        }
        if let association = associationOfEnd[property] { return association }
        if let owner = await owner(of: property), await isKind(owner, UMLToEcore.Syntax.Metaclass.association) {
            return owner
        }
        return nil
    }

    /// The other end of a binary association.
    ///
    /// - Parameter property: An end of the association.
    /// - Returns: The other member end, or `nil` if the property is not an end of a binary association.
    func otherEnd(of property: EUUID) async -> EUUID? {
        guard let association = await association(of: property) else { return nil }
        let ends = await referencedElements(association, UMLToEcore.Syntax.Feature.memberEnd)
        guard ends.count == 2, let index = ends.firstIndex(of: property) else { return nil }
        return ends[1 - index]
    }

    /// Whether a property is navigable: owned by a classifier other than an association, or
    /// listed by its association as a navigable owned end.
    ///
    /// - Parameter property: The property.
    /// - Returns: `true` if the property is navigable.
    func isNavigable(_ property: EUUID) async -> Bool {
        guard let owner = await owner(of: property) else { return false }
        if await isKind(owner, UMLToEcore.Syntax.Metaclass.association),
            !(await isKind(owner, UMLToEcore.Syntax.Metaclass.class))
        {
            return await referencedElements(owner, UMLToEcore.Syntax.Feature.navigableOwnedEnd).contains(property)
        }
        return await isKind(owner, UMLToEcore.Syntax.Metaclass.classifier)
    }

    /// Whether a type is the `UnlimitedNatural` primitive type of UML.
    ///
    /// - Parameter target: The type.
    /// - Returns: `true` for the type of the UML primitive types library or one of that name in a
    ///   package named `PrimitiveTypes`.
    func isUnlimitedNatural(_ target: Target) async -> Bool {
        switch target {
        case .library, .unresolved:
            return false
        case .element(let element):
            guard await string(element, UMLToEcore.Syntax.Feature.name) == UMLToEcore.Syntax.unlimitedNatural,
                let package = await owner(of: element)
            else { return false }
            return await string(package, UMLToEcore.Syntax.Feature.name) == UMLToEcore.Syntax.LibraryModel.umlPrimitiveTypes
        }
    }

    /// Handles an optional single-valued attribute of a primitive or enumeration type as the
    /// unsettable primitive attribute and nullable enumeration attribute options say.
    ///
    /// - Parameters:
    ///   - draft: The attribute.
    ///   - element: The property.
    private func checkOptionalAttribute(_ draft: EcoreDraft, of element: EUUID) async {
        guard draft.kind == .attribute, let type = draft.type, draft.lowerBound == 0, draft.upperBound == 1 else { return }
        if isPrimitive(type) {
            guard options.unsettablePrimitiveAttributes != .ignore else { return }
            if options.unsettablePrimitiveAttributes == .process { draft.unsettable = true }
            report(options.unsettablePrimitiveAttributes, UMLToEcore.Diagnostic.optionalAttribute,
                   "The optional attribute '\(draft.qualifiedName)' of a primitive type is not unsettable")
        } else if case .classifier(let eEnum, _) = type, eEnum.kind == .eEnum {
            guard options.nullableEnumAttributes != .ignore else { return }
            if options.nullableEnumAttributes == .process, let optional = nullableTypes[ObjectIdentifier(eEnum)] {
                draft.type = .classifier(optional, arguments: [])
                draft.unsettable = true
            }
            report(options.nullableEnumAttributes, UMLToEcore.Diagnostic.optionalEnumAttribute,
                   "The optional attribute '\(draft.qualifiedName)' of an enumeration type is not nullable")
        }
    }

    /// Whether a type has a Java primitive type or `String` as its instance class.
    ///
    /// - Parameter type: The type.
    /// - Returns: `true` for such Ecore data types and data types of this conversion.
    func isPrimitive(_ type: EcoreDraftType) -> Bool {
        switch type {
        case .external(_, let isClass, let name, _):
            return !isClass && UMLToEcore.Syntax.primitiveInstanceTypes.contains(name)
        case .classifier(let classifier, _):
            return classifier.kind == .eDataType
                && UMLToEcore.Syntax.primitiveInstanceClassNames.contains(classifier.instanceClassName ?? "")
        case .typeParameter:
            return false
        }
    }

    // MARK: - Operations

    /// Converts an operation of a class, structured data type or interface into an `EOperation`.
    ///
    /// The type, bounds, ordering and uniqueness of the operation are those of its return
    /// parameter; without one, the operation has no type and the bounds of 1.
    ///
    /// - Parameter element: The operation.
    private func convertOperation(_ element: EUUID) async {
        guard let namespace = await owner(of: element), await isEClass(namespace) else { return }
        let draft = EcoreDraft(.operation, source: element)
        record(element, draft)
        guard let eClass = await doSwitch(namespace), eClass.kind == .eClass else { return }
        eClass.operations.append(draft)
        draft.container = eClass
        await setName(draft, of: element)
        for exception in await references(element, UMLToEcore.Syntax.Feature.raisedException) {
            if let type = await genericType(of: exception) { draft.exceptions.append(type) }
        }
        let result = await returnParameter(of: element)
        if let result, let type = await type(of: result) { draft.type = type.type }
        await applyMultiplicity(draft, of: result)
        await traverse(element)
    }

    /// The return parameter of an operation.
    ///
    /// - Parameter operation: The operation.
    /// - Returns: The first owned parameter whose direction is `return`, or `nil`.
    func returnParameter(of operation: EUUID) async -> EUUID? {
        for child in await contents(of: operation) where await isKind(child, UMLToEcore.Syntax.Metaclass.parameter) {
            if await string(child, UMLToEcore.Syntax.Feature.direction) == UMLToEcore.Syntax.Literal.returnDirection {
                return child
            }
        }
        return nil
    }

    /// Converts a parameter other than the return parameter into an `EParameter`.
    ///
    /// - Parameter element: The parameter.
    private func convertParameter(_ element: EUUID) async {
        guard let operation = await owner(of: element), await isKind(operation, UMLToEcore.Syntax.Metaclass.operation),
            await string(element, UMLToEcore.Syntax.Feature.direction) != UMLToEcore.Syntax.Literal.returnDirection
        else { return }
        let draft = EcoreDraft(.parameter, source: element)
        record(element, draft)
        guard let eOperation = await doSwitch(operation), eOperation.kind == .operation else { return }
        eOperation.parameters.append(draft)
        draft.container = eOperation
        await setName(draft, of: element)
        draft.type = await type(of: element)?.type
        await applyMultiplicity(draft, of: element)
        await traverse(element)
    }

    /// Converts a classifier or other parameterable element that stands for a template
    /// parameter into an `ETypeParameter` of the classifier or operation of the template.
    ///
    /// - Parameter element: The parameterable element.
    private func convertTypeParameter(_ element: EUUID) async {
        typealias Feature = UMLToEcore.Syntax.Feature
        var templateParameter = await referencedElement(element, Feature.templateParameter)
        if templateParameter == nil, let owner = await owner(of: element),
            await isKind(owner, UMLToEcore.Syntax.Metaclass.templateParameter)
        {
            templateParameter = owner
        }
        guard let templateParameter, let signature = await owner(of: templateParameter),
            let template = await owner(of: signature), let templateDraft = await doSwitch(template),
            templateDraft.kind.isClassifier || templateDraft.kind == .operation
        else { return }
        let draft = EcoreDraft(.typeParameter, source: element)
        record(element, draft)
        var parameters = await referencedElements(signature, Feature.parameter)
        if parameters.isEmpty { parameters = await contents(of: signature) }
        let index = parameters.firstIndex(of: templateParameter) ?? templateDraft.typeParameters.count
        templateDraft.typeParameters.insert(draft, at: min(index, templateDraft.typeParameters.count))
        draft.container = templateDraft
        await setName(draft, of: element)
        if options.ecoreTaggedValues != .ignore,
            let application = application(of: UMLToEcore.Syntax.Stereotype.eTypeParameter, to: templateParameter),
            application.values[UMLToEcore.Syntax.Tag.bounds] != nil
        {
            report(options.ecoreTaggedValues == .process ? .process : .report, UMLToEcore.Diagnostic.ecoreTaggedValue,
                   "The Ecore tagged value 'bounds' of '\(draft.qualifiedName)'")
            if options.ecoreTaggedValues == .process {
                for bound in await taggedReferences(application, UMLToEcore.Syntax.Tag.bounds, of: templateParameter) {
                    if let type = await genericType(of: bound) { draft.bounds.append(type) }
                }
            }
        }
    }

    /// The UML elements that a tagged value refers to.
    ///
    /// - Parameters:
    ///   - application: The stereotype application.
    ///   - tag: The name of the tagged value.
    ///   - element: The element that the stereotype is applied to.
    /// - Returns: What each value resolves to.
    func taggedReferences(_ application: StereotypeApplication, _ tag: String, of element: EUUID) async -> [Target] {
        guard let value = application.values[tag], let resource = owners[element] else { return [] }
        let values = (value as? [any EcoreValue]) ?? [value]
        var targets: [Target] = []
        for value in values {
            if let id = value as? EUUID {
                targets.append(.element(id))
            } else if let proxy = value as? ResourceProxy {
                targets.append(await resolve(proxy))
            } else {
                for word in Self.text(of: value).split(whereSeparator: \.isWhitespace) {
                    if let id = await resource.object(identifiedBy: String(word)) { targets.append(.element(id)) }
                }
            }
        }
        return targets
    }

    // MARK: - Comments and constraints

    /// Records the body of a comment as documentation of the elements it annotates.
    ///
    /// - Parameter element: The comment.
    private func convertComment(_ element: EUUID) async {
        guard let body = await string(element, UMLToEcore.Syntax.Feature.body), !body.isEmpty,
            options.comments != .ignore
        else { return }
        for annotated in await referencedElements(element, UMLToEcore.Syntax.Feature.annotatedElement) {
            guard let draft = await doSwitch(annotated) else { continue }
            if options.comments == .process { addDocumentation(draft, body) }
            report(options.comments, UMLToEcore.Diagnostic.comment, "The comment of '\(draft.qualifiedName)'")
        }
    }

    /// Converts a constraint into an invariant of its classifier, and records its
    /// specification as documentation of its context.
    ///
    /// - Parameter element: The constraint.
    private func convertConstraint(_ element: EUUID) async {
        guard let context = await owner(of: element), var draft = await doSwitch(context) else { return }
        if draft.kind.isClassifier, options.invariantConstraints != .ignore {
            draft = await processInvariant(draft, constraint: element)
        }
        guard let specification = await referencedElement(element, UMLToEcore.Syntax.Feature.specification),
            !(draft.kind == .operation && options.operationBodies == .process)
        else { return }
        if let text = await stringValue(of: specification) { addDocumentation(draft, text) }
    }

    /// Appends a paragraph to the GenModel documentation of a draft.
    ///
    /// - Parameters:
    ///   - draft: The draft.
    ///   - text: The paragraph.
    func addDocumentation(_ draft: EcoreDraft, _ text: String) {
        guard !text.isEmpty else { return }
        let annotation = draft.annotation(AnnotationSource.genModel)
        let key = AnnotationSource.GenModelKey.documentation
        annotation.details[key] = annotation.details[key].map { $0 + options.lineSeparator + text } ?? text
    }

    /// Converts a named constraint of a classifier into an invariant.
    ///
    /// Unless ``UMLToEcore/Options/nonAPIInvariants`` says otherwise, the invariant of a
    /// class becomes a validation operation with the parameters `diagnostics` and `context`.
    /// Otherwise it becomes a constraint of the classifier, whose OCL body is recorded for the
    /// validation delegate if ``UMLToEcore/Options/validationDelegates`` says so.
    ///
    /// - Parameters:
    ///   - classifier: The draft of the classifier.
    ///   - constraint: The constraint.
    /// - Returns: The draft that the constraint documents: the validation operation, or the classifier.
    private func processInvariant(_ classifier: EcoreDraft, constraint: EUUID) async -> EcoreDraft {
        guard let name = await string(constraint, UMLToEcore.Syntax.Feature.name), !name.isEmpty else {
            return classifier
        }
        guard options.invariantConstraints == .process else {
            report(options.invariantConstraints, UMLToEcore.Diagnostic.invariantConstraint,
                   "The invariant '\(name)' of '\(classifier.qualifiedName)'")
            return classifier
        }
        report(.process, UMLToEcore.Diagnostic.invariantConstraint, "The invariant '\(name)' of '\(classifier.qualifiedName)'")
        let body = await opaqueBody(await referencedElement(constraint, UMLToEcore.Syntax.Feature.specification))
        if classifier.kind == .eClass, options.nonAPIInvariants != .process {
            let operation = invariantOperation(named: name, in: classifier)
            record(constraint, operation)
            if let body {
                if options.validationDelegates == .process {
                    processInvariantBody(operation, body)
                } else {
                    processOperationBody(operation, body)
                }
            }
            return operation
        }
        if addConstraint(classifier, name), options.validationDelegates == .process, let body {
            for (language, text) in body where language == UMLToEcore.Syntax.oclLanguage {
                if let package = classifier.package {
                    addDelegate(package, AnnotationSource.EcoreKey.validationDelegates)
                }
                classifier.annotation(options.oclDelegateURI).details[name] = text
            }
        }
        return classifier
    }

    /// Creates the validation operation of an invariant.
    ///
    /// - Parameters:
    ///   - name: The name of the invariant.
    ///   - eClass: The class.
    /// - Returns: The operation, added to the class.
    private func invariantOperation(named name: String, in eClass: EcoreDraft) -> EcoreDraft {
        let operation = EcoreDraft(.operation)
        eClass.operations.append(operation)
        operation.container = eClass
        setName(operation, name, validate: true)
        operation.type = ecoreType(.eBoolean)
        let names = UMLToEcore.Syntax.invariantParameters
        let documentation = UMLToEcore.Syntax.invariantParameterDocumentation
        let diagnostics = EcoreDraft(.parameter)
        diagnostics.name = names.diagnostics
        diagnostics.type = ecoreType(.eDiagnosticChain)
        addDocumentation(diagnostics, documentation.diagnostics)
        let context = EcoreDraft(.parameter)
        context.name = names.context
        let object = ecoreType(.eJavaObject)
        if case .external(let reference, _, let mapName, _) = ecoreType(.eMap) {
            context.type = .external(reference: reference, isClass: false, name: mapName, arguments: [object, object])
        }
        addDocumentation(context, documentation.context)
        for parameter in [diagnostics, context] {
            parameter.container = operation
            operation.parameters.append(parameter)
        }
        return operation
    }

    /// Adds the name of a constraint to the constraints of a classifier.
    ///
    /// - Parameters:
    ///   - classifier: The classifier.
    ///   - name: The name of the constraint.
    /// - Returns: `true` if the name was not listed yet.
    private func addConstraint(_ classifier: EcoreDraft, _ name: String) -> Bool {
        let annotation = classifier.annotation(AnnotationSource.ecore)
        let key = AnnotationSource.EcoreKey.constraints
        var names = annotation.details[key]?.split(separator: " ").map(String.init) ?? []
        guard !names.contains(name) else { return false }
        names.append(name)
        annotation.details[key] = names.joined(separator: " ")
        return true
    }

    /// Adds the OCL delegate URI to a list of delegates of a package.
    ///
    /// - Parameters:
    ///   - package: The package.
    ///   - key: The kind of delegate, such as `validationDelegates`.
    func addDelegate(_ package: EcoreDraft, _ key: String) {
        let annotation = package.annotation(AnnotationSource.ecore)
        var delegates = annotation.details[key]?.split(separator: " ").map(String.init) ?? []
        guard !delegates.contains(options.oclDelegateURI) else { return }
        delegates.append(options.oclDelegateURI)
        annotation.details[key] = delegates.joined(separator: " ")
    }

    /// The languages and bodies of an opaque expression or behaviour, paired as Eclipse UML2 pairs them.
    ///
    /// A body without a language is in OCL. If there are more or fewer languages than bodies,
    /// only a single body is taken, and none if there are several.
    ///
    /// - Parameter element: The opaque expression or behaviour, or `nil`.
    /// - Returns: The pairs of language and body, or `nil` if the element is not opaque.
    func opaqueBody(_ element: EUUID?) async -> [(String, String)]? {
        guard let element else { return nil }
        let kinds = await kinds(element)
        guard kinds.contains(UMLToEcore.Syntax.Metaclass.opaqueExpression)
            || kinds.contains(UMLToEcore.Syntax.Metaclass.opaqueBehavior)
        else { return nil }
        let languages = await strings(element, UMLToEcore.Syntax.Feature.language)
        let bodies = await strings(element, UMLToEcore.Syntax.Feature.body)
        let count = languages.count == bodies.count ? bodies.count : (bodies.count == 1 ? 1 : 0)
        return (0..<count).map { (($0 < languages.count ? languages[$0] : UMLToEcore.Syntax.oclLanguage), bodies[$0]) }
    }

    /// Records the OCL body of an invariant operation for the validation delegate.
    ///
    /// - Parameters:
    ///   - operation: The invariant operation.
    ///   - body: The languages and bodies.
    private func processInvariantBody(_ operation: EcoreDraft, _ body: [(String, String)]) {
        for (language, text) in body where language == UMLToEcore.Syntax.oclLanguage {
            if let package = operation.package { addDelegate(package, AnnotationSource.EcoreKey.validationDelegates) }
            operation.annotation(options.oclDelegateURI).details[UMLToEcore.Syntax.bodyKey] = text
        }
    }

    /// Records the body of an operation as the operation bodies option says.
    ///
    /// An OCL body is recorded for the invocation delegate if
    /// ``UMLToEcore/Options/invocationDelegates`` says so, a Java body for the GenModel, and
    /// any other body under the UML2 GenModel source.
    ///
    /// - Parameters:
    ///   - operation: The operation.
    ///   - body: The languages and bodies.
    func processOperationBody(_ operation: EcoreDraft, _ body: [(String, String)]) {
        for (language, text) in body {
            guard options.operationBodies == .process else {
                report(options.operationBodies, UMLToEcore.Diagnostic.operationBody,
                       "The \(language) body of '\(operation.qualifiedName)'")
                continue
            }
            report(.process, UMLToEcore.Diagnostic.operationBody, "The \(language) body of '\(operation.qualifiedName)'")
            var source = UMLToEcore.Syntax.uml2GenModel
            var value = text
            if language == UMLToEcore.Syntax.oclLanguage {
                value = Self.oclBody(text)
                if options.invocationDelegates == .process {
                    if let package = operation.package { addDelegate(package, AnnotationSource.EcoreKey.invocationDelegates) }
                    source = options.oclDelegateURI
                }
            } else if language == UMLToEcore.Syntax.javaLanguage {
                source = AnnotationSource.genModel
            }
            operation.annotation(source).details[UMLToEcore.Syntax.bodyKey] = value
        }
    }

    /// The OCL expression of a body condition, without a leading `result =` and the
    /// parentheses around the rest, as Eclipse UML2 extracts it.
    ///
    /// - Parameter body: The body condition.
    /// - Returns: The expression.
    static func oclBody(_ body: String) -> String {
        var text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix(UMLToEcore.Syntax.resultPrefix) else { return body }
        text = String(text.dropFirst(UMLToEcore.Syntax.resultPrefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("=") else { return body }
        text = String(text.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("("), text.hasSuffix(")") {
            text = String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }
}
