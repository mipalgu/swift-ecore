//
// UMLToEcoreSyntax.swift
// ECore
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import Foundation

extension UMLToEcore {
    /// The names, annotation sources and library mappings that the conversion of UML class
    /// models into Ecore metamodels relies on.
    ///
    /// The names are those of the Eclipse UML2 5.x metamodel, of its Ecore profile and of the
    /// annotations that Eclipse UML2 and Eclipse OCL write into the Ecore metamodels they
    /// produce, so that a converted metamodel carries the same annotations as one that Eclipse
    /// converts.
    public enum Syntax {
        // MARK: - Annotation sources

        /// The source of the annotations with which Eclipse UML2 records the original name of
        /// a renamed element (detail ``originalNameKey``).
        public static let umlAnnotationSource = UMLNamespaces.annotationSource

        /// The detail key under which the original name of a renamed element is kept.
        public static let originalNameKey = "originalName"

        /// The source of the operation bodies and initial values whose language is not OCL,
        /// or that are not evaluated by a delegate.
        public static let uml2GenModel = "http://www.eclipse.org/uml2/1.1.0/GenModel"

        /// The delegate URI of the Eclipse OCL Pivot evaluator, under which OCL constraints,
        /// operation bodies and initial values are recorded by default.
        public static let oclPivotDelegate = "http://www.eclipse.org/emf/2002/Ecore/OCL/Pivot"

        /// The delegate URI of the classic Eclipse OCL evaluator, which Eclipse UML2 uses unless told otherwise.
        public static let oclDelegate = AnnotationSource.ocl

        /// The source of the annotation that marks a derived union.
        public static let unionAnnotation = "union"

        /// The source of the annotation that lists the features or operations that an element redefines.
        public static let redefinesAnnotation = "redefines"

        /// The source of the annotation that lists the features that a feature subsets.
        public static let subsetsAnnotation = "subsets"

        /// The source of the annotation that holds the features and operations of a class
        /// that duplicate inherited ones.
        public static let duplicatesAnnotation = "duplicates"

        /// The source of the annotation that records the name of the opposite end of a
        /// unidirectional reference, as EMF's EMOF support records it.
        public static let oppositeRoleNameAnnotation = "http://schema.omg.org/spec/MOF/2.0/emof.xml#Property.oppositeRoleName"

        /// The detail key of the body of an operation, and of the opposite role name.
        public static let bodyKey = "body"

        /// The detail key of an initial value expression.
        public static let initialKey = "initial"

        /// The detail key of a derivation expression.
        public static let derivationKey = "derivation"

        /// The detail key with which a GenModel annotation suppresses the visibility of an operation.
        public static let suppressedVisibilityKey = "suppressedVisibility"

        /// The detail key with which extended metadata names the base type of a data type.
        public static let baseTypeKey = "baseType"

        /// The language name of OCL expressions.
        public static let oclLanguage = "OCL"

        /// The language name of Java expressions.
        public static let javaLanguage = "Java"

        /// The prefix of an OCL body expression that names its result.
        static let resultPrefix = "result"

        /// The names of the parameters of an invariant operation.
        static let invariantParameters = (diagnostics: "diagnostics", context: "context")

        /// The documentation of the parameters of an invariant operation.
        static let invariantParameterDocumentation = (
            diagnostics: "The chain of diagnostics to which problems are to be appended.",
            context: "The cache of context-specific information."
        )

        /// The separator of the parts of a qualified name in diagnostics.
        static let qualifiedNameSeparator = "::"

        /// The prefix of the role names of metaclass ends of extensions.
        static let metaclassRolePrefix = "base_"

        /// The instance type name of the optional data type of an enumeration.
        static let enumeratorTypeName = "org.eclipse.emf.common.util.Enumerator"

        /// The suffix of the name of the optional data type of an enumeration.
        static let optionalEnumSuffix = "_Optional"

        /// The prefix of the namespace URI of a package that has no URI of its own.
        static let derivedNamespacePrefix = "http:///"

        /// The suffix of the namespace URI of a package that has no URI of its own.
        static let derivedNamespaceSuffix = ".ecore"

        /// The suffix that distinguishes the URI of a converted metamodel from that of its UML model.
        static let convertedDocumentSuffix = ".ecore"

        // MARK: - UML metaclasses

        /// The names of the UML metaclasses that the conversion distinguishes.
        enum Metaclass {
            /// The `Package` metaclass.
            static let package = "Package"
            /// The `Class` metaclass.
            static let `class` = "Class"
            /// The `Interface` metaclass.
            static let interface = "Interface"
            /// The `DataType` metaclass.
            static let dataType = "DataType"
            /// The `Enumeration` metaclass.
            static let enumeration = "Enumeration"
            /// The `PrimitiveType` metaclass.
            static let primitiveType = "PrimitiveType"
            /// The `EnumerationLiteral` metaclass.
            static let enumerationLiteral = "EnumerationLiteral"
            /// The `Property` metaclass.
            static let property = "Property"
            /// The `Operation` metaclass.
            static let operation = "Operation"
            /// The `Parameter` metaclass.
            static let parameter = "Parameter"
            /// The `Generalization` metaclass.
            static let generalization = "Generalization"
            /// The `InterfaceRealization` metaclass.
            static let interfaceRealization = "InterfaceRealization"
            /// The `Comment` metaclass.
            static let comment = "Comment"
            /// The `Constraint` metaclass.
            static let constraint = "Constraint"
            /// The `Association` metaclass.
            static let association = "Association"
            /// The `Namespace` metaclass.
            static let namespace = "Namespace"
            /// The `Classifier` metaclass.
            static let classifier = "Classifier"
            /// The `TemplateSignature` metaclass.
            static let templateSignature = "TemplateSignature"
            /// The `TemplateParameter` metaclass.
            static let templateParameter = "TemplateParameter"
            /// The `TemplateBinding` metaclass.
            static let templateBinding = "TemplateBinding"
            /// The `TemplateParameterSubstitution` metaclass.
            static let templateParameterSubstitution = "TemplateParameterSubstitution"
            /// The `ParameterableElement` metaclass.
            static let parameterableElement = "ParameterableElement"
            /// The `OpaqueExpression` metaclass.
            static let opaqueExpression = "OpaqueExpression"
            /// The `OpaqueBehavior` metaclass.
            static let opaqueBehavior = "OpaqueBehavior"
            /// The `LiteralString` metaclass.
            static let literalString = "LiteralString"
            /// The `LiteralInteger` metaclass.
            static let literalInteger = "LiteralInteger"
            /// The `LiteralUnlimitedNatural` metaclass.
            static let literalUnlimitedNatural = "LiteralUnlimitedNatural"
            /// The `LiteralReal` metaclass.
            static let literalReal = "LiteralReal"
            /// The `LiteralBoolean` metaclass.
            static let literalBoolean = "LiteralBoolean"
            /// The `LiteralNull` metaclass.
            static let literalNull = "LiteralNull"
            /// The `InstanceValue` metaclass.
            static let instanceValue = "InstanceValue"
            /// The `EAnnotation` metaclass.
            static let eAnnotation = "EAnnotation"
        }

        /// The names of the features of the UML metamodel that the conversion reads.
        enum Feature {
            /// The `name` feature.
            static let name = "name"
            /// The `URI` feature.
            static let uri = "URI"
            /// The `isAbstract` feature.
            static let isAbstract = "isAbstract"
            /// The `type` feature.
            static let type = "type"
            /// The `lowerValue` feature.
            static let lowerValue = "lowerValue"
            /// The `upperValue` feature.
            static let upperValue = "upperValue"
            /// The `isOrdered` feature.
            static let isOrdered = "isOrdered"
            /// The `isUnique` feature.
            static let isUnique = "isUnique"
            /// The `isReadOnly` feature.
            static let isReadOnly = "isReadOnly"
            /// The `isDerived` feature.
            static let isDerived = "isDerived"
            /// The `isDerivedUnion` feature.
            static let isDerivedUnion = "isDerivedUnion"
            /// The `isID` feature.
            static let isID = "isID"
            /// The `aggregation` feature.
            static let aggregation = "aggregation"
            /// The `association` feature.
            static let association = "association"
            /// The `memberEnd` feature.
            static let memberEnd = "memberEnd"
            /// The `navigableOwnedEnd` feature.
            static let navigableOwnedEnd = "navigableOwnedEnd"
            /// The `ownedLiteral` feature.
            static let ownedLiteral = "ownedLiteral"
            /// The `signature` feature.
            static let signature = "signature"
            /// The `actual` feature.
            static let actual = "actual"
            /// The `formal` feature.
            static let formal = "formal"
            /// The `default` feature.
            static let `default` = "default"
            /// The `defaultValue` feature.
            static let defaultValue = "defaultValue"
            /// The `value` feature.
            static let value = "value"
            /// The `instance` feature.
            static let instance = "instance"
            /// The `body` feature.
            static let body = "body"
            /// The `language` feature.
            static let language = "language"
            /// The `annotatedElement` feature.
            static let annotatedElement = "annotatedElement"
            /// The `specification` feature.
            static let specification = "specification"
            /// The `general` feature.
            static let general = "general"
            /// The `contract` feature.
            static let contract = "contract"
            /// The `direction` feature.
            static let direction = "direction"
            /// The `raisedException` feature.
            static let raisedException = "raisedException"
            /// The `bodyCondition` feature.
            static let bodyCondition = "bodyCondition"
            /// The `method` feature.
            static let method = "method"
            /// The `redefinedProperty` feature.
            static let redefinedProperty = "redefinedProperty"
            /// The `subsettedProperty` feature.
            static let subsettedProperty = "subsettedProperty"
            /// The `redefinedOperation` feature.
            static let redefinedOperation = "redefinedOperation"
            /// The `templateParameter` feature.
            static let templateParameter = "templateParameter"
            /// The `parameter` feature.
            static let parameter = "parameter"
            /// The `ownedParameteredElement` feature.
            static let ownedParameteredElement = "ownedParameteredElement"
            /// The `parameteredElement` feature.
            static let parameteredElement = "parameteredElement"
            /// The `eAnnotations` feature.
            static let eAnnotations = "eAnnotations"
            /// The `source` feature.
            static let source = "source"
            /// The `details` feature.
            static let details = "details"
            /// The `key` feature.
            static let key = "key"
        }

        /// The values of UML enumerations that the conversion reads.
        enum Literal {
            /// The aggregation kind of composite properties.
            static let composite = "composite"
            /// The direction kind of return parameters.
            static let returnDirection = "return"
            /// The text of an unlimited upper bound.
            static let unlimited = "*"
        }

        // MARK: - The Ecore profile

        /// The name and namespace prefix of the Ecore profile.
        static let ecoreProfileName = "Ecore"

        /// The stereotypes of the Ecore profile of Eclipse UML2 and their tagged values.
        enum Stereotype {
            /// The `EPackage` stereotype.
            static let ePackage = "EPackage"
            /// The `EClass` stereotype.
            static let eClass = "EClass"
            /// The `EDataType` stereotype.
            static let eDataType = "EDataType"
            /// The `EEnum` stereotype.
            static let eEnum = "EEnum"
            /// The `EEnumLiteral` stereotype.
            static let eEnumLiteral = "EEnumLiteral"
            /// The `EOperation` stereotype.
            static let eOperation = "EOperation"
            /// The `EParameter` stereotype.
            static let eParameter = "EParameter"
            /// The `EAttribute` stereotype.
            static let eAttribute = "EAttribute"
            /// The `EReference` stereotype.
            static let eReference = "EReference"
            /// The `ETypeParameter` stereotype.
            static let eTypeParameter = "ETypeParameter"
            /// The `EGenericType` stereotype.
            static let eGenericType = "EGenericType"

            /// Every stereotype of the profile that applies to elements the conversion produces.
            static let all: Set<String> = [
                ePackage, eClass, eDataType, eEnum, eEnumLiteral, eOperation, eParameter, eAttribute, eReference,
                eTypeParameter, eGenericType,
            ]
        }

        /// The tagged values of the Ecore profile.
        enum Tag {
            /// The `annotations` tagged value.
            static let annotations = "annotations"
            /// The `attributeName` tagged value.
            static let attributeName = "attributeName"
            /// The `basePackage` tagged value.
            static let basePackage = "basePackage"
            /// The `bounds` tagged value.
            static let bounds = "bounds"
            /// The `className` tagged value.
            static let className = "className"
            /// The `dataTypeName` tagged value.
            static let dataTypeName = "dataTypeName"
            /// The `enumName` tagged value.
            static let enumName = "enumName"
            /// The `enumLiteralName` tagged value.
            static let enumLiteralName = "enumLiteralName"
            /// The `instanceClassName` tagged value.
            static let instanceClassName = "instanceClassName"
            /// The `isID` tagged value.
            static let isID = "isID"
            /// The `isResolveProxies` tagged value.
            static let isResolveProxies = "isResolveProxies"
            /// The `isTransient` tagged value.
            static let isTransient = "isTransient"
            /// The `isUnsettable` tagged value.
            static let isUnsettable = "isUnsettable"
            /// The `isVolatile` tagged value.
            static let isVolatile = "isVolatile"
            /// The `keys` tagged value.
            static let keys = "keys"
            /// The `literal` tagged value.
            static let literal = "literal"
            /// The `nsPrefix` tagged value.
            static let nsPrefix = "nsPrefix"
            /// The `nsURI` tagged value.
            static let nsURI = "nsURI"
            /// The `operationName` tagged value.
            static let operationName = "operationName"
            /// The `packageName` tagged value.
            static let packageName = "packageName"
            /// The `parameterName` tagged value.
            static let parameterName = "parameterName"
            /// The `referenceName` tagged value.
            static let referenceName = "referenceName"
            /// The `visibility` tagged value.
            static let visibility = "visibility"
            /// The `xmlContentKind` tagged value.
            static let xmlContentKind = "xmlContentKind"
            /// The `xmlFeatureKind` tagged value.
            static let xmlFeatureKind = "xmlFeatureKind"
            /// The `xmlName` tagged value.
            static let xmlName = "xmlName"
            /// The `xmlNamespace` tagged value.
            static let xmlNamespace = "xmlNamespace"
            /// The `prefix` tagged value.
            static let prefix = "prefix"
            /// The `lowerBound` tagged value.
            static let lowerBound = "lowerBound"
            /// The `upperBound` tagged value.
            static let upperBound = "upperBound"
        }

        /// The extended metadata kinds of the content kinds of the Ecore profile.
        static let contentKinds: [String: String] = [
            "Empty": "empty", "Simple": "simple", "Mixed": "mixed", "ElementOnly": "elementOnly",
        ]

        /// The extended metadata kinds of the feature kinds of the Ecore profile.
        static let featureKinds: [String: String] = [
            "Simple": "simple", "Attribute": "attribute", "AttributeWildcard": "attributeWildcard",
            "AttributeWilcard": "attributeWildcard", "Element": "element", "ElementWildcard": "elementWildcard",
            "Group": "group",
        ]

        /// The visibility kinds of the Ecore profile.
        enum Visibility {
            /// The `None` visibility kind.
            static let none = "None"
            /// The `ReadOnly` visibility kind.
            static let readOnly = "ReadOnly"
            /// The `ReadWrite` visibility kind.
            static let readWrite = "ReadWrite"
            /// The `ReadOnlyUnsettable` visibility kind.
            static let readOnlyUnsettable = "ReadOnlyUnsettable"
        }

        // MARK: - Libraries

        /// The documents of the primitive type libraries and metamodels of Eclipse UML2.
        enum Library {
            /// The library of the UML primitive types.
            static let umlPrimitiveTypes = "pathmap://UML_LIBRARIES/UMLPrimitiveTypes.library.uml"
            /// The library of the Java primitive types.
            static let javaPrimitiveTypes = "pathmap://UML_LIBRARIES/JavaPrimitiveTypes.library.uml"
            /// The library of the Ecore primitive types.
            static let ecorePrimitiveTypes = "pathmap://UML_LIBRARIES/EcorePrimitiveTypes.library.uml"
            /// The library of the XML Schema primitive types.
            static let xmlPrimitiveTypes = "pathmap://UML_LIBRARIES/XMLPrimitiveTypes.library.uml"
            /// The UML metamodel as a UML model.
            static let umlMetamodel = "pathmap://UML_METAMODELS/UML.metamodel.uml"
            /// The Ecore metamodel as a UML model.
            static let ecoreMetamodel = "pathmap://UML_METAMODELS/Ecore.metamodel.uml"
        }

        /// The names of the models of the primitive type libraries, which qualify their types.
        enum LibraryModel {
            /// The model of the `PrimitiveTypes` library.
            static let umlPrimitiveTypes = "PrimitiveTypes"
            /// The model of the `JavaPrimitiveTypes` library.
            static let javaPrimitiveTypes = "JavaPrimitiveTypes"
            /// The model of the `EcorePrimitiveTypes` library.
            static let ecorePrimitiveTypes = "EcorePrimitiveTypes"
            /// The model of the `XMLPrimitiveTypes` library.
            static let xmlPrimitiveTypes = "XMLPrimitiveTypes"
        }

        /// The namespace URI of the EMF XML type package, whose types the XML primitive types stand for.
        static let xmlTypeNamespace = "http://www.eclipse.org/emf/2003/XMLType"

        /// The name of the UML primitive type whose values may be unlimited.
        static let unlimitedNatural = "UnlimitedNatural"

        /// The Ecore data types of the UML primitive types, with the instance classes that
        /// Eclipse UML2 gives them (`boolean`, `int`, `double`, `java.lang.String`, `int`).
        static let umlPrimitiveTypes: [String: EcoreDataType] = [
            "Boolean": .eBoolean, "Integer": .eInt, "Real": .eDouble, "String": .eString, unlimitedNatural: .eInt,
        ]

        /// The Ecore data types of the Java primitive types, as Eclipse UML2 maps them.
        static let javaPrimitiveTypes: [String: EcoreDataType] = [
            "boolean": .eBoolean, "byte": .eByte, "char": .eChar, "double": .eDouble, "float": .eFloat, "int": .eInt,
            "long": .eLong, "short": .eShort,
        ]

        /// The Ecore data types that stand for the XML Schema primitive types.
        ///
        /// Eclipse UML2 refers to the types of the EMF XML type package, which this package does
        /// not provide; the types are therefore mapped onto the Ecore types with the same values.
        static let xmlPrimitiveTypes: [String: EcoreDataType] = [
            "string": .eString, "normalizedString": .eString, "token": .eString, "anyURI": .eString,
            "language": .eString, "Name": .eString, "NCName": .eString, "NMTOKEN": .eString, "ID": .eString,
            "IDREF": .eString, "QName": .eString, "boolean": .eBoolean, "int": .eInt, "integer": .eBigInteger,
            "long": .eLong, "short": .eShort, "byte": .eByte, "decimal": .eBigDecimal, "double": .eDouble,
            "float": .eFloat, "date": .eDate, "dateTime": .eDate, "time": .eDate, "base64Binary": .eByteArray,
            "hexBinary": .eByteArray, "nonNegativeInteger": .eBigInteger, "positiveInteger": .eBigInteger,
            "nonPositiveInteger": .eBigInteger, "negativeInteger": .eBigInteger, "unsignedInt": .eLong,
            "unsignedShort": .eInt, "unsignedByte": .eShort, "unsignedLong": .eBigInteger,
        ]

        /// The Ecore data types whose instance classes are Java primitive types or strings,
        /// which the unsettable primitive attribute option considers.
        static let primitiveInstanceTypes: Set<String> = [
            EcoreDataType.eBoolean.rawValue, EcoreDataType.eByte.rawValue, EcoreDataType.eChar.rawValue,
            EcoreDataType.eDouble.rawValue, EcoreDataType.eFloat.rawValue, EcoreDataType.eInt.rawValue,
            EcoreDataType.eLong.rawValue, EcoreDataType.eShort.rawValue, EcoreDataType.eString.rawValue,
        ]

        /// The instance class names that are Java primitive types or strings.
        static let primitiveInstanceClassNames: Set<String> = [
            "boolean", "byte", "char", "double", "float", "int", "long", "short", "java.lang.String",
        ]
    }

    /// The diagnostic codes of the conversion of UML class models into Ecore metamodels.
    ///
    /// The codes correspond to the diagnostics of the Eclipse UML2 converter: an option set to
    /// ``Choice/process`` reports what it changed as information, an option set to
    /// ``Choice/report`` reports what it found as a warning (as an error for untyped
    /// properties), and an option set to ``Choice/discard`` reports what it removed as a warning.
    public enum Diagnostic {
        /// An Ecore tagged value of the Ecore profile (option ``Options/ecoreTaggedValues``).
        public static let ecoreTaggedValue = "uml2ecore.ecoreTaggedValue"
        /// An operation that redefines another (option ``Options/redefiningOperations``).
        public static let redefiningOperation = "uml2ecore.redefiningOperation"
        /// A property that redefines another (option ``Options/redefiningProperties``).
        public static let redefiningProperty = "uml2ecore.redefiningProperty"
        /// A property that subsets another (option ``Options/subsettingProperties``).
        public static let subsettingProperty = "uml2ecore.subsettingProperty"
        /// A derived union (option ``Options/unionProperties``).
        public static let unionProperty = "uml2ecore.unionProperty"
        /// A derived feature that is stored (option ``Options/derivedFeatures``).
        public static let derivedFeature = "uml2ecore.derivedFeature"
        /// An operation with the signature of an inherited one (option ``Options/duplicateOperations``).
        public static let duplicateOperation = "uml2ecore.duplicateOperation"
        /// A feature with the name of an inherited one (option ``Options/duplicateFeatures``).
        public static let duplicateFeature = "uml2ecore.duplicateFeature"
        /// Super classes whose order changed (option ``Options/superClassOrder``).
        public static let superClassOrder = "uml2ecore.superClassOrder"
        /// Annotation details of a UML element (option ``Options/annotationDetails``).
        public static let annotationDetails = "uml2ecore.annotationDetails"
        /// An invariant constraint (option ``Options/invariantConstraints``).
        public static let invariantConstraint = "uml2ecore.invariantConstraint"
        /// The body of an operation (option ``Options/operationBodies``).
        public static let operationBody = "uml2ecore.operationBody"
        /// A comment (option ``Options/comments``).
        public static let comment = "uml2ecore.comment"
        /// A name that is not in camel case (option ``Options/camelCaseNames``).
        public static let camelCaseName = "uml2ecore.camelCaseName"
        /// A property without a type (option ``Options/untypedProperties``).
        public static let untypedProperty = "uml2ecore.untypedProperty"
        /// The name of the opposite end of a unidirectional reference (option ``Options/oppositeRoleNames``).
        public static let oppositeRoleName = "uml2ecore.oppositeRoleName"
        /// A default value expression of a property (option ``Options/propertyDefaultExpressions``).
        public static let propertyDefaultExpression = "uml2ecore.propertyDefaultExpression"
        /// An optional primitive attribute (option ``Options/unsettablePrimitiveAttributes``).
        public static let optionalAttribute = "uml2ecore.optionalAttribute"
        /// An optional enumeration attribute (option ``Options/nullableEnumAttributes``).
        public static let optionalEnumAttribute = "uml2ecore.optionalEnumAttribute"
        /// A navigable end owned by an association (option ``Options/navigableAssociationOwnedEnds``).
        public static let associationOwnedEnd = "uml2ecore.associationOwnedEnd"
        /// An option set to a choice that this converter does not implement.
        public static let unsupportedOption = "uml2ecore.unsupportedOption"
        /// A type that cannot be resolved, or a construct that has no equivalent in Ecore.
        public static let unsupported = "uml2ecore.unsupported"
    }
}
