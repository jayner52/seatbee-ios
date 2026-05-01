//
//  Item.swift
//  seatbee
//
//  Created by Shayan Mirzazadeh on 2026-05-01.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
