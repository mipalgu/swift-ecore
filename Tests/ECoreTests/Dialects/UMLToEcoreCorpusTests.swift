import EMFBase
import Foundation
import Testing

@testable import ECore

/// Converts every UML class model of a reference directory into an Ecore metamodel, if one is given.
///
/// The test runs only if the environment variable `UML_REFERENCE_DIR` names a directory (see
/// ``UMLReferenceCorpusTests``). Every `.uml` file beneath it that holds a classifier is read
/// and converted with the standard options; the counts of the converted elements and the
/// diagnostics by code are printed. Documents whose classifiers are not in a package are
/// counted but cannot be converted, as in Eclipse UML2. The files are only read, never
/// changed or copied.
@Suite("UML to Ecore reference corpus")
struct UMLToEcoreCorpusTests {
    /// The metaclasses whose instances make a document a class model.
    static let classifierKinds: Set<String> = ["Class", "Interface", "DataType", "Enumeration", "PrimitiveType"]

    /// Counts the classifiers, features and operations of packages and their subpackages.
    static func counts(of packages: [EPackage]) -> (classifiers: Int, features: Int, operations: Int) {
        var result = (classifiers: 0, features: 0, operations: 0)
        for package in packages.flatMap(\.allPackages) {
            result.classifiers += package.eClassifiers.count
            for case let eClass as EClass in package.eClassifiers {
                result.features += eClass.eStructuralFeatures.count
                result.operations += eClass.eOperations.count
            }
        }
        return result
    }

    /// Whether a resource holds a classifier.
    static func isClassModel(_ resource: Resource) async -> Bool {
        for object in await resource.getAllObjects() {
            guard let eClass = object.eClass as? EClass else { continue }
            if Self.classifierKinds.contains(eClass.name) { return true }
        }
        return false
    }

    @Test("Every reference class model converts", .enabled(if: UMLReferenceCorpusTests.directory != nil))
    func convertsReferenceModels() async throws {
        let directory = try #require(UMLReferenceCorpusTests.directory)
        let models = UMLReferenceCorpusTests.models(in: directory)
        #expect(!models.isEmpty)
        var failures: [String] = []
        var codes: [String: Int] = [:]
        var severities: [DiagnosticSeverity: Int] = [:]
        var converted = 0
        var skipped = 0
        var withoutPackage = 0
        var totals = (packages: 0, classifiers: 0, features: 0, operations: 0)
        for url in models {
            let base = directory.resolvingSymlinksInPath().path + "/"
            let name = url.resolvingSymlinksInPath().path.replacingOccurrences(of: base, with: "")
            do {
                let resourceSet = ResourceSet()
                await UMLToEcore.registerEcoreProfile(in: resourceSet)
                let read = try await UMLFormat.read(url: url, resourceSet: resourceSet)
                guard await Self.isClassModel(read.resource) else {
                    skipped += 1
                    continue
                }
                let result: ModelDocumentReadResult
                do {
                    result = try await UMLToEcore.convert(read.resource)
                } catch UMLToEcoreError.noPackage {
                    withoutPackage += 1
                    continue
                }
                converted += 1
                let counts = Self.counts(of: result.packages)
                totals.packages += result.packages.flatMap(\.allPackages).count
                totals.classifiers += counts.classifiers
                totals.features += counts.features
                totals.operations += counts.operations
                for diagnostic in result.diagnostics {
                    codes[diagnostic.code, default: 0] += 1
                    severities[diagnostic.severity, default: 0] += 1
                }
                print("UML to Ecore corpus: \(name): \(result.packages.count) root packages, "
                    + "\(counts.classifiers) classifiers, \(counts.features) features, \(counts.operations) operations, "
                    + "\(result.diagnostics.filter { $0.severity != .information }.count) warnings or errors")
                for diagnostic in result.diagnostics where diagnostic.severity != .information {
                    print("UML to Ecore corpus \(diagnostic.severity): \(name): \(diagnostic.message)")
                }
            } catch {
                failures.append("\(name): \(error)")
            }
        }
        print("UML to Ecore corpus: \(models.count) documents, \(converted) converted, \(skipped) without classifiers, "
            + "\(withoutPackage) without a package, \(failures.count) failures; \(totals.packages) packages, \(totals.classifiers) classifiers, "
            + "\(totals.features) features, \(totals.operations) operations")
        print("UML to Ecore corpus diagnostics by severity: "
            + "\(severities.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" })")
        print("UML to Ecore corpus diagnostics by code: \(codes.sorted { $0.key < $1.key })")
        for failure in failures { print("UML to Ecore corpus failure: \(failure)") }
        #expect(failures.isEmpty)
    }

    /// The environment variable that names the UML metamodel of Eclipse UML2 as a UML model
    /// (`UML.metamodel.uml`), against whose conversion the bundled `UML.ecore` is compared.
    ///
    /// The model is converted with the options of the Eclipse UML2 dialog, keeping names and
    /// referring to the UML primitive types, which comes closest to how `UML.ecore` was made.
    static let metamodelVariable = "UML_METAMODEL_DOCUMENT"

    /// The UML metamodel as a UML model, if one is given.
    static var metamodelDocument: URL? {
        guard let path = ProcessInfo.processInfo.environment[metamodelVariable], !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// The names of the features of each class of a package.
    static func featureNames(of package: EPackage) -> [String: Set<String>] {
        var result: [String: Set<String>] = [:]
        for case let eClass as EClass in package.eClassifiers {
            result[eClass.name] = Set(eClass.eStructuralFeatures.map(\.name))
        }
        return result
    }

    /// The properties of a feature that the comparison with `UML.ecore` considers.
    static func properties(of feature: any EStructuralFeature) -> [String: String] {
        if let attribute = feature as? EAttribute {
            return [
                "kind": "attribute", "lowerBound": "\(attribute.lowerBound)", "upperBound": "\(attribute.upperBound)",
                "ordered": "\(attribute.ordered)", "unique": "\(attribute.unique)", "changeable": "\(attribute.changeable)",
                "derived": "\(attribute.derived)", "transient": "\(attribute.transient)", "volatile": "\(attribute.volatile)",
                "unsettable": "\(attribute.unsettable)", "eType": attribute.eType.name,
            ]
        }
        guard let reference = feature as? EReference else { return [:] }
        return [
            "kind": "reference", "lowerBound": "\(reference.lowerBound)", "upperBound": "\(reference.upperBound)",
            "ordered": "\(reference.ordered)", "unique": "\(reference.unique)", "changeable": "\(reference.changeable)",
            "derived": "\(reference.derived)", "transient": "\(reference.transient)", "volatile": "\(reference.volatile)",
            "unsettable": "\(reference.unsettable)", "eType": reference.eType.name,
            "containment": "\(reference.containment)", "resolveProxies": "\(reference.resolveProxies)",
            "eOpposite": reference.opposite == nil ? "none" : "set",
        ]
    }

    /// Compares the super types, operations and feature properties of the classes of two packages.
    static func propertyDifferences(_ converted: EPackage, _ expected: EPackage)
        -> (counts: [String: Int], examples: [String])
    {
        var counts: [String: Int] = [:]
        var examples: [String] = []
        func note(_ property: String, _ text: String) {
            counts[property, default: 0] += 1
            if counts[property] ?? 0 <= 3 { examples.append("\(property): \(text)") }
        }
        for case let target as EClass in expected.eClassifiers {
            guard let actual = converted.getEClass(target.name) else { continue }
            if actual.eSuperTypes.map(\.name) != target.eSuperTypes.map(\.name) {
                note("eSuperTypes", "\(target.name) \(actual.eSuperTypes.map(\.name)) vs \(target.eSuperTypes.map(\.name))")
            }
            if Set(actual.eOperations.map(\.name)) != Set(target.eOperations.map(\.name)) {
                let missing = Set(target.eOperations.map(\.name)).subtracting(actual.eOperations.map(\.name)).sorted()
                let extra = Set(actual.eOperations.map(\.name)).subtracting(target.eOperations.map(\.name)).sorted()
                note("eOperations", "\(target.name) missing \(missing) extra \(extra)")
            }
            if actual.isAbstract != target.isAbstract { note("abstract", target.name) }
            for feature in target.eStructuralFeatures {
                guard let other = actual.getStructuralFeature(name: feature.name) else { continue }
                let left = properties(of: other)
                let right = properties(of: feature)
                for key in right.keys.sorted() where left[key] != right[key] {
                    note(key, "\(target.name).\(feature.name) \(left[key] ?? "-") vs \(right[key] ?? "-")")
                }
            }
        }
        return (counts, examples)
    }

    @Test("The UML metamodel converts into the classifiers and features of UML.ecore",
          .enabled(if: metamodelDocument != nil))
    func convertsUMLMetamodel() async throws {
        let url = try #require(Self.metamodelDocument)
        let resourceSet = ResourceSet()
        await UMLToEcore.registerEcoreProfile(in: resourceSet)
        let read = try await UMLFormat.read(url: url, resourceSet: resourceSet)
        var options = UMLToEcore.Options.eclipseDialog
        options.camelCaseNames = .ignore
        options.primitiveTypes = .umlTypes
        let result = try await UMLToEcore.convert(read.resource, options: options, resourceSet: resourceSet)
        let converted = try #require(result.packages.first { $0.name == "uml" })
        let (expected, _) = try await UMLMetamodel.packages()
        let convertedNames = Set(converted.eClassifiers.map(\.name))
        let expectedNames = Set(expected.eClassifiers.map(\.name))
        let convertedFeatures = Self.featureNames(of: converted)
        let expectedFeatures = Self.featureNames(of: expected)
        var featureDifferences: [String] = []
        for (name, features) in expectedFeatures.sorted(by: { $0.key < $1.key }) {
            let actual = convertedFeatures[name] ?? []
            if actual != features {
                featureDifferences.append("\(name): missing \(features.subtracting(actual).sorted()), "
                    + "extra \(actual.subtracting(features).sorted())")
            }
        }
        print("UML metamodel: \(converted.eClassifiers.count) classifiers converted, \(expected.eClassifiers.count) in UML.ecore; "
            + "missing \(expectedNames.subtracting(convertedNames).sorted()), extra \(convertedNames.subtracting(expectedNames).sorted()); "
            + "\(featureDifferences.count) classes with other features; nsURI \(converted.nsURI)")
        for difference in featureDifferences.prefix(40) { print("UML metamodel features: \(difference)") }
        var codes: [String: Int] = [:]
        for diagnostic in result.diagnostics { codes[diagnostic.code, default: 0] += 1 }
        print("UML metamodel diagnostics by code: \(codes.sorted { $0.key < $1.key })")
        for diagnostic in result.diagnostics where diagnostic.severity != .information {
            print("UML metamodel warning: \(diagnostic.message)")
        }
        let differences = Self.propertyDifferences(converted, expected)
        print("UML metamodel property differences: \(differences.counts.sorted { $0.key < $1.key })")
        for example in differences.examples.prefix(40) { print("UML metamodel difference: \(example)") }
        #expect(convertedNames == expectedNames)
        #expect(featureDifferences.isEmpty)
        #expect(differences.counts.isEmpty)
        #expect(converted.nsURI == expected.nsURI)
    }
}
