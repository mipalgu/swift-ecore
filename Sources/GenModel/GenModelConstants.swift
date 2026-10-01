//
// GenModelConstants.swift
// GenModel
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore

/// The single authoritative source of names used by the generator model code.
///
/// Every namespace URI, class name, feature name and enumeration literal that the
/// `GenModel` target refers to by name is defined here, so that no other file
/// contains a string with metamodel meaning.
///
/// The names mirror the published generator metamodel, which is the interface that
/// `.genmodel` files depend on.
public enum GenModelConstants {
    /// The namespace URI of the generator metamodel.
    public static let nsURI = "http://www.eclipse.org/emf/2002/GenModel"

    /// The namespace prefix of the generator metamodel.
    public static let nsPrefix = "genmodel"

    /// The name of the generator metamodel package.
    public static let packageName = "genmodel"

    /// The annotation source used for documentation annotations of the generator metamodel.
    public static let documentationSource = AnnotationSource.genModel

    /// The annotation detail key holding documentation text.
    public static let documentationKey = AnnotationSource.GenModelKey.documentation

    /// The file extension of generator model files.
    public static let genModelFileExtension = "genmodel"

    /// The base name of the bundled generator metamodel resource.
    public static let metamodelResourceName = "GenModel"

    /// The file extension of the bundled generator metamodel resource.
    public static let metamodelResourceExtension = "ecore"

    /// The directory holding bundled resources.
    public static let resourceDirectory = "Resources"

    /// The separator between a document location and a fragment in a reference.
    public static let fragmentSeparator: Character = "#"

    /// The prefix of a fragment path.
    public static let fragmentPathPrefix = "//"

    /// The separator between segments of a fragment path.
    public static let pathSeparator: Character = "/"

    /// The prefix of a positional fragment segment.
    public static let positionalSegmentPrefix: Character = "@"

    /// The separator between a positional segment's feature name and its index.
    public static let positionSeparator: Character = "."

    /// The name of the Ecore feature holding the classifiers of a package.
    public static let classifiersFeature = "eClassifiers"

    /// The name of the Ecore feature holding the structural features of a class.
    public static let structuralFeaturesFeature = "eStructuralFeatures"

    /// The name of the Ecore feature holding the subpackages of a package.
    public static let subpackagesFeature = "eSubpackages"

    /// The name of the Ecore feature holding the literals of an enumeration.
    public static let literalsFeature = "eLiterals"

    /// The names of the metaclasses of the generator metamodel.
    public enum ClassName {
        /// The root generator model class.
        public static let genModel = "GenModel"
        /// The class holding the settings of an Ecore package.
        public static let genPackage = "GenPackage"
        /// The class holding the settings of an Ecore class.
        public static let genClass = "GenClass"
        /// The class holding the settings of a structural feature.
        public static let genFeature = "GenFeature"
        /// The abstract base of all generator elements.
        public static let genBase = "GenBase"
        /// The class holding the settings of an enumeration.
        public static let genEnum = "GenEnum"
        /// The class holding the settings of an enumeration literal.
        public static let genEnumLiteral = "GenEnumLiteral"
        /// The abstract base of generator classifiers.
        public static let genClassifier = "GenClassifier"
        /// The class holding the settings of a data type.
        public static let genDataType = "GenDataType"
        /// The class holding the settings of an operation.
        public static let genOperation = "GenOperation"
        /// The class holding the settings of an operation parameter.
        public static let genParameter = "GenParameter"
        /// The abstract base of typed generator elements.
        public static let genTypedElement = "GenTypedElement"
        /// The class holding a generator annotation.
        public static let genAnnotation = "GenAnnotation"
        /// The class holding the settings of a type parameter.
        public static let genTypeParameter = "GenTypeParameter"

        /// All metaclass names, in metamodel order.
        public static let all: [String] = [
            genModel, genPackage, genClass, genFeature, genBase, genEnum, genEnumLiteral,
            genClassifier, genDataType, genOperation, genParameter, genTypedElement,
            genAnnotation, genTypeParameter,
        ]
    }

    /// The names of enumeration literals of the generator metamodel that the facade interprets.
    public enum LiteralName {
        /// The rich client platform literal of the runtime platform.
        public static let richClientPlatform = "RCP"
        /// The rich Ajax platform literal of the runtime platform.
        public static let richAjaxPlatform = "RAP"
        /// The reflective literal of the delegation kind.
        public static let reflectiveDelegation = "Reflective"
    }

    /// The names of the enumerations of the generator metamodel.
    public enum EnumName {
        /// How item providers are created.
        public static let genProviderKind = "GenProviderKind"
        /// How a feature is exposed as a property.
        public static let genPropertyKind = "GenPropertyKind"
        /// The kind of resource generated for a package.
        public static let genResourceKind = "GenResourceKind"
        /// The feature delegation strategy.
        public static let genDelegationKind = "GenDelegationKind"
        /// The compliance level of generated code.
        public static let genJDKLevel = "GenJDKLevel"
        /// The targeted runtime version.
        public static let genRuntimeVersion = "GenRuntimeVersion"
        /// The targeted runtime platform.
        public static let genRuntimePlatform = "GenRuntimePlatform"
        /// The label decoration kind.
        public static let genDecoration = "GenDecoration"
        /// The targeted host platform release.
        public static let genEclipsePlatformVersion = "GenEclipsePlatformVersion"
        /// The code style clean-ups.
        public static let genCodeStyle = "GenCodeStyle"
        /// The bundle packaging styles.
        public static let genOSGiStyle = "GenOSGiStyle"

        /// All enumeration names, in metamodel order.
        public static let all: [String] = [
            genProviderKind, genPropertyKind, genResourceKind, genDelegationKind, genJDKLevel,
            genRuntimeVersion, genRuntimePlatform, genDecoration, genEclipsePlatformVersion,
            genCodeStyle, genOSGiStyle,
        ]
    }

    /// The names of the data types of the generator metamodel.
    public enum DataTypeName {
        /// A workspace-relative path.
        public static let path = "Path"
        /// The name of a property editor factory.
        public static let propertyEditorFactory = "PropertyEditorFactory"

        /// All data type names, in metamodel order.
        public static let all: [String] = [path, propertyEditorFactory]
    }

    /// The names of the features that the generator code refers to.
    public enum FeatureName {
        /// Names of the source models of a generator model.
        public static let foreignModel = "foreignModel"
        /// The generator packages owned by a generator model.
        public static let genPackages = "genPackages"
        /// The generator packages used by a generator model.
        public static let usedGenPackages = "usedGenPackages"
        /// The nested generator packages of a package.
        public static let nestedGenPackages = "nestedGenPackages"
        /// The generator classes of a package.
        public static let genClasses = "genClasses"
        /// The generator enumerations of a package.
        public static let genEnums = "genEnums"
        /// The generator data types of a package.
        public static let genDataTypes = "genDataTypes"
        /// The generator features of a class.
        public static let genFeatures = "genFeatures"
        /// The generator operations of a class.
        public static let genOperations = "genOperations"
        /// The generator parameters of an operation.
        public static let genParameters = "genParameters"
        /// The generator literals of an enumeration.
        public static let genEnumLiterals = "genEnumLiterals"
        /// The generator type parameters of a classifier or operation.
        public static let genTypeParameters = "genTypeParameters"
        /// The generator annotations of an element.
        public static let genAnnotations = "genAnnotations"
        /// The explicit label feature of a class.
        public static let labelFeature = "labelFeature"
        /// The Ecore package of a generator package.
        public static let ecorePackage = "ecorePackage"
        /// The Ecore class of a generator class.
        public static let ecoreClass = "ecoreClass"
        /// The Ecore feature of a generator feature.
        public static let ecoreFeature = "ecoreFeature"
        /// The Ecore enumeration of a generator enumeration.
        public static let ecoreEnum = "ecoreEnum"
        /// The Ecore literal of a generator literal.
        public static let ecoreEnumLiteral = "ecoreEnumLiteral"
        /// The Ecore data type of a generator data type.
        public static let ecoreDataType = "ecoreDataType"
        /// The Ecore operation of a generator operation.
        public static let ecoreOperation = "ecoreOperation"
        /// The Ecore parameter of a generator parameter.
        public static let ecoreParameter = "ecoreParameter"
        /// The Ecore type parameter of a generator type parameter.
        public static let ecoreTypeParameter = "ecoreTypeParameter"
        /// The derived classifiers of a generator package.
        public static let genClassifiers = "genClassifiers"
        /// The generator package that owns a classifier.
        public static let genPackage = "genPackage"
        /// The generator model that owns a generator package.
        public static let genModel = "genModel"
        /// The targeted runtime platform of a generator model.
        public static let runtimePlatform = "runtimePlatform"
        /// The feature delegation strategy of a generator model.
        public static let featureDelegation = "featureDelegation"
        /// The derived flag that tells whether the runtime platform is a rich client.
        public static let richClientPlatform = "richClientPlatform"
        /// The derived flag that tells whether the runtime platform is a rich Ajax client.
        public static let richAjaxPlatform = "richAjaxPlatform"
        /// The derived flag that tells whether features delegate reflectively.
        public static let reflectiveDelegation = "reflectiveDelegation"
        /// The prefix of a generator package.
        public static let prefix = "prefix"
        /// The name of a generator model.
        public static let modelName = "modelName"

        /// The containment features of the generator metamodel, which define element ownership.
        public static let containments: [String] = [
            genPackages, nestedGenPackages, genClasses, genEnums, genDataTypes, genFeatures,
            genOperations, genParameters, genEnumLiterals, genTypeParameters, genAnnotations,
        ]

        /// The features that refer to Ecore elements.
        public static let ecoreReferences: [String] = [
            ecorePackage, ecoreClass, ecoreFeature, ecoreEnum, ecoreEnumLiteral, ecoreDataType,
            ecoreOperation, ecoreParameter, ecoreTypeParameter,
        ]
    }

    /// Names and words of Ecore conventions that the facade interprets.
    public enum EcoreConvention {
        /// The names of the two features that make a class a map entry.
        public static let mapEntryFeatureNames = ["key", "value"]

        /// The instance type names that mark a class as a map entry.
        public static let mapEntryInstanceTypeNames: Set<String> = [
            "java.util.Map$Entry", "java.util.Map.Entry",
        ]

        /// The type qualifiers that may precede a location in an Ecore reference.
        public static let referenceTypeQualifiers: Set<String> = [
            "ecore:EAttribute", "ecore:EReference", "ecore:EClass", "ecore:EEnum",
            "ecore:EEnumLiteral", "ecore:EDataType", "ecore:EOperation", "ecore:EParameter",
            "ecore:EPackage", "ecore:ETypeParameter",
        ]

        /// The word that marks a feature name as a label candidate.
        public static let nameWord = "name"

        /// The feature name that marks an identifying feature.
        public static let identifierName = "id"
    }
}
