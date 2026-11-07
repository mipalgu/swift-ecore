//
// EmfaticFixtures.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//

/// Neutral, self-authored Emfatic documents used by the tests.
enum EmfaticFixtures {
    /// A library metamodel that uses most constructs of Emfatic, in canonical form.
    static let library = """
        @GenModel(documentation="A small lending library")
        @namespace(uri="http://example.org/library", prefix="lib")
        package library;

        abstract class Item {
        	id attr String identifier;
        	attr String title;
        	attr int copies = 1;
        	attr boolean available = true;
        	!unique !ordered attr String[*] tags;
        	readonly volatile transient derived attr int loanCount;
        	op boolean isLoanable();
        }

        class Book extends Item, Described {
        	attr String[1] isbn;
        	ref Author[+]#books authors;
        	unsettable attr EDate published;
        	attr Genre genre = "fiction";
        }

        interface Described {
        	attr String description;
        	op void describe(String prefix, int depth) throws LibraryProblem;
        }

        class Author {
        	attr String name;
        	ref Book[*]#authors books;
        }

        class Library {
        	val Item[*] items;
        	val Member[*]#library members;
        	!resolve ref Author[0..5] featured;
        	op <T extends Item> T[*] itemsOfKind(Class kind);
        }

        class Member {
        	ref Library#members library;
        	attr char initial = 'M';
        	attr long joined = "0";
        }

        class LibraryProblem {
        }

        class Box<T extends Item> {
        	ref T[*] contents;
        	op T first();
        }

        class BookBox extends Box<Book> {
        }

        enum Genre {
        	fiction = 0;
        	poetry = 1;
        	reference = 5;
        }

        datatype Isbn : java.lang.String;

        transient datatype Cover : "byte[]";

        mapentry Index : String -> Item[*];

        @namespace(uri="urn:archive", prefix="arc")
        package archive {
        	class Shelf {
        		val Item[*] items;
        	}
        }
        """
}
