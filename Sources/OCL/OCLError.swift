//
// OCLError.swift
// OCL
//
//  Created by Rene Hexel on 18/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//

/// Errors that can occur during OCL operation evaluation.
///
/// OCL operations may fail due to invalid arguments, type mismatches, or other runtime conditions.
/// This enumeration provides structured error reporting for all OCL operation failures.
public enum OCLError: Error, Sendable, Equatable, CustomStringConvertible {
    /// Invalid arguments were provided to an OCL operation.
    case invalidArguments(String)
    
    /// Division by zero was attempted.
    case divisionByZero
    
    /// An invalid operation was requested.
    case invalidOperation(String)
    
    /// A type error occurred during operation evaluation.
    case typeError(String)
    
    /// An index was out of bounds for a collection.
    case indexOutOfBounds(Int, Int)  // index, size
    
    /// An operation was attempted on an empty collection.
    case emptyCollection(String)
    
    /// A human-readable description of the error.
    public var description: String {
        switch self {
        case .invalidArguments(let message):
            return "Invalid arguments: \(message)"
        case .divisionByZero:
            return "Division by zero"
        case .invalidOperation(let message):
            return "Invalid operation: \(message)"
        case .typeError(let message):
            return "Type error: \(message)"
        case .indexOutOfBounds(let index, let size):
            return "Index \(index) out of bounds for collection of size \(size)"
        case .emptyCollection(let operation):
            return "Cannot perform '\(operation)' on empty collection"
        }
    }
}

