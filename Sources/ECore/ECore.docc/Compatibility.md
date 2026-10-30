# Compatibility with 0.6

Keep the behaviour of version 0.6, or opt in to newer behaviour.

## Overview

Every API of version 0.6 is still available and behaves as it did in 0.6. Newer behaviour is
offered through additional API, whose default is the new behaviour.

### Container lookup scope

A resource finds the container of an object among its own objects. The contained object may
now also belong to another resource, or may have been removed from the resource of its
container, and still have its container found.

- New default: ``Resource/container(ofIdentifier:scope:)``,
  ``ResourceSet/container(ofIdentifier:scope:)``, and the ``ContainerLookupScope/standard`` scope
  (``ContainerLookupScope/anyResource``, also ``ContainerLookupScope/init()``) answer for an
  object of any resource.
- Option: the `scope` argument of ``Resource/eContainer(of:scope:)`` and
  ``Resource/eContainingFeature(of:scope:)``, or a scope configured for the resource with
  ``Resource/setContainerLookupScope(_:)`` or for all resources of a set with
  ``ResourceSet/setDefaultContainerLookupScope(_:)`` or
  ``ResourceSet/init(defaultContainerLookupScope:)``.
- 0.6 behaviour: ``Resource/eContainer(of:scope:)`` and
  ``Resource/eContainingFeature(of:scope:)`` without a scope, unless one is configured, or the
  ``ContainerLookupScope/thisResource`` scope (``ContainerLookupScope/legacy``). An object
  held by identifier is answered only while the resource can resolve it, and an object that
  its container embeds as a value always is.

```swift
let container = await resource.eContainer(of: object, scope: .anyResource)
let legacyContainer = await resource.eContainer(of: object)
```

Without a `scope` argument, or with `nil`, a lookup uses the scope configured for the
resource. The first of these that is set applies:

| Configuration | Set with |
|--|--|
| The resource's own scope | ``Resource/setContainerLookupScope(_:)`` |
| The default of its resource set | ``ResourceSet/setDefaultContainerLookupScope(_:)`` |
| The built-in default, ``ContainerLookupScope/thisResource`` | ``ContainerLookupScope/builtInDefault``, which is fixed |

``Resource/containerLookupScope`` reports the scope that applies, and
``Resource/configuredContainerLookupScope`` the configured one, if any. A resource keeps the
default of its set after the set has been released, as it keeps the set's metamodels.

``Resource/container(ofIdentifier:scope:)`` and ``ResourceSet/container(ofIdentifier:scope:)``
also follow a configured scope, but when none is configured they answer for an object of any
resource, as they did before the scope could be configured.

```swift
let resourceSet = ResourceSet(defaultContainerLookupScope: .anyResource)
let resource = await resourceSet.createResource(uri: "models/company.xmi")
let container = await resource.eContainer(of: object)  // any resource
await resource.setContainerLookupScope(.thisResource)
let legacyContainer = await resource.eContainer(of: object)  // this resource only
```

### Choosing the semantics

``ModellingSemantics`` names the two sets of behaviours, `standard` and `legacy`, of all the
modelling languages, and ``ModellingSemantics/fromEnvironment(_:)`` reads a choice from the
`SWIFT_MODELLING_SEMANTICS` environment variable. ``ContainerLookupScope/init(semantics:)``
selects the matching scope:

```swift
if let semantics = try ModellingSemantics.fromEnvironment() {
    await resourceSet.setDefaultContainerLookupScope(ContainerLookupScope(semantics: semantics))
}
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
- ``Resource/container(ofIdentifier:scope:)``
- ``ResourceSet/container(ofIdentifier:scope:)``

### Configuring the Container Lookup Scope

- ``Resource/containerLookupScope``
- ``Resource/configuredContainerLookupScope``
- ``Resource/containerLookupScopeOverride``
- ``Resource/setContainerLookupScope(_:)``
- ``ResourceSet/defaultContainerLookupScope``
- ``ResourceSet/setDefaultContainerLookupScope(_:)``
- ``ResourceSet/init(defaultContainerLookupScope:)``
- ``ContainerLookupScope/builtInDefault``

### Semantics

- ``ModellingSemantics``
- ``ModellingSemanticsError``
