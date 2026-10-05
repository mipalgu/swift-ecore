//
// LineTable.swift
// EMFBase
//
// Copyright © 2025 Rene Hexel. All rights reserved.
//

/// Converts between offsets and line and column positions in a text.
///
/// A line table is built once from a string and answers position queries in
/// logarithmic time. Line ends are LF, CRLF (a single end) and lone CR.
/// Lines and columns are one-based, and columns count Unicode scalars from
/// the start of the line. Offsets are UTF-8 byte offsets, with conversions
/// to and from UTF-16 offsets for text views that index in UTF-16 code units.
/// Offsets beyond the text are clamped to the end of the text, and offsets
/// that fall inside a multi-byte scalar resolve to the start of that scalar.
public struct LineTable: Sendable {
    private let bytes: [UInt8]
    private let lineStarts: [Int]
    private let lineUTF16Starts: [Int]

    /// Creates a line table for a text.
    ///
    /// - Parameter text: The text to index.
    public init(_ text: String) {
        let bytes = Array(text.utf8)
        var starts = [0]
        var utf16Starts = [0]
        var utf16 = 0
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            if Self.isStartByte(byte) { utf16 += byte >= 0xF0 ? 2 : 1 }
            index += 1
            if byte == 0x0D {
                if index < bytes.count && bytes[index] == 0x0A {
                    index += 1
                    utf16 += 1
                }
                starts.append(index)
                utf16Starts.append(utf16)
            } else if byte == 0x0A {
                starts.append(index)
                utf16Starts.append(utf16)
            }
        }
        self.bytes = bytes
        self.lineStarts = starts
        self.lineUTF16Starts = utf16Starts
    }

    /// The number of lines; an empty text has one empty line.
    public var lineCount: Int { lineStarts.count }

    /// The length of the text in UTF-8 code units.
    public var utf8Count: Int { bytes.count }

    /// The length of the text in UTF-16 code units.
    public var utf16Count: Int { utf16Offset(forUTF8Offset: bytes.count) }

    /// The location corresponding to a UTF-8 offset.
    ///
    /// - Parameter offset: The zero-based UTF-8 offset; clamped to the text.
    /// - Returns: The location with its line and column.
    public func location(forUTF8Offset offset: Int) -> SourceLocation {
        let offset = scalarStart(atOrBefore: offset)
        let line = lineIndex(containing: offset)
        var column = 1
        for index in lineStarts[line]..<offset where Self.isStartByte(bytes[index]) {
            column += 1
        }
        return SourceLocation(utf8Offset: offset, line: line + 1, column: column)
    }

    /// The UTF-8 offset corresponding to a line and column.
    ///
    /// The column one past the last character of a line (before its line end)
    /// is valid.
    ///
    /// - Parameters:
    ///   - line: The one-based line number.
    ///   - column: The one-based column in Unicode scalars.
    /// - Returns: The offset, or `nil` if the line or column does not exist.
    public func utf8Offset(line: Int, column: Int) -> Int? {
        guard line >= 1, line <= lineStarts.count, column >= 1,
            let content = contentRange(ofLine: line)
        else { return nil }
        var remaining = column - 1
        var index = content.lowerBound
        while remaining > 0 {
            guard index < content.upperBound else { return nil }
            index += 1
            while index < content.upperBound && !Self.isStartByte(bytes[index]) { index += 1 }
            remaining -= 1
        }
        return index
    }

    /// The UTF-8 range of a line, excluding its line end.
    ///
    /// - Parameter line: The one-based line number.
    /// - Returns: The byte range, or `nil` if the line does not exist.
    public func contentRange(ofLine line: Int) -> Range<Int>? {
        guard line >= 1, line <= lineStarts.count else { return nil }
        let start = lineStarts[line - 1]
        var end = line < lineStarts.count ? lineStarts[line] : bytes.count
        if line < lineStarts.count {
            if end > start && bytes[end - 1] == 0x0A { end -= 1 }
            if end > start && bytes[end - 1] == 0x0D { end -= 1 }
        }
        return start..<end
    }

    /// The UTF-16 offset corresponding to a UTF-8 offset.
    ///
    /// - Parameter offset: The zero-based UTF-8 offset; clamped to the text.
    /// - Returns: The offset in UTF-16 code units.
    public func utf16Offset(forUTF8Offset offset: Int) -> Int {
        let offset = scalarStart(atOrBefore: offset)
        let line = lineIndex(containing: offset)
        var utf16 = lineUTF16Starts[line]
        for index in lineStarts[line]..<offset where Self.isStartByte(bytes[index]) {
            utf16 += bytes[index] >= 0xF0 ? 2 : 1
        }
        return utf16
    }

    /// The UTF-8 offset corresponding to a UTF-16 offset.
    ///
    /// An offset between the two halves of a surrogate pair resolves to the
    /// start of that scalar.
    ///
    /// - Parameter offset: The zero-based UTF-16 offset; clamped to the text.
    /// - Returns: The offset in UTF-8 code units.
    public func utf8Offset(forUTF16Offset offset: Int) -> Int {
        guard offset > 0 else { return 0 }
        var low = 0
        var high = lineUTF16Starts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lineUTF16Starts[mid] <= offset { low = mid } else { high = mid - 1 }
        }
        var utf16 = lineUTF16Starts[low]
        var index = lineStarts[low]
        while index < bytes.count {
            let width = bytes[index] >= 0xF0 ? 2 : 1
            if utf16 + width > offset { break }
            utf16 += width
            index += 1
            while index < bytes.count && !Self.isStartByte(bytes[index]) { index += 1 }
        }
        return index
    }

    /// Builds a range from two UTF-8 offsets.
    ///
    /// - Parameters:
    ///   - start: The inclusive start offset.
    ///   - end: The exclusive end offset.
    /// - Returns: The corresponding range.
    public func range(fromUTF8Offset start: Int, to end: Int) -> SourceRange {
        SourceRange(start: location(forUTF8Offset: start), end: location(forUTF8Offset: end))
    }

    private static func isStartByte(_ byte: UInt8) -> Bool { byte & 0xC0 != 0x80 }

    private func scalarStart(atOrBefore offset: Int) -> Int {
        var index = min(max(offset, 0), bytes.count)
        while index > 0 && index < bytes.count && !Self.isStartByte(bytes[index]) { index -= 1 }
        return index
    }

    private func lineIndex(containing offset: Int) -> Int {
        var low = 0
        var high = lineStarts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lineStarts[mid] <= offset { low = mid } else { high = mid - 1 }
        }
        return low
    }
}
