# Incremental Evaluation

Observe changes to resources and record what computations read, so that results can be
brought up to date without computing them afresh.

## Overview

Query and transformation engines built on ECore can keep their results up to date as models
change, rather than evaluating everything again after each edit. ECore provides the
building blocks that such incremental evaluators share:

- **Change observation**: ``Resource/addChangeObserver(_:)`` registers a handler that receives
  the ``ResourceChange`` values of every editing operation, such as
  ``Resource/eSetWithChanges(objectId:feature:value:)``, ``Resource/eAdd(objectId:feature:value:at:)``
  and ``Resource/delete(_:cleaningReferences:)``. A ``ResourceChangeQueue`` collects them until
  the evaluator is ready to process them. While no observer is registered, editing costs
  what it did before.
- **Dependencies**: ``ModelDependencies`` names what a computation read: features of objects,
  the instances of classes, containers, or the containment structure as a whole. Evaluators
  collect them with a ``ModelDependencyRecorder`` while they evaluate.
- **Change impact**: ``ModelChangeImpact`` summarises a batch of changes in the same terms, so
  that ``ModelDependencies/isAffected(by:)`` decides whether a computation must be redone.
- **Reverse index**: ``ModelDependencyIndex`` finds the affected computations among many in
  time proportional to the size of the changes, as incremental pattern matchers do.
- **Cache invalidation**: ``ECoreExecutionEngine/invalidateCaches(for:)`` discards exactly the
  cached navigation results that changes may have made stale.

### Observing a Resource

```swift
let queue = ResourceChangeQueue()
let observation = await queue.observe(resource)
try await resource.eSetWithChanges(objectId: person.id, feature: "age", value: 42)
let impact = await ModelChangeImpact(changes: queue.drain(), in: [resource])
if dependencies.isAffected(by: impact) {
    // compute the result again
}
await resource.removeChangeObserver(observation)
```

Only the editing operations that report changes call observers. Operations that do not
report changes, such as ``Resource/eSet(objectId:feature:value:)`` and ``Resource/add(_:)``,
are meant for building models and are not observed.

## Topics

### Observing Changes

- ``Resource/addChangeObserver(_:)``
- ``Resource/removeChangeObserver(_:)``
- ``ResourceChangeObservation``
- ``ResourceChangeQueue``
- ``ResourceChange``

### Recording Dependencies

- ``ModelDependencies``
- ``ModelFeatureKey``
- ``ModelDependencyRecorder``
- ``ModelDependencyIndex``
- ``ModelChangeImpact``
