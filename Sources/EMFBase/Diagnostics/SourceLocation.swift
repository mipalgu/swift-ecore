//
// SourceLocation.swift
// EMFBase
//
// Copyright © 2025 Rene Hexel. All rights reserved.
//

/// A position within a text document.
///
/// A location records the zero-based UTF-8 byte offset from the start of the
/// document together with the one-based line and column of that position.
/// Columns count Unicode scalars from the start of the line, so a character
/// outside the Basic Multilingual Plane occupies a single column. Locations
/// are ordered by their UTF-8 offset.
public struct SourceLocation: Sendable, Hashable, Comparable, Codable {
    /// The zero-based offset in UTF-8 code units from the start of the document.
    public var utf8Offset: Int

    /// The one-based line number.
    public var line: Int

    /// The one-based column, counted in Unicode scalars from the start of the line.
    public var column: Int

    /// Creates a location.
    ///
    /// - Parameters:
    ///   - utf8Offset: The zero-based UTF-8 offset from the start of the document.
    ///   - line: The one-based line number.
    ///   - column: The one-based column, counted in Unicode scalars.
    public init(utf8Offset: Int, line: Int, column: Int) {
        self.utf8Offset = utf8Offset
        self.line = line
        self.column = column
    }

    /// The location at the very start of a document.
    public static let start = SourceLocation(utf8Offset: 0, line: 1, column: 1)

    /// Orders two locations of the same document by their UTF-8 offsets.
    ///
    /// - Parameters:
    ///   - lhs: The first location.
    ///   - rhs: The second location.
    /// - Returns: `true` if `lhs` precedes `rhs`.
    public static func < (lhs: SourceLocation, rhs: SourceLocation) -> Bool {
        lhs.utf8Offset < rhs.utf8Offset
    }
}

/// A half-open span of text within a document.
///
/// The range starts at `start` and extends up to, but does not include,
/// `end`. A range whose bounds coincide is empty and denotes an insertion
/// point.
public struct SourceRange: Sendable, Hashable, Codable {
    /// The first location inside the range.
    public var start: SourceLocation

    /// The first location after the range (exclusive).
    public var end: SourceLocation

    /// Creates a range.
    ///
    /// - Parameters:
    ///   - start: The inclusive start of the range.
    ///   - end: The exclusive end of the range.
    public init(start: SourceLocation, end: SourceLocation) {
        self.start = start
        self.end = end
    }

    /// Whether the range covers no text.
    public var isEmpty: Bool { start.utf8Offset >= end.utf8Offset }

    /// The length of the range in UTF-8 code units.
    public var utf8Length: Int { max(0, end.utf8Offset - start.utf8Offset) }

    /// Tests whether a location lies inside the range.
    ///
    /// - Parameter location: The location to test.
    /// - Returns: `true` if `start <= location < end`.
    public func contains(_ location: SourceLocation) -> Bool {
        location.utf8Offset >= start.utf8Offset && location.utf8Offset < end.utf8Offset
    }

    /// Tests whether another range lies entirely inside this one.
    ///
    /// - Parameter other: The range to test.
    /// - Returns: `true` if both bounds of `other` lie within this range (inclusive of the end).
    public func contains(_ other: SourceRange) -> Bool {
        other.start.utf8Offset >= start.utf8Offset && other.end.utf8Offset <= end.utf8Offset
    }

    /// Tests whether two ranges share at least one location.
    ///
    /// - Parameter other: The range to test.
    /// - Returns: `true` if the ranges overlap; empty ranges never overlap.
    public func overlaps(_ other: SourceRange) -> Bool {
        !isEmpty && !other.isEmpty
            && start.utf8Offset < other.end.utf8Offset && other.start.utf8Offset < end.utf8Offset
    }

    /// The smallest range covering both this range and another.
    ///
    /// - Parameter other: The range to combine with.
    /// - Returns: A range from the earlier start to the later end.
    public func union(_ other: SourceRange) -> SourceRange {
        SourceRange(start: min(start, other.start), end: max(end, other.end))
    }

    /// The smallest range covering a sequence of ranges.
    ///
    /// - Parameter ranges: The ranges to combine.
    /// - Returns: The union, or `nil` if the sequence is empty.
    public static func union<S: Sequence>(of ranges: S) -> SourceRange? where S.Element == SourceRange {
        ranges.reduce(nil) { partial, next in partial.map { $0.union(next) } ?? next }
    }
}

/// An optional source range carried by syntax tree nodes.
///
/// Origins are deliberately neutral: every origin compares equal to every
/// other origin and contributes nothing to a hash. Adding an origin property
/// to a value type therefore never changes its equality or hashing, so two
/// trees that differ only in where they were parsed from remain equal.
public struct SourceOrigin: Sendable, Hashable, Codable {
    /// The source range this value was parsed from, if known.
    public var range: SourceRange?

    /// Creates an origin.
    ///
    /// - Parameter range: The originating range, or `nil` if unknown.
    public init(_ range: SourceRange? = nil) {
        self.range = range
    }

    /// Compares two origins; the result is always `true`.
    ///
    /// - Parameters:
    ///   - lhs: The first origin.
    ///   - rhs: The second origin.
    /// - Returns: `true`, regardless of the ranges.
    public static func == (lhs: SourceOrigin, rhs: SourceOrigin) -> Bool { true }

    /// Hashes nothing, keeping the owner's hash independent of its origin.
    ///
    /// - Parameter hasher: The hasher, which is left unchanged.
    public func hash(into hasher: inout Hasher) {}
}
