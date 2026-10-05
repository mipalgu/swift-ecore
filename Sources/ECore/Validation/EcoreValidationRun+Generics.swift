import EMFBase

extension EcoreValidationRun {
    /// Checks the name and bounds of a type parameter.
    ///
    /// - Parameter value: The declared type parameter.
    func checkTypeParameter(_ value: ETypeParameter) {
        checkName(of: value.id, value.name)
    }

    /// Checks generic declarations, keys and unresolved types owned by an element.
    ///
    /// Generic diagnostics refer to their named owner so that editors can locate them
    /// through the metamodel index.
    ///
    /// - Parameter element: The model element to validate.
    func checkGenericDeclarations(_ element: EcoreElement) {
        var parameters: [ETypeParameter] = []
        var types: [(EcoreFeatureName, EGenericType)] = []
        switch element {
        case .eClass(let value):
            parameters = value.eTypeParameters
            types = value.eGenericSuperTypes.map { (.eGenericSuperTypes, $0) }
            checkGenericSuperTypes(value)
        case .dataType(let value): parameters = value.eTypeParameters
        case .eEnum(let value): parameters = value.eTypeParameters
        case .operation(let value):
            parameters = value.eTypeParameters
            types = value.eGenericType.map { [(.eGenericType, $0)] } ?? []
            types += value.eGenericExceptions.map { (.eGenericExceptions, $0) }
        case .parameter(let value): types = value.eGenericType.map { [(.eGenericType, $0)] } ?? []
        case .attribute(let value): types = value.eGenericType.map { [(.eGenericType, $0)] } ?? []
        case .reference(let value):
            types = value.eGenericType.map { [(.eGenericType, $0)] } ?? []
            checkKeys(value)
        case .typeParameter(let value): types = value.eBounds.map { (.eBounds, $0) }
        default: break
        }
        var names = Set<String>()
        for parameter in parameters where !names.insert(parameter.name).inserted {
            report(.uniqueTypeParameterNames, .duplicateTypeParameterName, element: element.id,
                feature: .eTypeParameters, arguments: [parameter.name], related: parameters.filter { $0.name == parameter.name }.map(\.id))
        }
        checkProxy(element.id, owner: element.id, feature: .eType)
        checkRetainedProxies(element.id, owner: element.id)
        for (feature, type) in types {
            checkGenericType(type, owner: element.id, feature: feature, parentFeature: nil)
        }
    }

    /// Checks that every key is an inherited or declared attribute of the target.
    ///
    /// - Parameter reference: The reference whose key identifiers to check.
    private func checkKeys(_ reference: EReference) {
        guard let target = canonical(reference.eType) as? EClass else { return }
        let allowed = Set(allFeatures(of: target).compactMap { ($0 as? EAttribute)?.id })
        for key in reference.eKeys where !allowed.contains(key) {
            report(.consistentKeys, .keyNotFromType, element: reference.id, feature: .eKeys,
                arguments: [index.element(key)?.name ?? key.uuidString], related: [key])
        }
    }

    /// The parameters of the canonical declaration of a classifier.
    ///
    /// - Parameter classifier: The classifier to inspect.
    /// - Returns: The declared type parameters.
    private func parameters(of classifier: any EClassifier) -> [ETypeParameter] {
        switch canonical(classifier) {
        case let value as EClass: return value.eTypeParameters
        case let value as EDataType: return value.eTypeParameters
        case let value as EEnum: return value.eTypeParameters
        default: return []
        }
    }

    /// Checks a generic type and recursively checks its nested types.
    ///
    /// - Parameters:
    ///   - type: The generic type being checked.
    ///   - owner: The named element to which diagnostics belong.
    ///   - feature: The containment feature of this generic type.
    ///   - parentFeature: The containment feature of its parent generic type, if any.
    private func checkGenericType(_ type: EGenericType, owner: EUUID,
        feature: EcoreFeatureName, parentFeature: EcoreFeatureName?) {
        if type.eClassifier != nil && type.eTypeParameter != nil {
            report(.consistentType, .genericTypeConflictingTargets, element: owner, feature: feature)
        }
        if let parameter = type.eTypeParameter, !parameterIsVisible(parameter, owner: owner, feature: feature) {
            report(.consistentType, .typeParameterOutOfScope, element: owner, feature: feature, related: [parameter])
        }
        if feature == .eGenericSuperTypes && !(type.eClassifier is EClass) {
            report(.consistentType, .genericClassifierInvalid, element: owner, feature: feature)
        } else if type.isWildcard && (feature != .eTypeArguments || parentFeature == .eGenericSuperTypes) {
            report(.consistentType, .genericWildcardInvalid, element: owner, feature: feature)
        }
        if type.eUpperBound != nil || type.eLowerBound != nil {
            if feature != .eTypeArguments || !type.isWildcard || (type.eUpperBound != nil && type.eLowerBound != nil) {
                report(.consistentGenericBounds, .genericBoundsInvalid, element: owner, feature: feature)
            }
        }
        let declared = type.eClassifier.map { parameters(of: $0) } ?? []
        if type.eTypeArguments.count != declared.count {
            report(.consistentArguments, .genericArgumentsInvalid,
                severity: type.eTypeArguments.isEmpty && !declared.isEmpty ? .warning : .error,
                element: owner, feature: feature,
                arguments: [String(type.eTypeArguments.count), String(declared.count)])
        } else {
            let substitutions = Dictionary(zip(declared.map(\.id), type.eTypeArguments), uniquingKeysWith: { first, _ in first })
            for (parameter, argument) in zip(declared, type.eTypeArguments) {
                if !parameter.eBounds.allSatisfy({ conforms(argument, to: $0, substitutions: substitutions) }) {
                    report(.consistentArguments, .genericSubstitutionInvalid, element: owner, feature: feature,
                        related: [parameter.id])
                }
            }
        }
        checkProxy(type.id, owner: owner, feature: feature)
        checkRetainedProxies(type.id, owner: owner)
        for child in type.containedTypes {
            checkGenericType(child.object, owner: owner, feature: child.feature, parentFeature: feature)
        }
    }

    /// Checks the declaration scope and ordering of a type parameter reference.
    ///
    /// - Parameters:
    ///   - parameter: The referenced parameter identifier.
    ///   - owner: The named element that contains the reference.
    ///   - feature: The generic containment feature of the reference.
    /// - Returns: Whether the reference is visible at that location.
    private func parameterIsVisible(_ parameter: EUUID, owner: EUUID, feature: EcoreFeatureName) -> Bool {
        guard case .typeParameter? = index.element(parameter),
            let declaration = index.container(of: parameter)?.container else { return false }
        let ancestry = [owner] + index.ancestors(of: owner)
        guard ancestry.contains(declaration) else { return false }
        if feature == .eBounds, case .typeParameter? = index.element(owner) {
            let siblings = index.children(of: declaration).filter { if case .typeParameter = $0 { true } else { false } }
            guard let used = siblings.firstIndex(where: { $0.id == parameter }),
                let current = siblings.firstIndex(where: { $0.id == owner }) else { return false }
            return used < current
        }
        return true
    }

    /// Checks an argument against a bound after substituting parameter references.
    ///
    /// - Parameters:
    ///   - argument: The supplied type argument.
    ///   - bound: The required bound.
    ///   - substitutions: Arguments assigned to the declaration's parameters.
    /// - Returns: Whether the argument satisfies the bound.
    private func conforms(_ argument: EGenericType, to bound: EGenericType,
        substitutions: [EUUID: EGenericType]) -> Bool {
        if let parameter = bound.eTypeParameter, let substituted = substitutions[parameter] {
            return argument.hasSameStructure(as: substituted)
        }
        if argument.isWildcard {
            if let upper = argument.eUpperBound { return conforms(upper, to: bound, substitutions: substitutions) }
            if let lower = argument.eLowerBound { return conforms(lower, to: bound, substitutions: substitutions) }
            return true
        }
        guard let target = bound.eClassifier else { return true }
        guard let supplied = argument.eClassifier else { return argument.eTypeParameter != nil }
        let actual = canonical(supplied)
        if actual.id == target.id {
            return bound.eTypeArguments.isEmpty || (argument.eTypeArguments.count == bound.eTypeArguments.count
                && zip(argument.eTypeArguments, bound.eTypeArguments).allSatisfy { conforms($0, to: $1, substitutions: substitutions) })
        }
        if let actualClass = actual as? EClass, target is EClass {
            return inheritedGenericTypes(of: EGenericType(eClassifier: actualClass, eTypeArguments: argument.eTypeArguments))
                .contains { $0.eClassifier?.id == target.id && conforms($0, to: bound, substitutions: substitutions) }
        }
        return false
    }

    /// Checks duplicate and incompatible generic superclass declarations.
    ///
    /// - Parameter value: The class whose superclass declarations to check.
    private func checkGenericSuperTypes(_ value: EClass) {
        var seen: [EUUID: EGenericType] = [:]
        var reported = Set<EUUID>()
        let directIDs = value.eGenericSuperTypes.compactMap { $0.eClassifier?.id }
        for type in inheritedGenericTypes(of: EGenericType(eClassifier: value)) {
            guard let classifier = type.eClassifier else { continue }
            if let previous = seen[classifier.id],
                (!previous.hasSameStructure(as: type) || directIDs.filter({ $0 == classifier.id }).count > 1),
                reported.insert(classifier.id).inserted {
                report(.consistentSuperTypes, .genericSuperTypesInconsistent, element: value.id,
                    feature: .eGenericSuperTypes, arguments: [classifier.name], related: [classifier.id])
            } else { seen[classifier.id] = type }
        }
    }

    /// Substitutes a declaration's parameters throughout a generic type.
    ///
    /// - Parameters:
    ///   - type: The declared generic type.
    ///   - substitutions: The actual arguments assigned to type parameters.
    /// - Returns: The type with its parameter references substituted.
    private func substitute(_ type: EGenericType, using substitutions: [EUUID: EGenericType]) -> EGenericType {
        if let parameter = type.eTypeParameter, let replacement = substitutions[parameter] { return replacement }
        var result = type
        result.eTypeArguments = type.eTypeArguments.map { substitute($0, using: substitutions) }
        result.eUpperBound = type.eUpperBound.map { substitute($0, using: substitutions) }
        result.eLowerBound = type.eLowerBound.map { substitute($0, using: substitutions) }
        return result
    }

    /// Lists generic ancestors with their arguments substituted on each inheritance path.
    ///
    /// Cycles stop at the first repeated classifier on a path. Separate paths remain
    /// available so that contradictory substitutions can be detected in a diamond.
    ///
    /// - Parameter type: The class use whose ancestors to inspect.
    /// - Returns: The generic ancestors in inheritance order.
    private func inheritedGenericTypes(of type: EGenericType) -> [EGenericType] {
        var result: [EGenericType] = []
        var expanded: [EUUID: [EGenericType]] = [:]
        func visit(_ use: EGenericType, path: Set<EUUID>) {
            guard let raw = use.eClassifier, let value = canonical(raw) as? EClass,
                !path.contains(value.id),
                !(expanded[value.id] ?? []).contains(where: { $0.hasSameStructure(as: use) }) else { return }
            expanded[value.id, default: []].append(use)
            let substitutions = Dictionary(zip(value.eTypeParameters.map(\.id), use.eTypeArguments),
                uniquingKeysWith: { first, _ in first })
            let explicitIDs = Set(value.eGenericSuperTypes.compactMap { $0.eClassifier?.id })
            let parents = value.eGenericSuperTypes + value.eSuperTypes.filter { !explicitIDs.contains($0.id) }
                .map { EGenericType(eClassifier: $0) }
            for parent in parents {
                let applied = substitute(parent, using: substitutions)
                result.append(applied)
                visit(applied, path: path.union([value.id]))
            }
        }
        visit(type, path: [])
        return result
    }

    /// Reports retained unresolved reference families on a named or generic element.
    ///
    /// - Parameters:
    ///   - identifier: The element holding the retained references.
    ///   - owner: The named element to which diagnostics belong.
    private func checkRetainedProxies(_ identifier: EUUID, owner: EUUID) {
        guard let rootID = index.root(of: owner), case .package(let package)? = index.element(rootID) else { return }
        for feature in EcoreFeatureName.allCases {
            for proxy in package.origin?.unresolvedReferences[identifier]?[feature] ?? [] {
                report(.everyProxyResolves, .unresolvedProxy, element: owner, feature: feature,
                    arguments: [proxy.uri + "#" + proxy.fragment])
            }
        }
    }

    /// Reports an unresolved classifier reference retained by the loader.
    ///
    /// - Parameters:
    ///   - identifier: The typed element or generic type holding the proxy.
    ///   - owner: The named element to which the diagnostic belongs.
    ///   - feature: The feature holding the unresolved reference.
    private func checkProxy(_ identifier: EUUID, owner: EUUID, feature: EcoreFeatureName) {
        guard let rootID = index.root(of: owner), case .package(let package)? = index.element(rootID),
            let proxy = package.origin?.unresolvedTypes[identifier] else { return }
        report(.everyProxyResolves, .unresolvedProxy, element: owner, feature: feature,
            arguments: [proxy.uri + "#" + proxy.fragment])
    }
}
