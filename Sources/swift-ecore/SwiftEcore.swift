//
// SwiftEcore.swift
// ECore
//
//  Created by Rene Hexel on 3/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import ArgumentParser
import ECore
import Foundation

/// The main command-line interface for Swift Ecore.
///
/// Swift Ecore provides Eclipse Modeling Framework (EMF) functionality for Swift,
/// including model validation, format conversion, code generation, and querying capabilities.
@main
struct SwiftEcoreCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swift-ecore",
        abstract: "Swift Ecore - Eclipse Modeling Framework for Swift",
        version: "0.1.0",
        subcommands: [
            InfoCommand.self,
            ValidateCommand.self,
            ConvertCommand.self,
            GenerateCommand.self,
            QueryCommand.self,
        ]
    )
}

// MARK: - Default Info Command

/// The default command that displays information about Swift Ecore.
struct InfoCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "info",
        abstract: "Show Swift Ecore information"
    )

    /// Executes the info command.
    ///
    /// Displays version information and available commands for Swift Ecore.
    func run() async throws {
        print(
            """
            Swift Ecore v0.1.0
            Eclipse Modeling Framework for Swift

            Available commands:
              validate    Validate models and metamodels
              convert     Convert between formats (XMI <-> JSON)
              generate    Generate code from models
              query       Query models and metamodels

            Use 'swift-ecore <command> --help' for detailed help on each command.
            """)
    }
}

// MARK: - Validate Command

/// Command for validating models and metamodels for correctness.
///
/// The validate command checks the structural integrity and compliance of model files,
/// supporting XMI, JSON, and Ecore formats.
struct ValidateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "validate",
        abstract: "Validate models and metamodels for correctness"
    )

    /// Path to the model file to validate.
    @Argument(help: "Path to the model file to validate")
    var inputPath: String

    /// Optional metamodel file for validation.
    @Option(name: .shortAndLong, help: "Metamodel file for validation (optional)")
    var metamodel: String?

    /// Enable verbose output.
    @Flag(name: .shortAndLong, help: "Enable verbose output")
    var verbose: Bool = false

    /// Executes the validate command.
    ///
    /// Validates the specified model file and reports any errors or warnings found.
    ///
    /// - Throws: `ValidationError` if validation fails.
    func run() async throws {
        if verbose {
            print("Validating: \(inputPath)")
            if let metamodel = metamodel {
                print("Using metamodel: \(metamodel)")
            }
        }

        let inputURL = URL(fileURLWithPath: inputPath)

        guard FileManager.default.fileExists(atPath: inputPath) else {
            throw ValidationError.fileNotFound(inputPath)
        }

        // Determine file type
        let fileExtension = inputURL.pathExtension.lowercased()

        switch fileExtension {
        case "xmi":
            try await validateXMI(at: inputURL)
        case "json":
            try await validateJSON(at: inputURL)
        case "ecore":
            try await validateEcore(at: inputURL)
        default:
            throw ValidationError.unsupportedFormat(fileExtension)
        }

        print("Validation completed successfully")
    }

    /// Validates an XMI file.
    ///
    /// - Parameter url: The URL of the XMI file to validate.
    /// - Throws: `ValidationError.parsingFailed` if parsing fails.
    private func validateXMI(at url: URL) async throws {
        if verbose { print("Validating XMI file...") }

        _ = Resource(uri: url.absoluteString)
        let parser = XMIParser()

        do {
            let parsedResource = try await parser.parse(url)
            let objects = await parsedResource.getRootObjects()

            if verbose {
                print("Found \(objects.count) root object(s)")
                for (index, obj) in objects.enumerated() {
                    if let eObj = obj as? DynamicEObject {
                        print("   \(index + 1). \(eObj.eClass.name) (id: \(eObj.id))")
                    }
                }
            }
        } catch {
            throw ValidationError.parsingFailed("XMI", error.localizedDescription)
        }
    }

    /// Validates a JSON file.
    ///
    /// - Parameter url: The URL of the JSON file to validate.
    /// - Throws: `ValidationError.parsingFailed` if parsing fails.
    private func validateJSON(at url: URL) async throws {
        if verbose { print("Validating JSON file...") }

        _ = Resource(uri: url.absoluteString)
        let parser = JSONParser()

        do {
            let parsedResource = try await parser.parse(url)
            let objects = await parsedResource.getRootObjects()

            if verbose {
                print("Found \(objects.count) root object(s)")
                for (index, obj) in objects.enumerated() {
                    if let eObj = obj as? DynamicEObject {
                        print("   \(index + 1). \(eObj.eClass.name) (id: \(eObj.id))")
                    }
                }
            }
        } catch {
            throw ValidationError.parsingFailed("JSON", error.localizedDescription)
        }
    }

    /// Validates an Ecore metamodel file.
    ///
    /// - Parameter url: The URL of the Ecore file to validate.
    /// - Throws: `ValidationError.parsingFailed` if parsing fails.
    private func validateEcore(at url: URL) async throws {
        if verbose { print("Validating Ecore metamodel...") }

        _ = Resource(uri: url.absoluteString)
        let parser = XMIParser()

        do {
            let parsedResource = try await parser.parse(url)
            let packages = await parsedResource.getRootObjects().compactMap { $0 as? EPackage }

            if verbose {
                print("Found \(packages.count) package(s)")
                for package in packages {
                    print(
                        "   \(package.name) - \(package.eClassifiers.count) classifier(s)"
                    )
                }
            }
        } catch {
            throw ValidationError.parsingFailed("Ecore", error.localizedDescription)
        }
    }
}

// MARK: - Convert Command

/// Command for converting between model formats.
///
/// The convert command supports bidirectional conversion between XMI and JSON formats,
/// preserving model structure and data integrity.
struct ConvertCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "convert",
        abstract: "Convert between model formats (XMI <-> JSON)"
    )

    /// Input file path.
    @Argument(help: "Input file path")
    var inputPath: String

    /// Output file path.
    @Argument(help: "Output file path")
    var outputPath: String

    /// Enable verbose output.
    @Flag(name: .shortAndLong, help: "Enable verbose output")
    var verbose: Bool = false

    /// Overwrite output file if it exists.
    @Flag(help: "Overwrite output file if it exists")
    var force: Bool = false

    /// Executes the convert command.
    ///
    /// Converts the input file to the output format based on file extensions.
    ///
    /// - Throws: `ConversionError` if conversion fails.
    func run() async throws {
        if verbose {
            print("Converting: \(inputPath) -> \(outputPath)")
        }

        let inputURL = URL(fileURLWithPath: inputPath)
        let outputURL = URL(fileURLWithPath: outputPath)

        guard FileManager.default.fileExists(atPath: inputPath) else {
            throw ConversionError.fileNotFound(inputPath)
        }

        if FileManager.default.fileExists(atPath: outputPath) && !force {
            throw ConversionError.outputExists(outputPath)
        }

        let inputExtension = inputURL.pathExtension.lowercased()
        let outputExtension = outputURL.pathExtension.lowercased()

        // Load input
        let resource: Resource

        switch inputExtension {
        case "xmi":
            if verbose { print("Reading XMI...") }
            let parser = XMIParser()
            resource = try await parser.parse(inputURL)
        case "json":
            if verbose { print("Reading JSON...") }
            let parser = JSONParser()
            resource = try await parser.parse(inputURL)
        default:
            throw ConversionError.unsupportedInputFormat(inputExtension)
        }

        // Save output
        switch outputExtension {
        case "xmi":
            if verbose { print("Writing XMI...") }
            let serializer = XMISerializer()
            let content = try await serializer.serialize(resource)
            try content.write(to: outputURL, atomically: true, encoding: .utf8)
        case "json":
            if verbose { print("Writing JSON...") }
            let serializer = JSONSerializer()
            let content = try await serializer.serialize(resource)
            try content.write(to: outputURL, atomically: true, encoding: .utf8)
        default:
            throw ConversionError.unsupportedOutputFormat(outputExtension)
        }

        if verbose {
            let objects = await resource.getRootObjects()
            print("Converted \(objects.count) object(s) successfully")
        }

        print("Conversion completed: \(outputPath)")
    }
}

// MARK: - Generate Command

/// Command for generating code from models.
///
/// The generate command creates source code in various target languages
/// from Ecore metamodels or model instances.
struct GenerateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "generate",
        abstract: "Generate code from models"
    )

    /// Input model file path.
    @Argument(help: "Input model file path")
    var inputPath: String

    /// Output directory for generated code.
    @Option(name: .shortAndLong, help: "Output directory for generated code")
    var output: String = "."

    /// Target language for code generation.
    @Option(name: .shortAndLong, help: "Target language (swift, cpp, c, llvm)")
    var language: String = "swift"

    /// Enable verbose output.
    @Flag(name: .shortAndLong, help: "Enable verbose output")
    var verbose: Bool = false

    /// Executes the generate command.
    ///
    /// Generates code in the specified target language from the input model.
    ///
    /// - Throws: `GenerationError` if generation fails.
    func run() async throws {
        if verbose {
            print("Generating \(language) code from: \(inputPath)")
            print("Output directory: \(output)")
        }

        let inputURL = URL(fileURLWithPath: inputPath)
        let outputURL = URL(fileURLWithPath: output)

        guard FileManager.default.fileExists(atPath: inputPath) else {
            throw GenerationError.fileNotFound(inputPath)
        }

        // Create output directory if it doesn't exist
        try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

        // Load model
        let resource: Resource
        let fileExtension = inputURL.pathExtension.lowercased()

        switch fileExtension {
        case "ecore":
            if verbose { print("Loading Ecore metamodel...") }
            let parser = XMIParser()
            resource = try await parser.parse(inputURL)
        case "xmi":
            if verbose { print("Loading XMI model...") }
            let parser = XMIParser()
            resource = try await parser.parse(inputURL)
        case "json":
            if verbose { print("Loading JSON model...") }
            let parser = JSONParser()
            resource = try await parser.parse(inputURL)
        default:
            throw GenerationError.unsupportedFormat(fileExtension)
        }

        // Generate code
        let generator = try CodeGenerator(language: language, outputDirectory: outputURL)
        try await generator.generate(from: resource, verbose: verbose)

        print("Code generation completed in: \(output)")
    }
}

// MARK: - Query Command

/// Command for querying models and metamodels.
///
/// The query command provides inspection capabilities for models,
/// allowing users to examine structure, find objects, and analyse content.
struct QueryCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "query",
        abstract: "Query models and metamodels"
    )

    /// Model file path to query.
    @Argument(help: "Model file path to query")
    var inputPath: String

    /// Query expression to execute.
    @Option(
        name: .shortAndLong,
        help: "Query expression (e.g., 'count(*)', 'find(Person)', 'list-classes')")
    var query: String = "info"

    /// Enable verbose output.
    @Flag(name: .shortAndLong, help: "Enable verbose output")
    var verbose: Bool = false

    /// Executes the query command.
    ///
    /// Runs the specified query against the input model and displays results.
    ///
    /// - Throws: `QueryError` if the query fails.
    func run() async throws {
        if verbose {
            print("Querying: \(inputPath)")
            print("Query: \(query)")
        }

        let inputURL = URL(fileURLWithPath: inputPath)

        guard FileManager.default.fileExists(atPath: inputPath) else {
            throw QueryError.fileNotFound(inputPath)
        }

        // Load model
        let resource: Resource
        let fileExtension = inputURL.pathExtension.lowercased()

        switch fileExtension {
        case "xmi":
            let parser = XMIParser()
            resource = try await parser.parse(inputURL)
        case "json":
            let parser = JSONParser()
            resource = try await parser.parse(inputURL)
        case "ecore":
            let parser = XMIParser()
            resource = try await parser.parse(inputURL)
        default:
            throw QueryError.unsupportedFormat(fileExtension)
        }

        // Execute query
        let queryEngine = QueryEngine(resource: resource)
        let result = try await queryEngine.execute(query)

        print(result)
    }
}

// MARK: - Code Generator

/// Actor responsible for generating code from models in various target languages.
///
/// The code generator supports multiple target languages including Swift, C++, C, and LLVM IR.
/// It processes model objects and generates appropriate source code structures.
actor CodeGenerator {
    /// The target language for code generation.
    let language: String

    /// The output directory where generated files will be written.
    let outputDirectory: URL

    /// Initialises a new code generator.
    ///
    /// - Parameters:
    ///   - language: The target language (must be one of: swift, cpp, c, llvm).
    ///   - outputDirectory: The directory where generated files will be written.
    /// - Throws: `GenerationError.unsupportedLanguage` if the language is not supported.
    init(language: String, outputDirectory: URL) throws {
        guard ["swift", "cpp", "c", "llvm"].contains(language) else {
            throw GenerationError.unsupportedLanguage(language)
        }
        self.language = language
        self.outputDirectory = outputDirectory
    }

    /// Generates code from the provided resource.
    ///
    /// - Parameters:
    ///   - resource: The resource containing model objects to generate from.
    ///   - verbose: Whether to output verbose progress information.
    /// - Throws: `GenerationError` if generation fails.
    func generate(from resource: Resource, verbose: Bool) async throws {
        let objects = await resource.getRootObjects()

        if objects.isEmpty {
            if verbose { print("No objects found in model") }
            return
        }

        switch language {
        case "swift":
            try await generateSwift(from: objects, verbose: verbose)
        case "cpp":
            try await generateCpp(from: objects, verbose: verbose)
        case "c":
            try await generateC(from: objects, verbose: verbose)
        case "llvm":
            try await generateLLVM(from: objects, verbose: verbose)
        default:
            throw GenerationError.unsupportedLanguage(language)
        }
    }

    /// Generates Swift code from the provided objects.
    ///
    /// - Parameters:
    ///   - objects: The model objects to generate code from.
    ///   - verbose: Whether to output verbose progress information.
    /// - Throws: File I/O errors if writing fails.
    private func generateSwift(from objects: [any EObject], verbose: Bool) async throws {
        if verbose { print("Generating Swift code...") }

        let outputFile = outputDirectory.appendingPathComponent("Generated.swift")
        var content = """
            //
            // Generated.swift
            // Generated by Swift Ecore
            //
            import Foundation

            """

        for obj in objects {
            if let eClass = obj as? EClass {
                content += generateSwiftClass(from: eClass)
            } else if let ePackage = obj as? EPackage {
                content += generateSwiftPackage(from: ePackage)
            }
        }

        try content.write(to: outputFile, atomically: true, encoding: .utf8)
        if verbose { print("Generated: \(outputFile.path)") }
    }

    /// Generates C++ code from the provided objects.
    ///
    /// - Parameters:
    ///   - objects: The model objects to generate code from.
    ///   - verbose: Whether to output verbose progress information.
    /// - Throws: File I/O errors if writing fails.
    private func generateCpp(from objects: [any EObject], verbose: Bool) async throws {
        if verbose { print("Generating C++ code...") }

        // Header file
        let headerFile = outputDirectory.appendingPathComponent("Generated.hpp")
        var headerContent = """
            //
            // Generated.hpp
            // Generated by Swift Ecore
            //
            #pragma once
            #include <memory>
            #include <string>
            #include <vector>

            """

        // Implementation file
        let implFile = outputDirectory.appendingPathComponent("Generated.cpp")
        var implContent = """
            //
            // Generated.cpp
            // Generated by Swift Ecore
            //
            #include "Generated.hpp"

            """

        for obj in objects {
            if let eClass = obj as? EClass {
                headerContent += generateCppClassHeader(from: eClass)
                implContent += generateCppClassImpl(from: eClass)
            }
        }

        try headerContent.write(to: headerFile, atomically: true, encoding: .utf8)
        try implContent.write(to: implFile, atomically: true, encoding: .utf8)

        if verbose {
            print("Generated: \(headerFile.path)")
            print("Generated: \(implFile.path)")
        }
    }

    /// Generates C code from the provided objects.
    ///
    /// - Parameters:
    ///   - objects: The model objects to generate code from.
    ///   - verbose: Whether to output verbose progress information.
    /// - Throws: File I/O errors if writing fails.
    private func generateC(from objects: [any EObject], verbose: Bool) async throws {
        if verbose { print("Generating C code...") }

        let headerFile = outputDirectory.appendingPathComponent("generated.h")
        let implFile = outputDirectory.appendingPathComponent("generated.c")

        var headerContent = """
            /*
             * generated.h
             * Generated by Swift Ecore
             */
            #ifndef GENERATED_H
            #define GENERATED_H

            """

        let implContent = """
            /*
             * generated.c
             * Generated by Swift Ecore
             */
            #include "generated.h"

            """

        headerContent += "\n#endif /* GENERATED_H */"

        try headerContent.write(to: headerFile, atomically: true, encoding: .utf8)
        try implContent.write(to: implFile, atomically: true, encoding: .utf8)

        if verbose {
            print("Generated: \(headerFile.path)")
            print("Generated: \(implFile.path)")
        }
    }

    /// Generates LLVM IR from the provided objects.
    ///
    /// - Parameters:
    ///   - objects: The model objects to generate code from.
    ///   - verbose: Whether to output verbose progress information.
    /// - Throws: File I/O errors if writing fails.
    private func generateLLVM(from objects: [any EObject], verbose: Bool) async throws {
        if verbose { print("Generating LLVM IR...") }

        let outputFile = outputDirectory.appendingPathComponent("generated.ll")
        let content = """
            ; generated.ll
            ; Generated by Swift Ecore

            """

        try content.write(to: outputFile, atomically: true, encoding: .utf8)
        if verbose { print("Generated: \(outputFile.path)") }
    }

    // MARK: - Swift Generation Helpers

    /// Generates a Swift struct from an EClass.
    ///
    /// - Parameter eClass: The EClass to generate from.
    /// - Returns: Swift code as a string.
    private func generateSwiftClass(from eClass: EClass) -> String {
        var result = """

            struct \(eClass.name) {
            """

        for feature in eClass.eStructuralFeatures {
            if let attribute = feature as? EAttribute {
                let typeName = swiftTypeName(for: attribute.eType as? EDataType)
                result += "\n    var \(attribute.name): \(typeName)?"
            } else if let reference = feature as? EReference {
                let typeName = reference.eType.name
                if reference.upperBound == -1 {
                    result += "\n    var \(reference.name): [\(typeName)] = []"
                } else {
                    result += "\n    var \(reference.name): \(typeName)?"
                }
            }
        }

        result += "\n}\n"
        return result
    }

    /// Generates Swift code from an EPackage.
    ///
    /// - Parameter ePackage: The EPackage to generate from.
    /// - Returns: Swift code as a string.
    private func generateSwiftPackage(from ePackage: EPackage) -> String {
        var result = """

            // Package: \(ePackage.name)
            """

        for classifier in ePackage.eClassifiers {
            if let eClass = classifier as? EClass {
                result += generateSwiftClass(from: eClass)
            }
        }

        return result
    }

    /// Maps an EDataType to a Swift type name.
    ///
    /// - Parameter dataType: The EDataType to map.
    /// - Returns: The corresponding Swift type name.
    private func swiftTypeName(for dataType: EDataType?) -> String {
        guard let dataType = dataType else { return "Any" }

        switch dataType.instanceClassName {
        case "String": return "String"
        case "Int": return "Int"
        case "Bool": return "Bool"
        case "Double": return "Double"
        case "Float": return "Float"
        default: return dataType.name
        }
    }

    // MARK: - C++ Generation Helpers

    /// Generates a C++ class header from an EClass.
    ///
    /// - Parameter eClass: The EClass to generate from.
    /// - Returns: C++ header code as a string.
    private func generateCppClassHeader(from eClass: EClass) -> String {
        var result = """

            class \(eClass.name) {
            public:
            """

        for feature in eClass.eStructuralFeatures {
            if let attribute = feature as? EAttribute {
                let typeName = cppTypeName(for: attribute.eType as? EDataType)
                result +=
                    "\n    \(typeName) get\(attribute.name.capitalized)() const;"
                result +=
                    "\n    void set\(attribute.name.capitalized)(const \(typeName)& value);"
            }
        }

        result += """

            private:
            """

        for feature in eClass.eStructuralFeatures {
            if let attribute = feature as? EAttribute {
                let typeName = cppTypeName(for: attribute.eType as? EDataType)
                result += "\n    \(typeName) \(attribute.name)_;"
            }
        }

        result += "\n};\n"
        return result
    }

    /// Generates C++ class implementation from an EClass.
    ///
    /// - Parameter eClass: The EClass to generate from.
    /// - Returns: C++ implementation code as a string.
    private func generateCppClassImpl(from eClass: EClass) -> String {
        var result = ""

        for feature in eClass.eStructuralFeatures {
            if let attribute = feature as? EAttribute {
                let className = eClass.name
                let attrName = attribute.name
                let typeName = cppTypeName(for: attribute.eType as? EDataType)

                result += """

                    \(typeName) \(className)::get\(attrName.capitalized)() const {
                        return \(attrName)_;
                    }

                    void \(className)::set\(attrName.capitalized)(const \(typeName)& value) {
                        \(attrName)_ = value;
                    }
                    """
            }
        }

        return result
    }

    /// Maps an EDataType to a C++ type name.
    ///
    /// - Parameter dataType: The EDataType to map.
    /// - Returns: The corresponding C++ type name.
    private func cppTypeName(for dataType: EDataType?) -> String {
        guard let dataType = dataType else { return "void*" }

        switch dataType.instanceClassName {
        case "String": return "std::string"
        case "Int": return "int"
        case "Bool": return "bool"
        case "Double": return "double"
        case "Float": return "float"
        default: return dataType.name
        }
    }
}

// MARK: - Query Engine

/// Actor responsible for executing queries against model resources.
///
/// The query engine provides various inspection and analysis capabilities
/// for examining model content and structure.
actor QueryEngine {
    /// The resource to query against.
    let resource: Resource

    /// Initialises a new query engine.
    ///
    /// - Parameter resource: The resource to query against.
    init(resource: Resource) {
        self.resource = resource
    }

    /// Executes a query against the resource.
    ///
    /// - Parameter query: The query string to execute.
    /// - Returns: The query result as a formatted string.
    /// - Throws: `QueryError` if the query is invalid or fails.
    func execute(_ query: String) async throws -> String {
        let parts = query.lowercased().components(separatedBy: CharacterSet.whitespacesAndNewlines)
        guard let command = parts.first else {
            throw QueryError.invalidQuery("Empty query")
        }

        let objects = await resource.getRootObjects()

        switch command {
        case "info":
            return generateInfo(for: objects)
        case "count":
            return "Total objects: \(objects.count)"
        case "list-classes":
            return generateClassList(for: objects)
        case "find":
            guard parts.count > 1 else {
                throw QueryError.invalidQuery("find requires a class name")
            }
            return findObjects(matching: parts[1], in: objects)
        case "tree":
            return generateTree(for: objects)
        default:
            throw QueryError.unsupportedQuery(command)
        }
    }

    /// Generates general information about the model objects.
    ///
    /// - Parameter objects: The objects to analyse.
    /// - Returns: Formatted information string.
    private func generateInfo(for objects: [any EObject]) -> String {
        var result = "Model Information\n"
        result += "=================\n"
        result += "Total objects: \(objects.count)\n\n"

        var classCount: [String: Int] = [:]
        for obj in objects {
            if let dynamicObj = obj as? DynamicEObject {
                let className = dynamicObj.eClass.name
                classCount[className, default: 0] += 1
            } else {
                let className = String(describing: type(of: obj))
                classCount[className, default: 0] += 1
            }
        }

        if !classCount.isEmpty {
            result += "Classes:\n"
            for (className, count) in classCount.sorted(by: { $0.key < $1.key }) {
                result += "  * \(className): \(count)\n"
            }
        }

        return result
    }

    /// Generates a list of available classes in the model.
    ///
    /// - Parameter objects: The objects to analyse.
    /// - Returns: Formatted class list string.
    private func generateClassList(for objects: [any EObject]) -> String {
        var result = "Available Classes\n"
        result += "=================\n"

        let classNames = Set(
            objects.compactMap { obj -> String? in
                if let dynamicObj = obj as? DynamicEObject {
                    return dynamicObj.eClass.name
                } else {
                    return String(describing: type(of: obj))
                }
            })

        for className in classNames.sorted() {
            result += "* \(className)\n"
        }

        return result
    }

    /// Finds objects matching a specific class name.
    ///
    /// - Parameters:
    ///   - className: The class name to match.
    ///   - objects: The objects to search within.
    /// - Returns: Formatted results string.
    private func findObjects(matching className: String, in objects: [any EObject]) -> String {
        let matches = objects.filter { obj in
            if let dynamicObj = obj as? DynamicEObject {
                return dynamicObj.eClass.name.lowercased() == className.lowercased()
            } else {
                return String(describing: type(of: obj)).lowercased().contains(
                    className.lowercased())
            }
        }

        var result = "Objects matching '\(className)'\n"
        result += String(repeating: "=", count: "Objects matching '\(className)'".count) + "\n"
        result += "Found \(matches.count) match(es)\n\n"

        for (index, obj) in matches.enumerated() {
            if let dynamicObj = obj as? DynamicEObject {
                result += "\(index + 1). \(dynamicObj.eClass.name) (id: \(dynamicObj.id))\n"

                // Show some features
                let featureNames = dynamicObj.getFeatureNames()
                for featureName in featureNames.prefix(3) {
                    if let value = dynamicObj.eGet(featureName) {
                        result += "   \(featureName): \(value)\n"
                    }
                }
                if featureNames.count > 3 {
                    result += "   ... (\(featureNames.count - 3) more features)\n"
                }
            } else {
                result += "\(index + 1). \(String(describing: type(of: obj)))\n"
            }
            result += "\n"
        }

        return result
    }

    /// Generates a tree view of objects and their relationships.
    ///
    /// - Parameter objects: The objects to display in tree format.
    /// - Returns: Formatted tree string.
    private func generateTree(for objects: [any EObject]) -> String {
        var result = "Object Tree\n"
        result += "===========\n"

        for (index, obj) in objects.enumerated() {
            result += generateTreeNode(for: obj, prefix: "", isLast: index == objects.count - 1)
        }

        return result
    }

    /// Generates a single tree node representation.
    ///
    /// - Parameters:
    ///   - obj: The object to represent.
    ///   - prefix: The prefix for indentation.
    ///   - isLast: Whether this is the last node at this level.
    /// - Returns: Formatted tree node string.
    private func generateTreeNode(for obj: any EObject, prefix: String, isLast: Bool) -> String {
        var result = ""
        let nodePrefix = isLast ? "+-- " : "|-- "

        if let dynamicObj = obj as? DynamicEObject {
            result += "\(prefix)\(nodePrefix)\(dynamicObj.eClass.name) (id: \(dynamicObj.id))\n"
        } else {
            result += "\(prefix)\(nodePrefix)\(String(describing: type(of: obj)))\n"
        }

        return result
    }
}

// MARK: - Error Types

/// Errors that can occur during model validation.
enum ValidationError: Error, LocalizedError {
    /// The specified file was not found.
    case fileNotFound(String)

    /// The file format is not supported.
    case unsupportedFormat(String)

    /// Parsing failed with details.
    case parsingFailed(String, String)

    /// A localised description of the error.
    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .unsupportedFormat(let format):
            return "Unsupported format: \(format)"
        case .parsingFailed(let format, let details):
            return "Failed to parse \(format): \(details)"
        }
    }
}

/// Errors that can occur during format conversion.
enum ConversionError: Error, LocalizedError {
    /// The input file was not found.
    case fileNotFound(String)

    /// The output file already exists.
    case outputExists(String)

    /// The input format is not supported.
    case unsupportedInputFormat(String)

    /// The output format is not supported.
    case unsupportedOutputFormat(String)

    /// A localised description of the error.
    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "Input file not found: \(path)"
        case .outputExists(let path):
            return "Output file already exists: \(path) (use --force to overwrite)"
        case .unsupportedInputFormat(let format):
            return "Unsupported input format: \(format)"
        case .unsupportedOutputFormat(let format):
            return "Unsupported output format: \(format)"
        }
    }
}

/// Errors that can occur during code generation.
enum GenerationError: Error, LocalizedError {
    /// The input file was not found.
    case fileNotFound(String)

    /// The file format is not supported.
    case unsupportedFormat(String)

    /// The target language is not supported.
    case unsupportedLanguage(String)

    /// A localised description of the error.
    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "Input file not found: \(path)"
        case .unsupportedFormat(let format):
            return "Unsupported format: \(format)"
        case .unsupportedLanguage(let language):
            return "Unsupported language: \(language). Supported: swift, cpp, c, llvm"
        }
    }
}

/// Errors that can occur during query execution.
enum QueryError: Error, LocalizedError {
    /// The specified file was not found.
    case fileNotFound(String)

    /// The file format is not supported.
    case unsupportedFormat(String)

    /// The query is invalid.
    case invalidQuery(String)

    /// The query type is not supported.
    case unsupportedQuery(String)

    /// A localised description of the error.
    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .unsupportedFormat(let format):
            return "Unsupported format: \(format)"
        case .invalidQuery(let details):
            return "Invalid query: \(details)"
        case .unsupportedQuery(let query):
            return "Unsupported query: \(query)"
        }
    }
}
