//
// UMLToEcore.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import EMFBase
import Foundation

/// Converts UML class models into Ecore metamodels, as Eclipse UML2 converts them.
///
/// A UML model read with ``UMLFormat`` holds its packages, classes and properties as
/// instances of the UML metamodel. The conversion turns them into the native packages of an
/// Ecore metamodel, following the mapping of the Eclipse UML2 converter
/// (`UMLUtil.UML2EcoreConverter`), so that a UML class model can serve as the metamodel of
/// instance documents:
///
/// | UML | Ecore |
/// |---|---|
/// | Package, Model, Profile | `EPackage`; nested packages become subpackages |
/// | Class, structured DataType | `EClass` (abstract as the class) |
/// | Interface | abstract interface `EClass` |
/// | Enumeration, EnumerationLiteral | `EEnum`, `EEnumLiteral` (value: position or specification) |
/// | PrimitiveType | `EDataType` whose instance class name is its name |
/// | Generalization, InterfaceRealization | super types |
/// | Property typed by a class, data type or interface | `EReference`; containment if composite or typed by a data type |
/// | Property typed otherwise | `EAttribute` with its default value |
/// | Binary association with navigable ends | opposite references |
/// | Operation, Parameter | `EOperation` typed by its return parameter, `EParameter` |
/// | Template parameters of classifiers and operations | `ETypeParameter` |
/// | Comment | GenModel documentation |
/// | Constraint | invariant: OCL constraint or validation operation, with documentation |
///
/// Multiplicities, ordering and uniqueness carry over (UML defaults to `[1..1]`, unordered and
/// unique), `isReadOnly` becomes not changeable, `isDerived` derived and `isID` an identifier.
/// The UML primitive types become Ecore data types (see ``PrimitiveTypeMapping``), as do the
/// types of the Java, Ecore and XML primitive type libraries of Eclipse UML2, and references
/// to the UML metamodel refer to the bundled UML metamodel.
///
/// A package takes its namespace URI from its `URI`, or else `http:///` followed by its
/// namespace prefix with dots replaced by slashes and `.ecore`; its namespace prefix is that of
/// its super package, a dot and its name. The tagged values of the Ecore profile of Eclipse
/// UML2 (`nsURI`, `nsPrefix`, `className`, `instanceClassName`, `isTransient`, `isVolatile`,
/// `isUnsettable`, `isResolveProxies`, `xmlName` and others) are applied where the profile is
/// applied. Types of other documents are read through the resource set and their packages
/// converted too, as additional root packages. The options (see ``Options``) decide how
/// derived features, derived unions, redefinitions, subsets, duplicates, constraints, bodies
/// and comments are converted.
///
/// ```swift
/// let resourceSet = ResourceSet()
/// let model = try await UMLFormat.read(url: modelURL, resourceSet: resourceSet)
/// let metamodel = try await UMLToEcore.convert(model.resource)
/// for diagnostic in metamodel.diagnostics { print(diagnostic.message) }
/// let instances = try await XMIParser(resourceSet: resourceSet).parse(instanceURL)
/// ```
public enum UMLToEcore {
    // MARK: - Conversion

    /// Converts the UML packages that are roots of a resource into an Ecore metamodel.
    ///
    /// The packages are converted, with everything they contain and the packages of the
    /// types of other documents they use. The Ecore metamodel is loaded into the resource set
    /// as a resource of its own, whose URI is that of the UML resource followed by `.ecore`,
    /// and every root package with a namespace URI other than that of Ecore itself is
    /// registered with the resource set, replacing a package registered under the same URI.
    ///
    /// - Parameters:
    ///   - resource: The resource of a UML model, as ``UMLFormat`` reads it.
    ///   - options: The options of the conversion (default ``Options/standard``).
    ///   - resourceSet: The resource set through which other documents are read and into
    ///     which the metamodel is loaded, or `nil` for that of the resource (or a new one).
    /// - Returns: The resource of the metamodel, its root packages, and what the conversion
    ///   reported.
    /// - Throws: ``UMLToEcoreError/noPackage(_:)`` if no root of the resource is a UML
    ///   package, or ``XMIError`` if the metamodel cannot be loaded.
    public static func convert(
        _ resource: Resource, options: Options = Options(), resourceSet: ResourceSet? = nil
    ) async throws -> ModelDocumentReadResult {
        let packages = try await packageRoots(of: resource)
        return try await convert(packages, in: resource, options: options, resourceSet: resourceSet)
    }

    /// Converts given UML packages of a resource into an Ecore metamodel.
    ///
    /// - Parameters:
    ///   - packages: The identifiers of the UML packages, models or profiles to convert.
    ///   - resource: The resource that holds them.
    ///   - options: The options of the conversion (default ``Options/standard``).
    ///   - resourceSet: The resource set through which other documents are read and into
    ///     which the metamodel is loaded, or `nil` for that of the resource (or a new one).
    /// - Returns: The resource of the metamodel, its root packages, and what the conversion
    ///   reported.
    /// - Throws: ``UMLToEcoreError/noPackage(_:)`` if none of the elements is a UML package,
    ///   or ``XMIError`` if the metamodel cannot be loaded.
    public static func convert(
        _ packages: [EUUID], in resource: Resource, options: Options = Options(), resourceSet: ResourceSet? = nil
    ) async throws -> ModelDocumentReadResult {
        var set = resourceSet
        if set == nil { set = await resource.resourceSet }
        let target = set ?? ResourceSet()
        let translation = try await translate(packages, in: resource, options: options, resourceSet: target)
        return try await load(translation, uri: resource.uri + Syntax.convertedDocumentSuffix, into: target)
    }

    /// Converts UML packages into the text of an Ecore document, without loading it.
    ///
    /// - Parameters:
    ///   - resource: The resource of a UML model.
    ///   - options: The options of the conversion (default ``Options/standard``).
    ///   - resourceSet: The resource set through which other documents are read, or `nil`
    ///     for that of the resource; the UML metamodel is registered with it.
    /// - Returns: The text of the Ecore document and what the conversion reported.
    /// - Throws: ``UMLToEcoreError/noPackage(_:)`` if no root of the resource is a UML package, or
    ///   the error of ``UMLMetamodel/register(in:)``.
    public static func translate(
        _ resource: Resource, options: Options = Options(), resourceSet: ResourceSet? = nil
    ) async throws -> ModelDocumentWriteResult {
        let packages = try await packageRoots(of: resource)
        var set = resourceSet
        if set == nil { set = await resource.resourceSet }
        return try await translate(packages, in: resource, options: options, resourceSet: set)
    }

    /// Converts UML packages into the text of an Ecore document.
    ///
    /// - Parameters:
    ///   - packages: The UML packages.
    ///   - resource: The resource that holds them.
    ///   - options: The options of the conversion.
    ///   - resourceSet: The resource set through which other documents are read.
    /// - Returns: The text of the Ecore document and what the conversion reported.
    /// - Throws: ``UMLToEcoreError/noPackage(_:)`` if none of the elements is a UML package, or
    ///   the error of ``UMLMetamodel/register(in:)``.
    static func translate(
        _ packages: [EUUID], in resource: Resource, options: Options, resourceSet: ResourceSet?
    ) async throws -> ModelDocumentWriteResult {
        if let resourceSet { try await UMLMetamodel.register(in: resourceSet) }
        let converter = UMLToEcoreConverter(options: options, resourceSet: resourceSet, document: resource.uri)
        var roots: [EUUID] = []
        for package in packages where await isPackage(package, in: resource) { roots.append(package) }
        guard !roots.isEmpty else { throw UMLToEcoreError.noPackage(resource.uri) }
        let drafts = await converter.convert(roots, in: resource)
        await assignIdentifiers(drafts, converter: converter)
        var writer = EcoreDraftWriter()
        return ModelDocumentWriteResult(text: writer.write(drafts), diagnostics: converter.diagnostics)
    }

    /// Loads the text of a converted metamodel into a resource set and registers its packages.
    ///
    /// If the metamodel refers to the bundled UML metamodel or its primitive types, they are
    /// registered first, and made available as resources under their namespace URIs, through
    /// which the loader resolves references to them.
    ///
    /// - Parameters:
    ///   - translation: The Ecore text and the diagnostics of the conversion.
    ///   - uri: The URI of the resource of the metamodel.
    ///   - resourceSet: The resource set.
    /// - Returns: The resource, its root packages, and the diagnostics of the conversion and the load.
    /// - Throws: ``XMIError`` if the metamodel cannot be loaded.
    static func load(_ translation: ModelDocumentWriteResult, uri: String, into resourceSet: ResourceSet) async throws
        -> ModelDocumentReadResult
    {
        if translation.text.contains(UMLNamespaces.uml) || translation.text.contains(UMLNamespaces.types) {
            try await UMLMetamodel.register(in: resourceSet)
            let (uml, types) = try await UMLMetamodel.packages()
            for (uri, package) in [(UMLNamespaces.uml, uml), (UMLNamespaces.types, types)]
            where await resourceSet.getResource(uri: uri) == nil {
                await resourceSet.createResource(uri: uri).registerNativePackage(package)
            }
        }
        let resource = try await resourceSet.loadEcoreResource(
            data: Data(translation.text.utf8), uri: uri, enableDebugging: false,
            options: EcoreLoadOptions(unresolvedReferences: .keepAsProxies, tolerant: true))
        let packages = await resource.getRootObjects().compactMap { $0 as? EPackage }
        for package in packages where !package.nsURI.isEmpty && package.nsURI != EcoreURI.ecoreNamespace.rawValue {
            await resourceSet.registerMetamodel(package)
        }
        return ModelDocumentReadResult(
            resource: resource, packages: packages, diagnostics: translation.diagnostics + (await resource.loadDiagnostics))
    }

    // MARK: - Reading UML documents as metamodels

    /// Reads a UML class model from a file or another location as an Ecore metamodel.
    ///
    /// This is the reader of UML documents in the role of a metamodel: the model is read with
    /// ``UMLFormat`` into a resource set of its own, with the Ecore profile described (see
    /// ``registerEcoreProfile(in:)``), converted, and the metamodel loaded into the given
    /// resource set under the URI of the document.
    ///
    /// - Parameters:
    ///   - url: The location of the UML document.
    ///   - resourceSet: The resource set that receives the metamodel.
    ///   - options: The options of the conversion (default ``Options/standard``).
    ///   - modelResourceSet: The resource set into which the UML model and the documents it
    ///     refers to are read, for example one with URI mappings for them, or `nil` for a new one.
    /// - Returns: The resource of the metamodel, its root packages, and what the reader and
    ///   the conversion reported.
    /// - Throws: The errors of ``read(data:uri:resourceSet:options:modelResourceSet:)`` or of
    ///   the URI handler.
    public static func read(
        url: URL, resourceSet: ResourceSet, options: Options = Options(), modelResourceSet: ResourceSet? = nil
    ) async throws -> ModelDocumentReadResult {
        let uri = URIReference.canonicalise(url.absoluteString)
        return try await read(
            data: try await resourceSet.readDocument(uri: uri), uri: uri, resourceSet: resourceSet, options: options,
            modelResourceSet: modelResourceSet)
    }

    /// Reads a UML class model from its bytes as an Ecore metamodel.
    ///
    /// The applications of the Ecore profile are read without its definition, so the warning
    /// that ``UMLFormat`` gives for that profile is left out.
    ///
    /// - Parameters:
    ///   - data: The bytes of the UML document.
    ///   - uri: The URI of the document, which the metamodel resource takes.
    ///   - resourceSet: The resource set that receives the metamodel.
    ///   - options: The options of the conversion (default ``Options/standard``).
    ///   - modelResourceSet: The resource set into which the UML model and the documents it
    ///     refers to are read, or `nil` for a new one. It must not be the resource set of the metamodel.
    /// - Returns: The resource of the metamodel, its root packages, and what the reader and
    ///   the conversion reported.
    /// - Throws: ``XMIError`` if the document is not well-formed XMI or the metamodel cannot be
    ///   loaded, or ``UMLToEcoreError/noPackage(_:)`` if the document holds no UML package.
    public static func read(
        data: Data, uri: String, resourceSet: ResourceSet, options: Options = Options(),
        modelResourceSet: ResourceSet? = nil
    ) async throws -> ModelDocumentReadResult {
        let uri = URIReference.canonicalise(uri)
        let modelSet = modelResourceSet ?? ResourceSet()
        await registerEcoreProfile(in: modelSet)
        let model = try await UMLFormat.read(data: data, uri: uri, resourceSet: modelSet)
        let readDiagnostics = model.diagnostics.filter { !isEcoreProfileDiagnostic($0) }
        let translation = try await translate(
            try await packageRoots(of: model.resource), in: model.resource, options: options, resourceSet: modelSet)
        let loaded = try await load(translation, uri: uri, into: resourceSet)
        return ModelDocumentReadResult(
            resource: loaded.resource, packages: loaded.packages, diagnostics: readDiagnostics + loaded.diagnostics)
    }

    /// Whether a diagnostic of the UML reader concerns the definition of the Ecore profile,
    /// which the conversion does not need.
    ///
    /// - Parameter diagnostic: A diagnostic of ``UMLFormat``.
    /// - Returns: `true` for the warning about the unresolved Ecore profile and for the classes
    ///   of its stereotypes that no registered metamodel defines.
    static func isEcoreProfileDiagnostic(_ diagnostic: SourceDiagnostic) -> Bool {
        if diagnostic.code == ModelDocumentDiagnostic.unresolvedProfile {
            return diagnostic.message.contains("'" + UMLNamespaces.ecoreProfile + "'")
        }
        guard diagnostic.code == ModelDocumentDiagnostic.conversionWarning else { return false }
        return Syntax.Stereotype.all.contains { diagnostic.message.hasSuffix("class '\($0)'") }
    }

    // MARK: - Helpers

    /// The roots of a resource that are UML packages.
    ///
    /// - Parameter resource: The resource.
    /// - Returns: The identifiers of the packages in order.
    /// - Throws: ``UMLToEcoreError/noPackage(_:)`` if there are none.
    static func packageRoots(of resource: Resource) async throws -> [EUUID] {
        var packages: [EUUID] = []
        for root in await resource.getRootObjects() where await isPackage(root.id, in: resource) {
            packages.append(root.id)
        }
        guard !packages.isEmpty else { throw UMLToEcoreError.noPackage(resource.uri) }
        return packages
    }

    /// Whether an object of a resource is a UML package.
    ///
    /// - Parameters:
    ///   - id: The object.
    ///   - resource: The resource.
    /// - Returns: `true` if the metaclass of the object is `Package` or a subclass of it.
    static func isPackage(_ id: EUUID, in resource: Resource) async -> Bool {
        guard let object = await resource.resolve(id) else { return false }
        guard let eClass = object.eClass as? EClass else { return false }
        return eClass.name == Syntax.Metaclass.package || eClass.allSuperTypes.contains { $0.name == Syntax.Metaclass.package }
    }

    /// Gives every element of the converted metamodel an identifier: that of its UML element
    /// where it has one, otherwise one made of the identifier of its container and its name.
    ///
    /// - Parameters:
    ///   - roots: The root packages.
    ///   - converter: The converter that made them.
    static func assignIdentifiers(_ roots: [EcoreDraft], converter: UMLToEcoreConverter) async {
        var used: Set<String> = []
        func unique(_ candidate: String) -> String {
            var identifier = candidate.isEmpty ? String(wordSeparator) : candidate
            var counter = 1
            while !used.insert(identifier).inserted {
                identifier = candidate + "." + String(counter)
                counter += 1
            }
            return identifier
        }
        func assign(_ draft: EcoreDraft, parent: String) async {
            var candidate: String?
            if let source = draft.source { candidate = await converter.xmlIdentifier(of: source) }
            draft.identifier = unique(candidate ?? (parent.isEmpty ? draft.name : parent + "." + draft.name))
            let children = draft.classifiers + draft.subpackages + draft.typeParameters + draft.literals
                + draft.operations + draft.features + draft.parameters
                + draft.annotations.flatMap(\.contents)
            for child in children { await assign(child, parent: draft.identifier) }
        }
        for root in roots { await assign(root, parent: "") }
    }
}

/// Errors raised while UML models are converted into Ecore metamodels.
public enum UMLToEcoreError: Error, Sendable, Equatable {
    /// The resource or document holds no UML package. The associated value is its URI.
    case noPackage(String)
}

extension UMLToEcoreError: CustomStringConvertible, LocalizedError {
    /// A sentence that describes the error and names the document.
    public var description: String {
        switch self {
        case .noPackage(let document):
            return "\(document) holds no UML package, model or profile to convert"
        }
    }

    /// The ``description`` of the error.
    public var errorDescription: String? { description }
}
