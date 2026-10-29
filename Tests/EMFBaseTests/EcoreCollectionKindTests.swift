//
// EcoreCollectionKindTests.swift
// EMFBaseTests
//
// Created by Rene Hexel on 30/10/2026.
// Copyright © 2026 Rene Hexel. All rights reserved.
//

import Testing

@testable import EMFBase

@Suite("Ecore collection kinds")
struct EcoreCollectionKindTests {

    // MARK: - Kind properties

    @Test(
        "Each kind reports whether it is ordered and unique",
        arguments: [
            (EcoreCollectionKind.sequence, true, false),
            (EcoreCollectionKind.orderedSet, true, true),
            (EcoreCollectionKind.set, false, true),
            (EcoreCollectionKind.bag, false, false),
        ])
    func orderedAndUnique(_ kind: EcoreCollectionKind, _ ordered: Bool, _ unique: Bool) {
        #expect(kind.isOrdered == ordered)
        #expect(kind.isUnique == unique)
        #expect(EcoreCollectionKind(ordered: ordered, unique: unique) == kind)
    }

    @Test("Every kind is listed exactly once")
    func allCases() {
        #expect(EcoreCollectionKind.allCases == [.sequence, .orderedSet, .set, .bag])
    }

    // MARK: - Arrays

    @Test("An array without an explicit kind is a sequence")
    func defaultKind() {
        #expect(EcoreValueArray([1, 2]).kind == .sequence)
        #expect(EcoreValueArray([]).kind == .sequence)
    }

    @Test("An array keeps the kind it was created with", arguments: EcoreCollectionKind.allCases)
    func explicitKind(_ kind: EcoreCollectionKind) {
        let array = EcoreValueArray(["a", "b"], kind: kind)
        #expect(array.kind == kind)
        #expect(array.values.count == 2)
        #expect(array.values.first as? String == "a")
    }

    @Test("The single-argument initialiser remains usable as a function")
    func initialiserReference() {
        let make: ([any EcoreValue]) -> EcoreValueArray = EcoreValueArray.init
        #expect(make([1]).kind == .sequence)
    }

    @Test("Arrays of different kinds with equal elements are equal", arguments: EcoreCollectionKind.allCases)
    func kindIgnoredByEquality(_ kind: EcoreCollectionKind) {
        let plain = EcoreValueArray([1, "a"])
        let kinded = EcoreValueArray([1, "a"], kind: kind)
        #expect(plain == kinded)
        #expect(plain.hashValue == kinded.hashValue)
        #expect(Set<EcoreValueArray>([plain, kinded]).count == 1)
        #expect(areEqual(plain, kinded))
    }

    @Test("Arrays with different elements remain unequal whatever their kind")
    func elementsStillCompared() {
        #expect(EcoreValueArray([1, 2], kind: .set) != EcoreValueArray([2, 1], kind: .set))
        #expect(EcoreValueArray([1], kind: .bag) != EcoreValueArray([1, 1], kind: .bag))
    }

    @Test("Nested arrays of different kinds compare and hash alike", arguments: EcoreCollectionKind.allCases)
    func nestedKindIgnored(_ kind: EcoreCollectionKind) {
        let plain = EcoreValueArray([EcoreValueArray([1, 2])])
        let kinded = EcoreValueArray([EcoreValueArray([1, 2], kind: kind)], kind: kind)
        #expect(plain == kinded)
        #expect(plain.hashValue == kinded.hashValue)
        var plainHasher = Hasher()
        var kindedHasher = Hasher()
        hash(EcoreValueArray([1, 2]), into: &plainHasher)
        hash(EcoreValueArray([1, 2], kind: kind), into: &kindedHasher)
        #expect(plainHasher.finalize() == kindedHasher.finalize())
    }

    @Test("The textual form does not depend on the kind", arguments: EcoreCollectionKind.allCases)
    func descriptionUnchanged(_ kind: EcoreCollectionKind) {
        let kinded = EcoreValueArray([1, "a", EcoreValueArray([2], kind: kind)], kind: kind)
        let plain = EcoreValueArray([1, "a", EcoreValueArray([2])])
        #expect(String(describing: kinded) == String(describing: plain))
        #expect(String(reflecting: kinded) == String(reflecting: plain))
        #expect(String(describing: plain).hasPrefix("EcoreValueArray(values: [1, \"a\", "))
        #expect(!String(describing: kinded).contains("kind"))
    }

    @Test("Reflection exposes the elements only")
    func mirrorChildren() {
        let mirror = Mirror(reflecting: EcoreValueArray([1], kind: .set))
        #expect(mirror.children.map(\.label) == ["values"])
        #expect(mirror.displayStyle == .struct)
    }
}
