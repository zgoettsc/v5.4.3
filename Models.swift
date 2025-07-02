import Foundation

struct LogEntry: Equatable, Codable, Hashable, Identifiable {
    let id = UUID() // Local identifier, not used for uniqueness in Set
    let date: Date
    let userId: UUID
    
    enum CodingKeys: String, CodingKey {
        case date = "timestamp"
        case userId
        // 'id' is not included in CodingKeys since it's not stored in Firebase
    }
    
    init(date: Date, userId: UUID) {
        self.date = date
        self.userId = userId
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let dateString = try container.decode(String.self, forKey: .date)
        guard let decodedDate = ISO8601DateFormatter().date(from: dateString) else {
            throw DecodingError.dataCorruptedError(forKey: .date, in: container, debugDescription: "Invalid ISO8601 date string")
        }
        self.date = decodedDate
        self.userId = try container.decode(UUID.self, forKey: .userId)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let dateString = ISO8601DateFormatter().string(from: date)
        try container.encode(dateString, forKey: .date)
        try container.encode(userId, forKey: .userId)
    }
    
    // Hashable conformance: Ignore id, use only date and userId
    static func == (lhs: LogEntry, rhs: LogEntry) -> Bool {
        return lhs.date == rhs.date && lhs.userId == rhs.userId
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(date)
        hasher.combine(userId)
    }
}

// Cycle conforms to Equatable and Codable
// Replace the entire existing Cycle struct in Models.swift with this:

struct Cycle: Identifiable, Codable {
    let id: UUID
    let number: Int
    let patientName: String
    let startDate: Date
    let foodChallengeDate: Date
    let missedDoses: [MissedDose]?
    
    enum CodingKeys: String, CodingKey {
        case id, number, patientName, startDate, foodChallengeDate, missedDoses
    }
    
    init(id: UUID = UUID(), number: Int, patientName: String, startDate: Date, foodChallengeDate: Date, missedDoses: [MissedDose]? = nil) {
        self.id = id
        self.number = number
        self.patientName = patientName
        self.startDate = startDate
        self.foodChallengeDate = foodChallengeDate
        self.missedDoses = missedDoses
    }
    
    init?(dictionary: [String: Any]) {
        guard let idStr = dictionary["id"] as? String, let id = UUID(uuidString: idStr),
              let number = dictionary["number"] as? Int,
              let patientName = dictionary["patientName"] as? String,
              let startDateStr = dictionary["startDate"] as? String,
              let foodChallengeDateStr = dictionary["foodChallengeDate"] as? String else {
            return nil
        }
        self.id = id
        self.number = number
        self.patientName = patientName
        
        let formatter = ISO8601DateFormatter()
        guard let decodedStartDate = formatter.date(from: startDateStr) else {
            return nil // Changed from throw to return nil
        }
        startDate = decodedStartDate
        
        guard let decodedFoodChallengeDate = formatter.date(from: foodChallengeDateStr) else {
            return nil // Changed from throw to return nil
        }
        foodChallengeDate = decodedFoodChallengeDate
        
        // Parse missed doses
        if let missedDosesArray = dictionary["missedDoses"] as? [[String: Any]] {
            self.missedDoses = missedDosesArray.compactMap { MissedDose(dictionary: $0) }
        } else {
            self.missedDoses = nil
        }
    }
    
    // Add toDictionary method
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id.uuidString,
            "number": number,
            "patientName": patientName,
            "startDate": ISO8601DateFormatter().string(from: startDate),
            "foodChallengeDate": ISO8601DateFormatter().string(from: foodChallengeDate)
        ]
        
        if let missedDoses = missedDoses, !missedDoses.isEmpty {
            dict["missedDoses"] = missedDoses.map { dose in
                [
                    "id": dose.id.uuidString,
                    "date": ISO8601DateFormatter().string(from: dose.date),
                    "cycleId": dose.cycleId.uuidString
                ]
            }
        }
        
        return dict
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        number = try container.decode(Int.self, forKey: .number)
        patientName = try container.decode(String.self, forKey: .patientName)
        
        let startDateString = try container.decode(String.self, forKey: .startDate)
        let formatter = ISO8601DateFormatter()
        guard let decodedStartDate = formatter.date(from: startDateString) else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Invalid ISO8601 date string"))
        }
        startDate = decodedStartDate
        
        let foodChallengeDateString = try container.decode(String.self, forKey: .foodChallengeDate)
        guard let decodedFoodChallengeDate = formatter.date(from: foodChallengeDateString) else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Invalid ISO8601 date string"))
        }
        foodChallengeDate = decodedFoodChallengeDate
        
        missedDoses = try container.decodeIfPresent([MissedDose].self, forKey: .missedDoses)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(number, forKey: .number)
        try container.encode(patientName, forKey: .patientName)
        try container.encode(ISO8601DateFormatter().string(from: startDate), forKey: .startDate)
        try container.encode(ISO8601DateFormatter().string(from: foodChallengeDate), forKey: .foodChallengeDate)
        try container.encodeIfPresent(missedDoses, forKey: .missedDoses)
    }
}

struct WeeklyDoseData: Codable, Equatable {
    let dose: Double
    let unit: String
    
    static func == (lhs: WeeklyDoseData, rhs: WeeklyDoseData) -> Bool {
        return lhs.dose == rhs.dose && lhs.unit == rhs.unit
    }
}

struct MissedDose: Codable, Identifiable {
    let id: UUID
    let date: Date
    let cycleId: UUID
    
    init(id: UUID = UUID(), date: Date, cycleId: UUID) {
        self.id = id
        self.date = date
        self.cycleId = cycleId
    }
    
    init?(dictionary: [String: Any]) {
        guard let idStr = dictionary["id"] as? String,
              let id = UUID(uuidString: idStr),
              let dateStr = dictionary["date"] as? String,
              let cycleIdStr = dictionary["cycleId"] as? String,
              let cycleId = UUID(uuidString: cycleIdStr) else {
            return nil
        }
        
        self.id = id
        self.cycleId = cycleId
        
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: dateStr) else {
            return nil
        }
        self.date = date
    }
}

// Item conforms to Identifiable and Codable
struct Item: Identifiable, Codable {
    let id: UUID
    let name: String
    let category: Category
    let dose: Double?
    let unit: String?
    let weeklyDoses: [Int: WeeklyDoseData]?
    let order: Int
    let scheduleType: ScheduleType?
    let customScheduleDays: Set<Int>?
    let everyOtherDayStartDate: Date?
    
    init(id: UUID = UUID(), name: String, category: Category, dose: Double? = nil, unit: String? = nil,
         weeklyDoses: [Int: WeeklyDoseData]? = nil, order: Int = 0,
         scheduleType: ScheduleType? = nil, customScheduleDays: Set<Int>? = nil, everyOtherDayStartDate: Date? = nil) {
        self.id = id
        self.name = name
        self.category = category
        self.dose = dose
        self.unit = unit
        self.weeklyDoses = weeklyDoses
        self.order = order
        self.scheduleType = scheduleType
        self.customScheduleDays = customScheduleDays
        self.everyOtherDayStartDate = everyOtherDayStartDate
    }
    
    init?(dictionary: [String: Any]) {
        guard let idStr = dictionary["id"] as? String, let id = UUID(uuidString: idStr),
              let name = dictionary["name"] as? String,
              let categoryStr = dictionary["category"] as? String,
              let category = Category(rawValue: categoryStr) else {
            print("Failed to parse item: missing id, name, or category in \(dictionary)")
            return nil
        }
        self.id = id
        self.name = name
        self.category = category
        self.dose = dictionary["dose"] as? Double
        self.unit = dictionary["unit"] as? String
        
        // Enhanced weekly doses parsing
        var parsedDoses: [Int: WeeklyDoseData] = [:]
        
        if let weeklyDosesDict = dictionary["weeklyDoses"] as? [String: Any] {
            for (weekKey, value) in weeklyDosesDict {
                guard let weekNum = Int(weekKey) else {
                    print("Invalid week key: \(weekKey) in weeklyDoses")
                    continue
                }
                if let doseDataDict = value as? [String: Any],
                   let doseValue = doseDataDict["dose"] as? Double,
                   let unitValue = doseDataDict["unit"] as? String {
                    parsedDoses[weekNum] = WeeklyDoseData(dose: doseValue, unit: unitValue)
                } else if let doseValue = value as? Double {
                    // Legacy format with just dose, use item unit as fallback
                    parsedDoses[weekNum] = WeeklyDoseData(dose: doseValue, unit: self.unit ?? "")
                    print("Parsed legacy weekly dose for week \(weekNum): \(doseValue)")
                } else {
                    print("Failed to parse weekly dose for week \(weekKey): \(value)")
                }
            }
        } else if let weeklyDosesArray = dictionary["weeklyDoses"] as? [Any] {
            for (index, value) in weeklyDosesArray.enumerated() {
                if let doseDataDict = value as? [String: Any],
                   let doseValue = doseDataDict["dose"] as? Double,
                   let unitValue = doseDataDict["unit"] as? String {
                    parsedDoses[index] = WeeklyDoseData(dose: doseValue, unit: unitValue)
                } else if let doseValue = value as? Double {
                    // Simple number in array
                    parsedDoses[index] = WeeklyDoseData(dose: doseValue, unit: self.unit ?? "")
                } else if value is NSNull || value == nil {
                    // Skip null values in array
                    continue
                }
            }
        }
        
        self.weeklyDoses = parsedDoses.isEmpty ? nil : parsedDoses
        // Parse scheduling properties
        self.scheduleType = {
            if let scheduleTypeStr = dictionary["scheduleType"] as? String {
                return ScheduleType(rawValue: scheduleTypeStr)
            }
            return nil
        }()

        self.customScheduleDays = {
            if let daysArray = dictionary["customScheduleDays"] as? [Int] {
                return Set(daysArray)
            }
            return nil
        }()

        self.everyOtherDayStartDate = {
            if let dateStr = dictionary["everyOtherDayStartDate"] as? String {
                return ISO8601DateFormatter().date(from: dateStr)
            }
            return nil
        }()
        self.order = dictionary["order"] as? Int ?? 0
    }
    
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id.uuidString,
            "name": name,
            "category": category.rawValue,
            "order": order
        ]
        if let dose = dose { dict["dose"] = dose }
        if let unit = unit { dict["unit"] = unit }
        
        if let weeklyDoses = weeklyDoses {
            var weeklyDosesDict: [String: [String: Any]] = [:]
            for (week, doseData) in weeklyDoses {
                weeklyDosesDict[String(week)] = [
                    "dose": doseData.dose,
                    "unit": doseData.unit
                ]
            }
            dict["weeklyDoses"] = weeklyDosesDict
            print("Serialized weeklyDoses: \(weeklyDosesDict)")
        }
        // Add scheduling properties
        if let scheduleType = scheduleType {
            dict["scheduleType"] = scheduleType.rawValue
        }
        if let customScheduleDays = customScheduleDays, !customScheduleDays.isEmpty {
            dict["customScheduleDays"] = Array(customScheduleDays).sorted()
        }
        if let everyOtherDayStartDate = everyOtherDayStartDate {
            dict["everyOtherDayStartDate"] = ISO8601DateFormatter().string(from: everyOtherDayStartDate)
        }
        
        return dict
    }
    
    enum CodingKeys: String, CodingKey {
        case id, name, category, dose, unit, weeklyDoses, order, scheduleType, customScheduleDays, everyOtherDayStartDate
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        let categoryString = try container.decode(String.self, forKey: .category)
        guard let decodedCategory = Category(rawValue: categoryString) else {
            throw DecodingError.dataCorruptedError(forKey: .category, in: container, debugDescription: "Invalid category value")
        }
        category = decodedCategory
        dose = try container.decodeIfPresent(Double.self, forKey: .dose)
        unit = try container.decodeIfPresent(String.self, forKey: .unit)
        
        // Decode the weekly doses
        if let weeklyDosesDict = try container.decodeIfPresent([String: [String: String]].self, forKey: .weeklyDoses) {
            var decodedWeeklyDoses: [Int: WeeklyDoseData] = [:]
            for (weekStr, doseData) in weeklyDosesDict {
                if let week = Int(weekStr),
                   let doseStr = doseData["dose"],
                   let dose = Double(doseStr),
                   let unit = doseData["unit"] {
                    decodedWeeklyDoses[week] = WeeklyDoseData(dose: dose, unit: unit)
                }
            }
            weeklyDoses = decodedWeeklyDoses.isEmpty ? nil : decodedWeeklyDoses
        } else {
            weeklyDoses = nil
        }
        // Decode scheduling properties
        scheduleType = try container.decodeIfPresent(ScheduleType.self, forKey: .scheduleType)
        if let daysArray = try container.decodeIfPresent([Int].self, forKey: .customScheduleDays) {
            customScheduleDays = Set(daysArray)
        } else {
            customScheduleDays = nil
        }
        everyOtherDayStartDate = try container.decodeIfPresent(Date.self, forKey: .everyOtherDayStartDate)
        
        order = try container.decodeIfPresent(Int.self, forKey: .order) ?? 0
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(category.rawValue, forKey: .category)
        try container.encodeIfPresent(dose, forKey: .dose)
        try container.encodeIfPresent(unit, forKey: .unit)
        
        if let weeklyDoses = weeklyDoses {
            var encodedWeeklyDoses: [String: [String: String]] = [:]
            for (week, doseData) in weeklyDoses {
                encodedWeeklyDoses[String(week)] = [
                    "dose": String(doseData.dose),
                    "unit": doseData.unit
                ]
            }
            try container.encode(encodedWeeklyDoses, forKey: .weeklyDoses)
        }
        // Encode scheduling properties
        try container.encodeIfPresent(scheduleType, forKey: .scheduleType)
        if let customScheduleDays = customScheduleDays, !customScheduleDays.isEmpty {
            try container.encode(Array(customScheduleDays).sorted(), forKey: .customScheduleDays)
        }
        try container.encodeIfPresent(everyOtherDayStartDate, forKey: .everyOtherDayStartDate)
        
        try container.encode(order, forKey: .order)
    }
}

// Unit conforms to Hashable, Identifiable, and Codable
struct Unit: Hashable, Identifiable, Codable {
    let id: UUID
    let name: String
    
    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
    
    init?(dictionary: [String: Any]) {
        guard let idStr = dictionary["id"] as? String, let id = UUID(uuidString: idStr),
              let name = dictionary["name"] as? String else { return nil }
        self.id = id
        self.name = name
    }
    
    func toDictionary() -> [String: Any] {
        ["id": id.uuidString, "name": name]
    }
    
    static func == (lhs: Unit, rhs: Unit) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    enum CodingKeys: String, CodingKey {
        case id, name
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
    }
}

// User conforms to Identifiable, Equatable, and Codable
struct User: Identifiable, Equatable, Codable {
    let id: UUID
    let name: String
    let email: String? // NEW: Email field
    let authId: String?
    var ownedRooms: [String]? // Optional array for rooms owned by the user
    var subscriptionPlan: String? // Stores the product ID of the current subscription
    var roomLimit: Int // Maximum number of rooms allowed
    var isSuperAdmin: Bool
    var pendingTransferRequests: [String]? // Array of transfer request IDs
    var roomAccess: [String: RoomAccess]? // Room access with isAdmin per room
    var roomSettings: [String: RoomSettings]? // Room-specific settings
    var appVersionHistory: [String: String]? // NEW: Version history - [version: date]

    init(id: UUID = UUID(), name: String, email: String? = nil, authId: String? = nil,
         ownedRooms: [String]? = nil, subscriptionPlan: String? = nil, roomLimit: Int = 0,
         isSuperAdmin: Bool = false, pendingTransferRequests: [String]? = nil,
         roomAccess: [String: RoomAccess]? = nil, roomSettings: [String: RoomSettings]? = nil,
         appVersionHistory: [String: String]? = nil) {
        self.id = id
        self.name = name
        self.email = email
        self.authId = authId
        self.ownedRooms = ownedRooms
        self.subscriptionPlan = subscriptionPlan
        self.roomLimit = roomLimit
        self.isSuperAdmin = isSuperAdmin
        self.pendingTransferRequests = pendingTransferRequests
        self.roomAccess = roomAccess
        self.roomSettings = roomSettings
        self.appVersionHistory = appVersionHistory
    }

    init?(dictionary: [String: Any]) {
        guard let idStr = dictionary["id"] as? String, let id = UUID(uuidString: idStr),
              let name = dictionary["name"] as? String else { return nil }
        self.id = id
        self.name = name
        self.email = dictionary["email"] as? String
        self.authId = dictionary["authId"] as? String
        self.ownedRooms = dictionary["ownedRooms"] as? [String]
        self.subscriptionPlan = dictionary["subscriptionPlan"] as? String
        self.roomLimit = dictionary["roomLimit"] as? Int ?? 0
        self.isSuperAdmin = dictionary["isSuperAdmin"] as? Bool ?? false
        self.pendingTransferRequests = dictionary["pendingTransferRequests"] as? [String]
        
        // Parse version history and convert cleaned keys back to proper versions
        if let versionHistoryDict = dictionary["appVersionHistory"] as? [String: String] {
            var cleanedVersionHistory: [String: String] = [:]
            for (cleanVersion, date) in versionHistoryDict {
                // Convert back from cleaned version (e.g., "5_1" -> "5.1")
                let originalVersion = cleanVersion.replacingOccurrences(of: "_", with: ".")
                cleanedVersionHistory[originalVersion] = date
            }
            self.appVersionHistory = cleanedVersionHistory.isEmpty ? nil : cleanedVersionHistory
        } else {
            self.appVersionHistory = nil
        }

        // Parse roomAccess
        if let roomAccessDict = dictionary["roomAccess"] as? [String: [String: Any]] {
            self.roomAccess = roomAccessDict.compactMapValues { RoomAccess(dictionary: $0) }
        } else {
            self.roomAccess = nil
        }

        // Parse roomSettings
        if let roomSettingsDict = dictionary["roomSettings"] as? [String: [String: Any]] {
            self.roomSettings = roomSettingsDict.compactMapValues { RoomSettings(dictionary: $0) }
        } else {
            self.roomSettings = nil
        }
    }

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [:]
        
        // Core required fields
        dict["id"] = id.uuidString
        dict["name"] = name
        dict["roomLimit"] = roomLimit
        dict["isSuperAdmin"] = isSuperAdmin
        
        // Optional fields with validation
        if let email = email?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty {
            dict["email"] = email
        }
        
        if let authId = authId?.trimmingCharacters(in: .whitespacesAndNewlines), !authId.isEmpty {
            dict["authId"] = authId
        }
        
        if let ownedRooms = ownedRooms, !ownedRooms.isEmpty {
            dict["ownedRooms"] = ownedRooms
        }
        
        if let subscriptionPlan = subscriptionPlan?.trimmingCharacters(in: .whitespacesAndNewlines), !subscriptionPlan.isEmpty {
            dict["subscriptionPlan"] = subscriptionPlan
        }
        
        if let pendingTransferRequests = pendingTransferRequests, !pendingTransferRequests.isEmpty {
            dict["pendingTransferRequests"] = pendingTransferRequests
        }
        
        if let roomAccess = roomAccess, !roomAccess.isEmpty {
            dict["roomAccess"] = roomAccess.mapValues { $0.toDictionary() }
        }
        
        if let roomSettings = roomSettings, !roomSettings.isEmpty {
            dict["roomSettings"] = roomSettings.mapValues { $0.toDictionary() }
        }
        
        // Version history with extra safety
        if let appVersionHistory = appVersionHistory, !appVersionHistory.isEmpty {
            var cleanVersionHistory: [String: Any] = [:]
            
            for (version, date) in appVersionHistory {
                // Clean version key
                let cleanVersion = version
                    .replacingOccurrences(of: ".", with: "_")
                    .replacingOccurrences(of: "#", with: "_")
                    .replacingOccurrences(of: "$", with: "_")
                    .replacingOccurrences(of: "[", with: "_")
                    .replacingOccurrences(of: "]", with: "_")
                    .replacingOccurrences(of: "/", with: "_")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                
                let cleanDate = date.trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Only add if both are valid
                if !cleanVersion.isEmpty && !cleanDate.isEmpty {
                    cleanVersionHistory[cleanVersion] = cleanDate
                }
            }
            
            if !cleanVersionHistory.isEmpty {
                dict["appVersionHistory"] = cleanVersionHistory
            }
        }
        
        return dict
    }
    
    static func == (lhs: User, rhs: User) -> Bool {
        return lhs.id == rhs.id &&
               lhs.name == rhs.name &&
               lhs.email == rhs.email && // NEW: Include email in equality
               lhs.authId == rhs.authId &&
               lhs.ownedRooms == rhs.ownedRooms &&
               lhs.subscriptionPlan == rhs.subscriptionPlan &&
               lhs.roomLimit == rhs.roomLimit &&
               lhs.isSuperAdmin == rhs.isSuperAdmin &&
               lhs.pendingTransferRequests == rhs.pendingTransferRequests &&
               lhs.roomAccess == rhs.roomAccess &&
               lhs.roomSettings == rhs.roomSettings &&
               lhs.appVersionHistory == rhs.appVersionHistory // NEW: Include version history in equality
    }

    enum CodingKeys: String, CodingKey {
        case id, name, email, authId, ownedRooms, subscriptionPlan, roomLimit, isSuperAdmin, pendingTransferRequests, roomAccess, roomSettings, appVersionHistory
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        email = try container.decodeIfPresent(String.self, forKey: .email) // NEW: Decode email
        authId = try container.decodeIfPresent(String.self, forKey: .authId)
        ownedRooms = try container.decodeIfPresent([String].self, forKey: .ownedRooms)
        subscriptionPlan = try container.decodeIfPresent(String.self, forKey: .subscriptionPlan)
        roomLimit = try container.decodeIfPresent(Int.self, forKey: .roomLimit) ?? 0
        isSuperAdmin = try container.decodeIfPresent(Bool.self, forKey: .isSuperAdmin) ?? false
        pendingTransferRequests = try container.decodeIfPresent([String].self, forKey: .pendingTransferRequests)
        roomAccess = try container.decodeIfPresent([String: RoomAccess].self, forKey: .roomAccess)
        roomSettings = try container.decodeIfPresent([String: RoomSettings].self, forKey: .roomSettings)
        appVersionHistory = try container.decodeIfPresent([String: String].self, forKey: .appVersionHistory) // NEW: Decode version history
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(email, forKey: .email) // NEW: Encode email
        try container.encodeIfPresent(authId, forKey: .authId)
        try container.encodeIfPresent(ownedRooms, forKey: .ownedRooms)
        try container.encodeIfPresent(subscriptionPlan, forKey: .subscriptionPlan)
        try container.encode(roomLimit, forKey: .roomLimit)
        try container.encode(isSuperAdmin, forKey: .isSuperAdmin)
        try container.encodeIfPresent(pendingTransferRequests, forKey: .pendingTransferRequests)
        try container.encodeIfPresent(roomAccess, forKey: .roomAccess)
        try container.encodeIfPresent(roomSettings, forKey: .roomSettings)
        try container.encodeIfPresent(appVersionHistory, forKey: .appVersionHistory) // NEW: Encode version history
    }
}

// New supporting structs
struct RoomAccess: Codable, Equatable {
    let isActive: Bool
    let joinedAt: Date
    let isAdmin: Bool
    let isSuperAdminAccess: Bool

    init(isActive: Bool, joinedAt: Date, isAdmin: Bool, isSuperAdminAccess: Bool = false) {
        self.isActive = isActive
        self.joinedAt = joinedAt
        self.isAdmin = isAdmin
        self.isSuperAdminAccess = isSuperAdminAccess
    }

    init?(dictionary: [String: Any]) {
        guard let isActive = dictionary["isActive"] as? Bool,
              let joinedAtStr = dictionary["joinedAt"] as? String,
              let joinedAt = ISO8601DateFormatter().date(from: joinedAtStr),
              let isAdmin = dictionary["isAdmin"] as? Bool else { return nil }
        self.isActive = isActive
        self.joinedAt = joinedAt
        self.isAdmin = isAdmin
        self.isSuperAdminAccess = dictionary["isSuperAdminAccess"] as? Bool ?? false
    }

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "isActive": isActive,
            "joinedAt": ISO8601DateFormatter().string(from: joinedAt),
            "isAdmin": isAdmin
        ]
        if isSuperAdminAccess {
            dict["isSuperAdminAccess"] = isSuperAdminAccess
        }
        return dict
    }
}

struct RoomSettings: Codable, Equatable {
    let treatmentFoodTimerEnabled: Bool
    let remindersEnabled: [Category: Bool]
    let reminderTimes: [Category: Date]

    init(treatmentFoodTimerEnabled: Bool, remindersEnabled: [Category: Bool] = [:], reminderTimes: [Category: Date] = [:]) {
        self.treatmentFoodTimerEnabled = treatmentFoodTimerEnabled
        self.remindersEnabled = remindersEnabled
        self.reminderTimes = reminderTimes
    }

    init?(dictionary: [String: Any]) {
        self.treatmentFoodTimerEnabled = dictionary["treatmentFoodTimerEnabled"] as? Bool ?? false
        
        if let remindersEnabledDict = dictionary["remindersEnabled"] as? [String: Bool] {
            self.remindersEnabled = remindersEnabledDict.reduce(into: [Category: Bool]()) { result, pair in
                if let category = Category(rawValue: pair.key) {
                    result[category] = pair.value
                }
            }
        } else {
            self.remindersEnabled = [:]
        }

        if let reminderTimesDict = dictionary["reminderTimes"] as? [String: String] {
            self.reminderTimes = reminderTimesDict.reduce(into: [Category: Date]()) { result, pair in
                if let category = Category(rawValue: pair.key),
                   let date = ISO8601DateFormatter().date(from: pair.value) {
                    result[category] = date
                }
            }
        } else {
            self.reminderTimes = [:]
        }
    }

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "treatmentFoodTimerEnabled": treatmentFoodTimerEnabled
        ]
        if !remindersEnabled.isEmpty {
            let stringKeyedReminders = Dictionary(uniqueKeysWithValues: remindersEnabled.map { (key, value) in
                (key.rawValue, value)
            })
            dict["remindersEnabled"] = stringKeyedReminders
        }
        if !reminderTimes.isEmpty {
            let stringKeyedTimes = Dictionary(uniqueKeysWithValues: reminderTimes.map { (key, value) in
                (key.rawValue, ISO8601DateFormatter().string(from: value))
            })
            dict["reminderTimes"] = stringKeyedTimes
        }
        return dict
    }

    enum CodingKeys: String, CodingKey {
        case treatmentFoodTimerEnabled, remindersEnabled, reminderTimes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        treatmentFoodTimerEnabled = try container.decodeIfPresent(Bool.self, forKey: .treatmentFoodTimerEnabled) ?? false
        
        if let remindersEnabledDict = try container.decodeIfPresent([String: Bool].self, forKey: .remindersEnabled) {
            remindersEnabled = remindersEnabledDict.reduce(into: [Category: Bool]()) { result, pair in
                if let category = Category(rawValue: pair.key) {
                    result[category] = pair.value
                }
            }
        } else {
            remindersEnabled = [:]
        }

        if let reminderTimesDict = try container.decodeIfPresent([String: String].self, forKey: .reminderTimes) {
            reminderTimes = reminderTimesDict.reduce(into: [Category: Date]()) { result, pair in
                if let category = Category(rawValue: pair.key),
                   let date = ISO8601DateFormatter().date(from: pair.value) {
                    result[category] = date
                }
            }
        } else {
            reminderTimes = [:]
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(treatmentFoodTimerEnabled, forKey: .treatmentFoodTimerEnabled)
        
        let stringKeyedReminders = Dictionary(uniqueKeysWithValues: remindersEnabled.map { (key, value) in
            (key.rawValue, value)
        })
        try container.encode(stringKeyedReminders, forKey: .remindersEnabled)
        
        let stringKeyedTimes = Dictionary(uniqueKeysWithValues: reminderTimes.map { (key, value) in
            (key.rawValue, ISO8601DateFormatter().string(from: value))
        })
        try container.encode(stringKeyedTimes, forKey: .reminderTimes)
    }
}
struct ReminderSettings: Codable, Equatable {
    let enabled: Bool
    let time: Date

    init(enabled: Bool, time: Date) {
        self.enabled = enabled
        self.time = time
    }

    init?(dictionary: [String: Any]) {
        guard let enabled = dictionary["enabled"] as? Bool,
              let timeStr = dictionary["time"] as? String,
              let time = ISO8601DateFormatter().date(from: timeStr) else { return nil }
        self.enabled = enabled
        self.time = time
    }

    func toDictionary() -> [String: Any] {
        return [
            "enabled": enabled,
            "time": ISO8601DateFormatter().string(from: time)
        ]
    }
}
enum Category: String, CaseIterable {
    case medicine = "Medicine"
    case maintenance = "Maintenance"
    case treatment = "Treatment"
    case recommended = "Recommended"
}

enum ScheduleType: String, CaseIterable, Codable {
    case everyday = "Everyday"
    case everyOtherDay = "Every Other Day"
    case custom = "Custom"
}

// GroupedItem for combining items within a category
struct GroupedItem: Identifiable, Codable {
    let id: UUID
    let name: String
    let category: Category
    let itemIds: [UUID] // IDs of Items in this group
    
    init(id: UUID = UUID(), name: String, category: Category, itemIds: [UUID]) {
        self.id = id
        self.name = name
        self.category = category
        self.itemIds = itemIds
    }
    
    init?(dictionary: [String: Any]) {
        guard let idStr = dictionary["id"] as? String, let id = UUID(uuidString: idStr),
              let name = dictionary["name"] as? String,
              let categoryStr = dictionary["category"] as? String,
              let category = Category(rawValue: categoryStr),
              let itemIdsArray = dictionary["itemIds"] as? [String] else { return nil }
        self.id = id
        self.name = name
        self.category = category
        self.itemIds = itemIdsArray.compactMap { UUID(uuidString: $0) }
    }
    
    func toDictionary() -> [String: Any] {
        [
            "id": id.uuidString,
            "name": name,
            "category": category.rawValue,
            "itemIds": itemIds.map { $0.uuidString }
        ]
    }
    
    enum CodingKeys: String, CodingKey {
        case id, name, category, itemIds
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        let categoryString = try container.decode(String.self, forKey: .category)
        guard let decodedCategory = Category(rawValue: categoryString) else {
            throw DecodingError.dataCorruptedError(forKey: .category, in: container, debugDescription: "Invalid category value")
        }
        category = decodedCategory
        itemIds = try container.decode([UUID].self, forKey: .itemIds)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(category.rawValue, forKey: .category)
        try container.encode(itemIds, forKey: .itemIds)
    }
}

struct Fraction: Identifiable, Codable, Hashable { // Add Hashable conformance
    let id = UUID()
    let numerator: Int
    let denominator: Int
    
    var decimalValue: Double {
        Double(numerator) / Double(denominator)
    }
    
    var displayString: String {
        "\(numerator)/\(denominator)"
    }
    
    static let commonFractions: [Fraction] = [
        Fraction(numerator: 1, denominator: 8),  // 0.125
        Fraction(numerator: 1, denominator: 4),  // 0.25
        Fraction(numerator: 1, denominator: 3),  // ~0.333
        Fraction(numerator: 1, denominator: 2),  // 0.5
        Fraction(numerator: 2, denominator: 3),  // ~0.666
        Fraction(numerator: 3, denominator: 4),  // 0.75
    ]
    
    static func fractionForDecimal(_ decimal: Double, tolerance: Double = 0.01) -> Fraction? {
        commonFractions.first { abs($0.decimalValue - decimal) < tolerance }
    }
    
    // Hashable conformance
    static func ==(lhs: Fraction, rhs: Fraction) -> Bool {
        lhs.numerator == rhs.numerator && lhs.denominator == rhs.denominator
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(numerator)
        hasher.combine(denominator)
    }
}

// Helper extension to transform dictionary keys
extension Dictionary {
    func mapKeys<T>(transform: (Key) -> T) -> [T: Value] {
        return reduce(into: [T: Value]()) { result, pair in
            result[transform(pair.key)] = pair.value
        }
    }
}

struct TreatmentTimer: Codable, Equatable {
    let id: String
    let isActive: Bool
    let endTime: Date
    let associatedItemIds: [UUID]?
    let notificationIds: [String]?
    let roomName: String? // Add this line
    
    init(id: String = UUID().uuidString,
         isActive: Bool = true,
         endTime: Date,
         associatedItemIds: [UUID]? = nil,
         notificationIds: [String]? = nil,
         roomName: String? = nil) { // Add roomName parameter
        self.id = id
        self.isActive = isActive
        self.endTime = endTime
        self.associatedItemIds = associatedItemIds
        self.notificationIds = notificationIds
        self.roomName = roomName // Add this line
    }
    
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "isActive": isActive,
            "endTime": ISO8601DateFormatter().string(from: endTime)
        ]
        
        if let associatedItemIds = associatedItemIds {
            dict["associatedItemIds"] = associatedItemIds.map { $0.uuidString }
        }
        
        if let notificationIds = notificationIds {
            dict["notificationIds"] = notificationIds
        }
        
        if let roomName = roomName {
            dict["roomName"] = roomName
        }
        
        return dict
    }
    
    static func fromDictionary(_ dict: [String: Any]) -> TreatmentTimer? {
        guard let id = dict["id"] as? String,
              let isActive = dict["isActive"] as? Bool,
              let endTimeStr = dict["endTime"] as? String,
              let endTime = ISO8601DateFormatter().date(from: endTimeStr) else {
            return nil
        }
        
        var associatedItemIds: [UUID]? = nil
        if let itemIdStrings = dict["associatedItemIds"] as? [String] {
            associatedItemIds = itemIdStrings.compactMap { UUID(uuidString: $0) }
        }
        
        var notificationIds: [String]? = nil
        if let ids = dict["notificationIds"] as? [String] {
            notificationIds = ids
        }
        
        let roomName = dict["roomName"] as? String
        
        return TreatmentTimer(
            id: id,
            isActive: isActive,
            endTime: endTime,
            associatedItemIds: associatedItemIds,
            notificationIds: notificationIds,
            roomName: roomName
        )
    }
}
enum SymptomType: String, Codable, CaseIterable, Identifiable {
    case hives = "Hives"
    case itching = "Itching"
    case redness = "Redness"
    case coughing = "Coughing"
    case vomiting = "Vomiting"
    case anaphylaxis = "Anaphylaxis"
    case other = "Other"
    
    var id: String { self.rawValue }
}

struct Reaction: Identifiable, Codable {
    let id: UUID
    let date: Date
    let itemId: UUID?
    let symptoms: [SymptomType]
    let otherSymptom: String?
    let description: String
    let userId: UUID
    
    init(id: UUID = UUID(), date: Date, itemId: UUID? = nil, symptoms: [SymptomType], otherSymptom: String? = nil, description: String, userId: UUID) {
        self.id = id
        self.date = date
        self.itemId = itemId
        self.symptoms = symptoms
        self.otherSymptom = otherSymptom
        self.description = description
        self.userId = userId
    }
    
    init?(dictionary: [String: Any]) {
        guard let idStr = dictionary["id"] as? String, let id = UUID(uuidString: idStr),
              let dateStr = dictionary["date"] as? String,
              let date = ISO8601DateFormatter().date(from: dateStr),
              let symptomsArr = dictionary["symptoms"] as? [String],
              let description = dictionary["description"] as? String,
              let userIdStr = dictionary["userId"] as? String,
              let userId = UUID(uuidString: userIdStr) else { return nil }
        
        self.id = id
        self.date = date
        self.description = description
        self.userId = userId
        
        if let itemIdStr = dictionary["itemId"] as? String {
            self.itemId = UUID(uuidString: itemIdStr)
        } else {
            self.itemId = nil
        }
        
        self.symptoms = symptomsArr.compactMap { SymptomType(rawValue: $0) }
        self.otherSymptom = dictionary["otherSymptom"] as? String
    }
    
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id.uuidString,
            "date": ISO8601DateFormatter().string(from: date),
            "symptoms": symptoms.map { $0.rawValue },
            "description": description,
            "userId": userId.uuidString
        ]
        
        if let itemId = itemId {
            dict["itemId"] = itemId.uuidString
        }
        
        if let otherSymptom = otherSymptom {
            dict["otherSymptom"] = otherSymptom
        }
        
        return dict
    }
}
struct TransferRequest: Identifiable, Codable {
    let id: UUID
    let initiatorUserId: UUID // Was fromUserId
    let initiatorUserName: String // Was fromUserName
    let recipientUserId: UUID // Was toUserId
    let newOwnerId: UUID // New field
    let roomId: String
    let roomName: String
    let requestDate: Date
    let expiresAt: Date
    var status: TransferStatus
    
    enum TransferStatus: String, Codable, CaseIterable {
        case pending = "pending"
        case accepted = "accepted"
        case acceptedPendingSubscription = "accepted_pending_subscription"
        case declined = "declined"
        case expired = "expired"
        case cancelled = "cancelled"
    }
    
    init(id: UUID = UUID(), initiatorUserId: UUID, initiatorUserName: String, recipientUserId: UUID, newOwnerId: UUID, roomId: String, roomName: String, status: TransferStatus = .pending) {
        self.id = id
        self.initiatorUserId = initiatorUserId
        self.initiatorUserName = initiatorUserName
        self.recipientUserId = recipientUserId
        self.newOwnerId = newOwnerId
        self.roomId = roomId
        self.roomName = roomName
        self.requestDate = Date()
        self.expiresAt = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        self.status = status
    }
    
    init?(dictionary: [String: Any]) {
        guard let idStr = dictionary["id"] as? String, let id = UUID(uuidString: idStr),
              let initiatorUserIdStr = dictionary["initiatorUserId"] as? String, let initiatorUserId = UUID(uuidString: initiatorUserIdStr),
              let initiatorUserName = dictionary["initiatorUserName"] as? String,
              let recipientUserIdStr = dictionary["recipientUserId"] as? String, let recipientUserId = UUID(uuidString: recipientUserIdStr),
              let newOwnerIdStr = dictionary["newOwnerId"] as? String, let newOwnerId = UUID(uuidString: newOwnerIdStr),
              let roomId = dictionary["roomId"] as? String,
              let roomName = dictionary["roomName"] as? String,
              let requestDateStr = dictionary["requestDate"] as? String,
              let requestDate = ISO8601DateFormatter().date(from: requestDateStr),
              let expiresAtStr = dictionary["expiresAt"] as? String,
              let expiresAt = ISO8601DateFormatter().date(from: expiresAtStr),
              let statusStr = dictionary["status"] as? String,
              let status = TransferStatus(rawValue: statusStr) else { return nil }
        
        self.id = id
        self.initiatorUserId = initiatorUserId
        self.initiatorUserName = initiatorUserName
        self.recipientUserId = recipientUserId
        self.newOwnerId = newOwnerId
        self.roomId = roomId
        self.roomName = roomName
        self.requestDate = requestDate
        self.expiresAt = expiresAt
        self.status = status
    }
    
    func toDictionary() -> [String: Any] {
        [
            "id": id.uuidString,
            "initiatorUserId": initiatorUserId.uuidString,
            "initiatorUserName": initiatorUserName,
            "recipientUserId": recipientUserId.uuidString,
            "newOwnerId": newOwnerId.uuidString,
            "roomId": roomId,
            "roomName": roomName,
            "requestDate": ISO8601DateFormatter().string(from: requestDate),
            "expiresAt": ISO8601DateFormatter().string(from: expiresAt),
            "status": status.rawValue
        ]
    }
    
    var isExpired: Bool {
        return Date() > expiresAt
    }
    
    var canBeAccepted: Bool {
        return status == .pending && !isExpired
    }
    
    var canBeCancelled: Bool {
        return status == .pending && !isExpired
    }
}
// Treatment Timer Override Settings
struct TreatmentTimerOverride: Codable, Equatable {
    let enabled: Bool
    let durationSeconds: Int
    
    init(enabled: Bool = false, durationSeconds: Int = 900) {
        self.enabled = enabled
        self.durationSeconds = max(durationSeconds, 1) // Ensure positive duration
    }
    
    init?(dictionary: [String: Any]) {
        guard let enabled = dictionary["enabled"] as? Bool,
              let durationSeconds = dictionary["durationSeconds"] as? Int else {
            return nil
        }
        self.enabled = enabled
        self.durationSeconds = max(durationSeconds, 1)
    }
    
    func toDictionary() -> [String: Any] {
        return [
            "enabled": enabled,
            "durationSeconds": durationSeconds
        ]
    }
    
    static func == (lhs: TreatmentTimerOverride, rhs: TreatmentTimerOverride) -> Bool {
        return lhs.enabled == rhs.enabled && lhs.durationSeconds == rhs.durationSeconds
    }
}
// Demo Room Code for super admin multi-use invitations
struct DemoRoomCode: Codable, Equatable {
    let roomId: String
    let code: String
    let createdBy: UUID
    let createdAt: Date
    let isActive: Bool
    let roomName: String
    let usageCount: Int
    
    init(roomId: String, code: String, createdBy: UUID, roomName: String, isActive: Bool = true, usageCount: Int = 0) {
        self.roomId = roomId
        self.code = code
        self.createdBy = createdBy
        self.createdAt = Date()
        self.isActive = isActive
        self.roomName = roomName
        self.usageCount = usageCount
    }
    
    init?(dictionary: [String: Any]) {
        guard let roomId = dictionary["roomId"] as? String,
              let code = dictionary["code"] as? String,
              let createdByStr = dictionary["createdBy"] as? String,
              let createdBy = UUID(uuidString: createdByStr),
              let createdAtStr = dictionary["createdAt"] as? String,
              let createdAt = ISO8601DateFormatter().date(from: createdAtStr),
              let isActive = dictionary["isActive"] as? Bool,
              let roomName = dictionary["roomName"] as? String,
              let usageCount = dictionary["usageCount"] as? Int else { return nil }
        
        self.roomId = roomId
        self.code = code
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.isActive = isActive
        self.roomName = roomName
        self.usageCount = usageCount
    }
    
    func toDictionary() -> [String: Any] {
        return [
            "roomId": roomId,
            "code": code,
            "createdBy": createdBy.uuidString,
            "createdAt": ISO8601DateFormatter().string(from: createdAt),
            "isActive": isActive,
            "roomName": roomName,
            "usageCount": usageCount
        ]
    }
}
