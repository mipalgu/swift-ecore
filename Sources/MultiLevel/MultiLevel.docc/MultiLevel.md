# ``MultiLevel``

@Metadata {
    @DisplayName("MultiLevel")
}

Native multi-level (deep) modelling with clabjects, levels and potency.

## Overview

Ecore has a single boundary between types and instances. Domains with types of types,
such as product types and products or task kinds and tasks, need more levels. MultiLevel
models such domains directly: a ``DeepModel`` is a chain of ``LevelModel``s, each an
ontological instance of the one above, whose ``Clabject``s are at once classes and
objects.

```
Model Commerce@2 {
  Node ProductType {
    vat@1 : double = 7.5;
    price : double;
  }
}
Commerce Store {
  ProductType Book { vat = 4.0; }
}
Store Shop {
  Book manual { price = 35.0; }
}
```

``Potency`` states over how many levels an element can still be instantiated. A
``PotencyScheme`` decides what a feature is at each level: ``MetaDepthPotencyScheme``
gives every feature a single potency, and ``MelaneePotencyScheme`` separates durability
from mutability and admits the unbounded potency `*`. A model selects its scheme.

Models are written in the MetaDepth notation (``MetaDepthReader`` and
``MetaDepthWriter``) and interchanged losslessly as XMI or JSON instances of the bundled
linguistic metamodel (``MultiLevelPackage`` and ``LinguisticEncoding``).
``MetaDepthFormatHandler`` makes the notation available to ``ECore/ModelIO``.

### Strictness

By default (``LevelCrossingPolicy/strict``), references connect clabjects of one level;
deep references (`T@0`), leap potency (`@(2)`) and references declared with a target level
(`{level=1}`) are the sanctioned crossings, and any other crossing is an error.
``LevelCrossingPolicy/nonStrict`` lets any reference cross levels.

### Views for Ecore tools

A ``DeepLevelView`` presents one level to unchanged Ecore tools: every type facet above
the level becomes a class whose supertypes include its ontological type, so that type
tests and instance queries of AQL, ATL and MTL find deep instances. A ``LevelPairView``
presents two adjacent levels as an editable metamodel and model and commits changes back.

### Constraints

Constraints carry a potency and are written in AQL. ``DeepModel/validate(evaluator:)``
checks the structure of a model and evaluates its constraints on the deep instances at
the levels their potencies select, through a ``DeepConstraintEvaluator`` such as the one
of the AQL package.

## Topics

### Models

- ``DeepModel``
- ``LevelModel``
- ``Clabject``
- ``DeepFeature``
- ``DeepSlot``
- ``DeepValue``
- ``DeepConstraint``
- ``EdgeEnds``
- ``EdgeEnd``

### Potency

- ``Potency``
- ``PotencyVariant``
- ``PotencyScheme``
- ``MetaDepthPotencyScheme``
- ``MelaneePotencyScheme``
- ``FeatureRole``

### Text and Interchange

- ``MetaDepthReader``
- ``MetaDepthWriter``
- ``MetaDepthFormatHandler``
- ``MultiLevelFormats``
- ``MultiLevelPackage``
- ``LinguisticEncoding``

### Views

- ``DeepLevelView``
- ``LevelPairView``

### Validation and Constraints

- ``LevelCrossingPolicy``
- ``DeepConstraintEvaluator``
- ``DeepConstraintContext``
- ``MultiLevelDiagnosticCode``
- ``MultiLevelError``
