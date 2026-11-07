//
// OCLinEcoreFixtures.swift
// ECoreTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import OCL

@testable import ECore

/// Self-authored OCLinEcore documents for the tests.
enum OCLinEcoreFixtures {
    /// A school model in the writer's layout, which exercises every construct the writer emits.
    static let school = """
        import ecore : 'http://www.eclipse.org/emf/2002/Ecore#/';

        package school : sch = 'http://example.org/school'
        {
        \tdocumentation 'A neutral school model for tests.';
        \tpackage records : rec = 'http://example.org/school/records'
        \t{
        \t\tclass Transcript;
        \t}
        \tenum Level
        \t{
        \t\tliteral introductory;
        \t\tliteral advanced = 5;
        \t\tliteral research : 'Research';
        \t}
        \tdatatype Code : 'java.lang.String' { serializable }
        \t{
        \t\tinvariant WellFormed: self.size() = 6;
        \t}
        \tabstract class Named
        \t{
        \t\tattribute name : String;
        \t\tattribute nickname : String[?];
        \t}
        \tclass School extends Named
        \t{
        \t\tproperty courses#school : Course[*] { composes, ordered };
        \t\tproperty students : Student[*] { composes }
        \t\t{
        \t\t\tkey name;
        \t\t}
        \t}
        \tclass Course extends Named
        \t{
        \t\tinvariant HasCapacity: capacity > 0;
        \t\tinvariant NotOverfull('Too many enrolments for ' + name): enrolments->size() <= capacity;
        \t\tattribute capacity : Integer = '30';
        \t\tattribute level : Level;
        \t\tattribute topics : String[*] { ordered, !unique };
        \t\tattribute credit : ecore::EDouble[?];
        \t\tproperty school#courses : School[?];
        \t\tproperty enrolments : Enrolment[*] { derived, readonly, transient, volatile }
        \t\t{
        \t\t\tderivation: school.students.enrolments->select(e | e.course = self);
        \t\t}
        \t\toperation isFull() : Boolean
        \t\t{
        \t\t\tbody: enrolments->size() >= capacity;
        \t\t}
        \t\toperation enrol(student : Student) : Enrolment[?]
        \t\t{
        \t\t\tprecondition Open: not isFull();
        \t\t\tprecondition: student <> null;
        \t\t\tpostcondition Recorded: enrolments->exists(e | e.student = student);
        \t\t}
        \t}
        \tclass Student extends Named
        \t{
        \t\tinvariant: enrolments->isUnique(course);
        \t\tattribute year : Integer
        \t\t{
        \t\t\tinitial: 1;
        \t\t}
        \t\tproperty enrolments : Enrolment[*] { composes };
        \t}
        \tclass Enrolment
        \t{
        \t\tannotation 'http://example.org/notes'(reviewed = 'yes');
        \t\tproperty course : Course;
        \t\tproperty student : Student { !resolve };
        \t\tattribute since : ecore::EDate[?];
        \t\tattribute active : Boolean[?];
        \t}
        }

        """

    /// A loosely formatted document that uses alternative spellings of the same constructs.
    static let informal = """
        -- A comment before the package
        package shop : shop = 'http://example.org/shop' {
          class Product {
            attribute price : Real;
            attribute sku : String { id };
            invariant PositivePrice : price > 0.0 ;
            /* a block comment */
            operation discounted(rate : Real) : Real { body : price * (1 - rate) ; }
          }
          enum Size { small; medium; large = 10; }
          class Basket { property items : Product[0..*] {ordered,unique}; attribute count : Integer[1..1]; }
        }
        """
}

/// Renders the structure of packages as text, so that tests can compare packages without
/// regard to identifiers.
enum MetamodelSummary {
    static func describe(_ packages: [EPackage]) -> String {
        var references: [EUUID: String] = [:]
        var attributes: [EUUID: String] = [:]
        func index(_ package: EPackage) {
            for case let eClass as EClass in package.eClassifiers {
                for feature in eClass.eStructuralFeatures {
                    if let reference = feature as? EReference { references[reference.id] = eClass.name + "." + reference.name }
                    if let attribute = feature as? EAttribute { attributes[attribute.id] = attribute.name }
                }
            }
            package.eSubpackages.forEach(index)
        }
        packages.forEach(index)
        var lines: [String] = []
        func annotations(_ element: some EModelElement, _ indent: String) {
            for annotation in element.eAnnotations {
                lines.append(indent + "@" + annotation.source + " " + annotation.details.map { "\($0.key)=\($0.value)" }.joined(separator: "|"))
            }
        }
        func describe(_ package: EPackage, _ indent: String) {
            lines.append(indent + "package \(package.name) \(package.nsPrefix) \(package.nsURI)")
            annotations(package, indent + "  ")
            for classifier in package.eClassifiers {
                switch classifier {
                case let eClass as EClass:
                    lines.append(indent + "  class \(eClass.name) abstract=\(eClass.isAbstract) interface=\(eClass.isInterface) super=\(eClass.eSuperTypes.map(\.name)) instance=\(eClass.instanceClassName ?? "-")")
                    annotations(eClass, indent + "    ")
                    for feature in eClass.eStructuralFeatures {
                        if let a = feature as? EAttribute {
                            lines.append(indent + "    attribute \(a.name):\(a.eType.name)[\(a.lowerBound)..\(a.upperBound)] o=\(a.ordered) u=\(a.unique) c=\(a.changeable) v=\(a.volatile) t=\(a.transient) d=\(a.derived) id=\(a.isID) us=\(a.unsettable) default=\(a.defaultValueLiteral ?? "-")")
                            annotations(a, indent + "      ")
                        }
                        if let r = feature as? EReference {
                            lines.append(indent + "    reference \(r.name):\(r.eType.name)[\(r.lowerBound)..\(r.upperBound)] o=\(r.ordered) u=\(r.unique) c=\(r.changeable) v=\(r.volatile) t=\(r.transient) d=\(r.derived) us=\(r.unsettable) contains=\(r.containment) resolve=\(r.resolveProxies) opposite=\(r.opposite.flatMap { references[$0] } ?? "-") keys=\(r.eKeys.compactMap { attributes[$0] })")
                            annotations(r, indent + "      ")
                        }
                    }
                    for operation in eClass.eOperations {
                        lines.append(indent + "    operation \(operation.name)(\(operation.eParameters.map { "\($0.name):\($0.eType?.name ?? "-")[\($0.lowerBound)..\($0.upperBound)]" }.joined(separator: ","))):\(operation.eType?.name ?? "-")[\(operation.lowerBound)..\(operation.upperBound)] o=\(operation.ordered) u=\(operation.unique)")
                        annotations(operation, indent + "      ")
                    }
                case let eEnum as EEnum:
                    lines.append(indent + "  enum \(eEnum.name) serialisable=\(eEnum.serialisable) " + eEnum.literals.map { "\($0.name)=\($0.value):\($0.literal ?? "-")" }.joined(separator: ","))
                    annotations(eEnum, indent + "    ")
                case let dataType as EDataType:
                    lines.append(indent + "  datatype \(dataType.name) serialisable=\(dataType.serialisable) instance=\(dataType.instanceClassName ?? "-")")
                    annotations(dataType, indent + "    ")
                default:
                    break
                }
            }
            for subpackage in package.eSubpackages { describe(subpackage, indent + "  ") }
        }
        packages.forEach { describe($0, "") }
        return lines.joined(separator: "\n")
    }
}
