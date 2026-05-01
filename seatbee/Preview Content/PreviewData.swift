import Foundation

enum PreviewData {
    static let sampleGuests: [Guest] = [
        Guest(id: "g1", name: "Sarah Chen", categories: ["Wedding Party"], dietary: nil, notes: nil, rsvp: .yes, side: .bride, vip: true),
        Guest(id: "g2", name: "Jon Park", categories: ["Wedding Party"], dietary: nil, notes: nil, rsvp: .yes, side: .groom, vip: true),
        Guest(id: "g3", name: "Linda Chen", categories: ["Family"], dietary: "Vegetarian", notes: "Aunt", rsvp: .yes, side: .bride, vip: false),
        Guest(id: "g4", name: "Mike Park", categories: ["Family"], dietary: nil, notes: "Uncle", rsvp: .yes, side: .groom, vip: false),
        Guest(id: "g5", name: "Emma Wilson", categories: ["Friends"], dietary: nil, notes: nil, rsvp: .yes, side: .bride, vip: false),
        Guest(id: "g6", name: "James Taylor", categories: ["Friends"], dietary: "Gluten-free", notes: nil, rsvp: .pending, side: .groom, vip: false),
        Guest(id: "g7", name: "Olivia Martinez", categories: ["Work"], dietary: nil, notes: nil, rsvp: .yes, side: .bride, vip: false, plusOne: true),
        Guest(id: "g8", name: "David Kim", categories: ["Work"], dietary: nil, notes: nil, rsvp: .no, side: .groom, vip: false),
    ]

    static let sampleTables: [SeatTable] = [
        SeatTable(id: "t1", name: "Table 1", type: .round, seats: 8, x: 100, y: 100, assignments: ["g1": 0, "g2": 1, "g3": 2]),
        SeatTable(id: "t2", name: "Table 2", type: .round, seats: 8, x: 250, y: 100, assignments: ["g4": 0, "g5": 1]),
        SeatTable(id: "t3", name: "Table 3", type: .round, seats: 8, x: 400, y: 100, assignments: [:]),
        SeatTable(id: "t4", name: "Table 4", type: .round, seats: 8, x: 100, y: 250, assignments: ["g7": 0]),
        SeatTable(id: "t5", name: "Table 5", type: .round, seats: 10, x: 250, y: 250, assignments: [:]),
        SeatTable(id: "t6", name: "Head Table", type: .head, seats: 12, x: 250, y: 50, assignments: [:]),
    ]

    static let samplePlan = SeatingPlan(
        id: "plan1",
        name: "Sarah & Jon",
        eventDate: Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 15)),
        venue: "The Garden House",
        eventType: .wedding,
        tables: sampleTables,
        guests: sampleGuests,
        rules: [
            SeatingRule(id: "r1", type: .seatTogether, guests: ["g1", "g2"], weight: 100, hard: true, enabled: true),
            SeatingRule(id: "r2", type: .keepApart, guests: ["g3", "g4"], weight: 80, hard: false, enabled: true),
        ],
        objects: [],
        createdAt: Date(),
        updatedAt: Date(),
        userId: "user1",
        tier: "signature_pass"
    )
}
