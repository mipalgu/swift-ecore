# Compatibility with 0.6

Keep the behaviour of version 0.6, or opt in to newer behaviour.

## Overview

Every API of version 0.6 is still available and behaves as it did in 0.6. Newer behaviour is
offered through additional API, whose default is the new behaviour.

### Container lookup scope

A resource finds the container of an object among its own objects. The contained object may
now also belong to another resource, or may have been removed from the resource of its
container, and still have its container found.

- New default: ``Resource/container(ofIdentifier:)``,
  ``ResourceSet/container(ofIdentifier:)``, and the ``ContainerLookupScope/standard`` scope
  (``ContainerLookupScope/anyResource``, also ``ContainerLookupScope/init()``) answer for an
  object of any resource.
- Option: the `scope` argument of ``Resource/eContainer(of:scope:)`` and
  ``Resource/eContainingFeature(of:scope:)``.
- 0.6 behaviour: ``Resource/eContainer(of:)`` and ``Resource/eContainingFeature(of:)``, or the
  ``ContainerLookupScope/thisResource`` scope (``ContainerLookupScope/legacy``). An object
  held by identifier is answered only while the resource can resolve it, and an object that
  its container embeds as a value always is.

```swift
let container = await resource.eContainer(of: object, scope: .anyResource)
let legacyContainer = await resource.eContainer(of: object)
```

### Collection kinds

`EcoreValueArray` records the kind of collection it represents. Arrays created with
`EcoreValueArray(_:)` are sequences, as before, and the kind takes no part in equality,
hashing or the textual form of an array, so code written for version 0.6 is unaffected.

## Topics

### Container Lookup

- ``ContainerLookupScope``
- ``Resource/eContainer(of:scope:)``
- ``Resource/eContainingFeature(of:scope:)``
- ``Resource/container(ofIdentifier:)``
- ``ResourceSet/container(ofIdentifier:)``
