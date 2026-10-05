//
// MetamodelDiff.swift
// ECoreEdit
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase

/// Describes the difference between two states of a document as a change set.
enum MetamodelDiff {
    /// Compares two documents by comparing their indices.
    ///
    /// Elements are matched by identifier. The result lists the elements that appeared and
    /// disappeared, the elements that moved to another container or feature, the properties
    /// whose values differ, and the containers whose children differ.
    ///
    /// - Parameters:
    ///   - old: The document before.
    ///   - new: The document after.
    ///   - label: The label of the change set.
    /// - Returns: The change set that leads from `old` to `new`.
    static func changeSet(from old: MetamodelDocument, to new: MetamodelDocument, label: String)
        -> MetamodelChangeSet
    {
        var removed: Set<EUUID> = []
        var removedTops: [(EcoreElement, EcoreContainment?)] = []
        for element in old.index.allElements where !new.index.contains(element.id) {
            removed.insert(element.id)
        }
        for element in old.index.allElements where removed.contains(element.id) {
            let place = old.index.container(of: element.id)
            if place == nil || !removed.contains(place?.container ?? element.id) { removedTops.append((element, place)) }
        }
        var added: Set<EUUID> = []
        var addedTops: [(EcoreElement, EcoreContainment?)] = []
        var changes: [MetamodelChange] = []
        var modified: [EUUID: Set<EcoreFeatureName>] = [:]
        var structure: Set<EUUID> = []
        var sets: [MetamodelChange] = []
        var moves: [MetamodelChange] = []
        for element in new.index.allElements {
            let identifier = element.id
            let place = new.index.container(of: identifier)
            guard let before = old.index.element(identifier), !old.index.isExternal(identifier) else {
                added.insert(identifier)
                continue
            }
            if let oldPlace = old.index.container(of: identifier), let place {
                if oldPlace.container != place.container || oldPlace.feature != place.feature {
                    moves.append(
                        MetamodelChange(
                            kind: .move, element: identifier, feature: place.feature,
                            oldValue: .identifier(oldPlace.container), newValue: .identifier(place.container),
                            index: place.index, oldIndex: oldPlace.index, oldFeature: oldPlace.feature))
                    structure.insert(oldPlace.container)
                    structure.insert(place.container)
                } else if oldPlace.index != place.index {
                    structure.insert(place.container)
                }
            }
            for descriptor in EcoreEditSchema.propertyDescriptors[element.kind] ?? [] {
                guard let metaFeature = EcorePackage.feature(descriptor.feature, of: element.kind) else { continue }
                let oldValue = EditValue(before.object.eGet(metaFeature))
                let newValue = EditValue(element.object.eGet(metaFeature))
                guard oldValue != newValue else { continue }
                sets.append(
                    MetamodelChange(
                        kind: .set, element: identifier, feature: descriptor.feature, oldValue: oldValue,
                        newValue: newValue))
                modified[identifier, default: []].insert(descriptor.feature)
            }
        }
        for element in new.index.allElements where added.contains(element.id) {
            let place = new.index.container(of: element.id)
            if place == nil || !added.contains(place?.container ?? element.id) { addedTops.append((element, place)) }
        }
        for (element, place) in removedTops {
            changes.append(
                MetamodelChange(
                    kind: .remove, element: element.id, feature: place?.feature,
                    oldValue: place.map { .identifier($0.container) }, index: place?.index))
            if let place { structure.insert(place.container) }
        }
        for (element, place) in addedTops {
            changes.append(
                MetamodelChange(
                    kind: .add, element: element.id, feature: place?.feature,
                    newValue: place.map { .identifier($0.container) }, index: place?.index))
            if let place { structure.insert(place.container) }
        }
        changes += moves + sets
        structure.subtract(removed)
        structure.subtract(added)
        let affected = LabelImpact.affected(modified: modified, structure: structure, added: added, index: new.index)
        return MetamodelChangeSet(
            label: label, changes: changes, added: added, removed: removed, modified: modified,
            structureChanged: structure, labelsAffected: affected.subtracting(removed))
    }
}
