import EMFBase
import Testing

@testable import ECore

/// Verifies validation of generic declarations, reference keys and retained proxies.
@Suite("Generic Ecore validation")
struct EcoreGenericValidatorTests {
    /// The data type used for primitive attributes and type arguments.
    private static let string = EcorePackage.dataType(.eString)!

    /// Validates a self-authored package and selects one constraint.
    ///
    /// - Parameters:
    ///   - classifiers: The classifiers to validate.
    ///   - constraint: The constraint whose diagnostics to retain.
    /// - Returns: The matching diagnostics in document order.
    private func diagnostics(_ classifiers: [any EClassifier], _ constraint: EcoreConstraint) -> [EcoreDiagnostic] {
        let package = EPackage(name: "sample", nsURI: "urn:test:sample", nsPrefix: "sample", eClassifiers: classifiers)
        return EcoreValidator().validate(MetamodelIndex(roots: [package])).filter { $0.code == constraint }
    }

    /// Checks keys against the canonical target and inherited attributes.
    @Test("Keys must belong to the target class or its supertypes")
    func referenceKeys() {
        let key = EAttribute(name: "key", eType: Self.string)
        let foreign = EAttribute(name: "foreign", eType: Self.string)
        let base = EClass(name: "Base", eStructuralFeatures: [key])
        let target = EClass(name: "Target", eSuperTypes: [base])
        var reference = EReference(name: "items", eType: target)
        reference.eKeys = [key.id]
        let owner = EClass(name: "Owner", eStructuralFeatures: [reference, foreign])
        #expect(diagnostics([base, target, owner], .consistentKeys).isEmpty)
        reference.eKeys = [foreign.id]
        let bad = EClass(id: owner.id, name: owner.name, eStructuralFeatures: [reference, foreign])
        let found = diagnostics([base, target, bad], .consistentKeys)
        #expect(found.count == 1)
        #expect(found.first?.element == reference.id)
        #expect(found.first?.feature == .eKeys)
    }

    /// Checks duplicate declarations on all declaring metaclasses.
    @Test("Type parameter names are unique within each declaration", arguments: [0, 1, 2, 3])
    func parameterNames(kind: Int) {
        let parameters = [ETypeParameter(name: "T"), ETypeParameter(name: "T")]
        let classifier: any EClassifier
        switch kind {
        case 0:
            var value = EClass(name: "Owner"); value.eTypeParameters = parameters; classifier = value
        case 1:
            var value = EDataType(name: "Owner"); value.eTypeParameters = parameters; classifier = value
        case 2:
            var value = EEnum(name: "Owner"); value.eTypeParameters = parameters; classifier = value
        default:
            var operation = EOperation(name: "run"); operation.eTypeParameters = parameters
            classifier = EClass(name: "Owner", eOperations: [operation])
        }
        #expect(diagnostics([classifier], .uniqueTypeParameterNames).count == 1)
    }

    /// Checks classifier/type-parameter exclusivity and scope.
    @Test("Generic type parameters must be in scope and exclusive")
    func parameterScope() {
        let parameter = ETypeParameter(name: "T")
        var declared = EClass(name: "Declared"); declared.eTypeParameters = [parameter]
        var operation = EOperation(name: "run")
        operation.eGenericType = EGenericType(eClassifier: Self.string, eTypeParameter: parameter.id)
        var owner = EClass(name: "Owner", eOperations: [operation])
        #expect(diagnostics([declared, owner], .consistentType).count == 2)
        owner.eTypeParameters = [parameter]
        operation.eGenericType = EGenericType(eTypeParameter: parameter.id)
        owner.eOperations = [operation]
        #expect(diagnostics([owner], .consistentType).isEmpty)
    }

    /// Checks generic superclass kinds and wildcard restrictions.
    @Test("Generic supertypes require classes and concrete type arguments")
    func supertypeKinds() {
        var owner = EClass(name: "Owner")
        owner.eGenericSuperTypes = [EGenericType(eClassifier: Self.string)]
        #expect(diagnostics([owner], .consistentType).count == 1)
        var base = EClass(name: "Base"); base.eTypeParameters = [ETypeParameter(name: "T")]
        owner.eGenericSuperTypes = [EGenericType(eClassifier: base, eTypeArguments: [EGenericType()])]
        #expect(diagnostics([base, owner], .consistentType).count == 1)
    }

    /// Checks every invalid wildcard-bound combination.
    @Test("Wildcard bounds are exclusive and only belong to type arguments", arguments: [0, 1, 2])
    func wildcardBounds(kind: Int) {
        let bound = EGenericType(eClassifier: Self.string)
        var operation = EOperation(name: "run")
        switch kind {
        case 0: operation.eGenericType = EGenericType(eUpperBound: bound)
        case 1:
            operation.eGenericType = EGenericType(eClassifier: Self.string, eTypeArguments: [
                EGenericType(eUpperBound: bound, eLowerBound: bound),
            ])
        default:
            operation.eGenericType = EGenericType(eClassifier: Self.string, eTypeArguments: [
                EGenericType(eClassifier: Self.string, eUpperBound: bound),
            ])
        }
        #expect(diagnostics([EClass(name: "Owner", eOperations: [operation])], .consistentGenericBounds).count == 1)
    }

    /// Checks argument arity and the warning for raw generic use.
    @Test("Arguments match parameter arity and require a classifier", arguments: [0, 1, 2])
    func argumentArity(kind: Int) {
        var sequence = EDataType(name: "Sequence"); sequence.eTypeParameters = [ETypeParameter(name: "T")]
        var operation = EOperation(name: "run")
        switch kind {
        case 0: operation.eGenericType = EGenericType(eClassifier: sequence)
        case 1: operation.eGenericType = EGenericType(eClassifier: sequence, eTypeArguments: [EGenericType(), EGenericType()])
        default: operation.eGenericType = EGenericType(eTypeArguments: [EGenericType(eClassifier: Self.string)])
        }
        let found = diagnostics([sequence, EClass(name: "Owner", eOperations: [operation])], .consistentArguments)
        #expect(found.count == 1)
        #expect(found.first?.severity == (kind == 0 ? .warning : .error))
    }

    /// Checks argument substitution against class bounds.
    @Test("Type arguments satisfy parameter bounds")
    func substitutions() {
        let base = EClass(name: "Base")
        let derived = EClass(name: "Derived", eSuperTypes: [base])
        var sequence = EClass(name: "Sequence")
        sequence.eTypeParameters = [ETypeParameter(name: "T", eBounds: [EGenericType(eClassifier: base)])]
        var operation = EOperation(name: "run")
        operation.eGenericType = EGenericType(eClassifier: sequence, eTypeArguments: [EGenericType(eClassifier: derived)])
        var owner = EClass(name: "Owner", eOperations: [operation])
        #expect(diagnostics([base, derived, sequence, owner], .consistentArguments).isEmpty)
        operation.eGenericType = EGenericType(eClassifier: sequence, eTypeArguments: [EGenericType(eClassifier: Self.string)])
        owner.eOperations = [operation]
        #expect(diagnostics([base, derived, sequence, owner], .consistentArguments).count == 1)
    }

    /// Checks contradictory uses of one generic superclass.
    @Test("Repeated generic supertypes must be consistent")
    func superclassArguments() {
        var base = EClass(name: "Base"); base.eTypeParameters = [ETypeParameter(name: "T")]
        var owner = EClass(name: "Owner")
        owner.eGenericSuperTypes = [
            EGenericType(eClassifier: base, eTypeArguments: [EGenericType(eClassifier: Self.string)]),
            EGenericType(eClassifier: base, eTypeArguments: [EGenericType(eClassifier: EcorePackage.dataType(.eInt))]),
        ]
        #expect(diagnostics([base, owner], .consistentSuperTypes).count == 1)
    }

    /// Checks that all preserved unresolved references produce diagnostics.
    @Test("Unresolved proxies are reported and may be disabled")
    func unresolvedProxies() async throws {
        let set = ResourceSet()
        let text = GenericWritingFixtures.document.replacingOccurrences(of: "#//Item", with: "absent.ecore#//Item")
        await set.setURIHandlers([InMemoryURIHandler(texts: [GenericWritingFixtures.uri: text])])
        let resource = try await set.loadEcoreResource(uri: GenericWritingFixtures.uri,
            options: EcoreLoadOptions(unresolvedReferences: .keepAsProxies))
        let package = try #require(await resource.getRootObjects().first as? EPackage)
        let index = MetamodelIndex(roots: [package])
        let validator = EcoreValidator()
        #expect(!validator.validate(index).filter { $0.code == .everyProxyResolves }.isEmpty)
        let disabled = EcoreValidator(options: .init(disabledConstraints: [.everyProxyResolves]))
        #expect(disabled.validate(index).allSatisfy { $0.code != .everyProxyResolves })
    }

    /// Checks the shared opt-out policy for every new constraint.
    @Test("All generic constraints can be disabled together")
    func disabledConstraints() {
        let codes: Set<EcoreConstraint> = [.consistentKeys, .uniqueTypeParameterNames, .consistentType,
            .consistentGenericBounds, .consistentArguments, .consistentSuperTypes, .everyProxyResolves]
        var owner = EClass(name: "Owner")
        owner.eTypeParameters = [ETypeParameter(name: "T"), ETypeParameter(name: "T")]
        owner.eGenericSuperTypes = [EGenericType(eClassifier: Self.string, eTypeArguments: [EGenericType()])]
        let package = EPackage(name: "sample", nsURI: "urn:test:sample", nsPrefix: "sample", eClassifiers: [owner])
        let findings = EcoreValidator(options: .init(disabledConstraints: codes)).validate(MetamodelIndex(roots: [package]))
        #expect(findings.allSatisfy { !codes.contains($0.code) })
    }
    /// Checks inherited generic substitutions through a diamond hierarchy.
    @Test("Generic ancestor arguments agree across all inheritance paths")
    func diamondArguments() {
        let parameter = ETypeParameter(name: "T")
        var base = EClass(name: "Base"); base.eTypeParameters = [parameter]
        var left = EClass(name: "Left")
        left.eGenericSuperTypes = [EGenericType(eClassifier: base, eTypeArguments: [EGenericType(eClassifier: Self.string)])]
        var right = EClass(name: "Right")
        right.eGenericSuperTypes = [EGenericType(eClassifier: base, eTypeArguments: [EGenericType(eClassifier: EcorePackage.dataType(.eInt))])]
        let owner = EClass(name: "Owner", eSuperTypes: [left, right])
        #expect(diagnostics([base, left, right, owner], .consistentSuperTypes).count == 1)
        right.eGenericSuperTypes = left.eGenericSuperTypes
        let good = EClass(id: owner.id, name: owner.name, eSuperTypes: [left, right])
        #expect(diagnostics([base, left, right, good], .consistentSuperTypes).isEmpty)
    }

    /// Checks substitutions against parameterised superclass bounds.
    @Test("Inherited parameterised bounds retain their actual arguments")
    func inheritedArgumentBounds() {
        var base = EClass(name: "Base"); base.eTypeParameters = [ETypeParameter(name: "T")]
        var child = EClass(name: "Child")
        child.eGenericSuperTypes = [EGenericType(eClassifier: base, eTypeArguments: [EGenericType(eClassifier: Self.string)])]
        var sequence = EClass(name: "Sequence")
        sequence.eTypeParameters = [ETypeParameter(name: "T", eBounds: [
            EGenericType(eClassifier: base, eTypeArguments: [EGenericType(eClassifier: EcorePackage.dataType(.eInt))]),
        ])]
        var operation = EOperation(name: "run")
        operation.eGenericType = EGenericType(eClassifier: sequence, eTypeArguments: [EGenericType(eClassifier: child)])
        let owner = EClass(name: "Owner", eOperations: [operation])
        #expect(diagnostics([base, child, sequence, owner], .consistentArguments).count == 1)
    }

    /// Checks upper and lower bounds against the same required class bound.
    @Test("Wildcard lower bounds must satisfy declaration bounds")
    func lowerBoundSubstitution() {
        let base = EClass(name: "Base")
        var sequence = EClass(name: "Sequence")
        sequence.eTypeParameters = [ETypeParameter(name: "T", eBounds: [EGenericType(eClassifier: base)])]
        var operation = EOperation(name: "run")
        operation.eGenericType = EGenericType(eClassifier: sequence, eTypeArguments: [
            EGenericType(eLowerBound: EGenericType(eClassifier: Self.string)),
        ])
        #expect(diagnostics([base, sequence, EClass(name: "Owner", eOperations: [operation])], .consistentArguments).count == 1)
    }

    /// Checks proxies on each retained reference family and their saved spelling.
    @Test("Unresolved non-type references remain visible to validation and saving")
    func otherProxyFeatures() async throws {
        let text = """
        <ecore:EPackage xmlns:ecore="http://www.eclipse.org/emf/2002/Ecore"
          xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" name="sample" nsURI="urn:test:sample" nsPrefix="sample">
          <eClassifiers xsi:type="ecore:EClass" name="Owner" eSuperTypes="absent.ecore#//Base">
            <eAnnotations source="urn:test:annotation" references="absent.ecore#//Other"/>
            <eOperations name="run" eExceptions="absent.ecore#//Failure"><eGenericType eTypeParameter="absent.ecore#//Other/T"/></eOperations>
            <eStructuralFeatures xsi:type="ecore:EReference" name="items" eType="#//Owner"
              eOpposite="absent.ecore#//Other/owner" eKeys="absent.ecore#//Other/key"/>
          </eClassifiers>
        </ecore:EPackage>
        """
        let resource = try await ResourceSet().loadEcoreResource(text: text, uri: "memory:/sample.ecore",
            options: EcoreLoadOptions(unresolvedReferences: .keepAsProxies))
        let package = try #require(await resource.getRootObjects().first as? EPackage)
        let findings = EcoreValidator().validate(MetamodelIndex(roots: [package])).filter { $0.code == .everyProxyResolves }
        #expect(Set(findings.compactMap(\.feature)) == [.eSuperTypes, .references, .eExceptions, .eOpposite, .eKeys, .eTypeParameter])
        let written = XMISerializer().serialize(package)
        for fragment in ["Base", "Other", "Failure", "Other/owner", "Other/key", "Other/T"] {
            #expect(written.contains("absent.ecore#//" + fragment))
        }
    }

    /// Checks direct bounds prohibit forward references while nested recursive bounds are legal.
    @Test("Type parameter bounds respect declaration order", arguments: [0, 1, 2])
    func orderedBounds(kind: Int) {
        var first = ETypeParameter(name: "T")
        let second = ETypeParameter(name: "U")
        if kind == 0 { first.eBounds = [EGenericType(eTypeParameter: second.id)] }
        else if kind == 1 { first.eBounds = [EGenericType(eTypeParameter: first.id)] }
        else {
            var bound = EClass(name: "Bound"); bound.eTypeParameters = [ETypeParameter(name: "V")]
            first.eBounds = [EGenericType(eClassifier: bound, eTypeArguments: [EGenericType(eTypeParameter: first.id)])]
        }
        var owner = EClass(name: "Owner"); owner.eTypeParameters = [first, second]
        #expect(diagnostics([owner], .consistentType).count == (kind == 2 ? 0 : 1))
    }

}
