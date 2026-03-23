//
//  Item.swift
//  English word app
//
//  Created by 岡田瑠聖 on 2026/03/23.
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
