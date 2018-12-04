//
//  Group2.swift
//  KeePassium
//
//  Created by Andrei Popleteev on 2018-03-08.
//  Copyright © 2018 Andrei Popleteev. All rights reserved.
//

import Foundation
//import AEXML

public class Group2: Group {
    public var isExpanded: Bool
    public var customIconUUID: UUID
    public var defaultAutoTypeSequence: String
    public var enableAutoType: Bool? // It can be True/False/null in XML.
    public var enableSearching: Bool? // Same here.
    public var lastTopVisibleEntryUUID: UUID
    public var usageCount: UInt32
    public var locationChangedTime: Date
    public var customData: CustomData2 // v4 only
    
    override init(database: Database) {
        isExpanded = true
        customIconUUID = UUID.ZERO
        defaultAutoTypeSequence = ""
        enableAutoType = nil
        enableSearching = nil
        lastTopVisibleEntryUUID = UUID.ZERO
        usageCount = 0
        locationChangedTime = Date.now
        customData = CustomData2()
        super.init(database: database)
    }
    deinit {
        erase()
    }
    
    override public func erase() {
        super.erase()
        isExpanded = true
        customIconUUID.erase()
        defaultAutoTypeSequence.erase()
        enableAutoType = nil
        enableSearching = nil
        lastTopVisibleEntryUUID.erase()
        usageCount = 0
        locationChangedTime = Date.now
        customData.erase()
    }
    
    /// Creates a shallow copy of this group with the same properties, but no children items.
    /// The clone belongs to the same DB, but has no parent group.
    override public func clone() -> Group {
        let copy = Group2(database: database)
        apply(to: copy)
        return copy
    }
    
    /// Copies properties of this group to `target`. Complex properties are cloned.
    /// Does not affect children items, parent group or parent database.
    func apply(to target: Group2) {
        super.apply(to: target)
        
        target.isExpanded = isExpanded
        target.customIconUUID = customIconUUID
        target.defaultAutoTypeSequence = defaultAutoTypeSequence
        target.enableAutoType = enableAutoType
        target.enableSearching = enableSearching
        target.lastTopVisibleEntryUUID = lastTopVisibleEntryUUID
        target.usageCount = usageCount
        target.locationChangedTime = locationChangedTime
        target.customData = customData.clone()
    }
    
    /// Creates an entry in this group.
    override public func createEntry() -> Entry {
        let newEntry = Entry2(database: database)
        newEntry.uuid = UUID()
        // inherit the recycled status
        newEntry.isDeleted = self.isDeleted
        
        // inherit the group's icon, if it was changed
        if iconID != Group.defaultIconID && iconID != Group.defaultOpenIconID {
            newEntry.iconID = self.iconID
        }
        
        self.add(entry: newEntry)
        return newEntry
    }
    
    /// Creates a subgroup in this group.
    override public func createGroup() -> Group {
        let newGroup = Group2(database: database)
        newGroup.uuid = UUID()
        // inherit the icon and recycled status
        newGroup.iconID = self.iconID
        newGroup.customIconUUID = self.customIconUUID
        newGroup.isDeleted = self.isDeleted
        
        self.add(group: newGroup)
        
        return newGroup
    }
    
    /// Updates lass access timestamp and changes usage counter.
    override public func accessed() {
        super.accessed()
        usageCount += 1
    }
    
    /// Moves the group's whole branch to Backup/Recycle Bin group.
    /// If Backup is not available (disabled in DB setting), removes the group permanently.
    /// - Returns: true if successful, false otherwise.
    override public func moveToBackup() -> Bool {
        let db = self.database as! Database2
        
        guard let parentGroup = self.parent else {
            Diag.warning("moveToBackup failed: no parent group")
            return false
        }
        
        var allGroupsRecursive: Array<Group> = [Group2]()
        var allEntriesRecursive: Array<Entry> = [Entry2]()
        collectAllChildren(groups: &allGroupsRecursive, entries: &allEntriesRecursive)
        
        if let backupGroup = db.getBackupGroup(createIfMissing: true) {
            parentGroup.remove(group: self)
            backupGroup.add(group: self)
            accessed()
            locationChangedTime = Date.now
            
            // Flag the group and all its siblings deleted (siblings' timestamps remain unchanged).
            self.isDeleted = true
            for group in allGroupsRecursive {
                group.isDeleted = true
            }
            for entry in allEntriesRecursive {
                entry.isDeleted = true
            }
        } else {
            // Backup group has been disabled for this DB.
            // So we delete the group and all its children permanently,
            // but mention them in the DeletedObjects list to facilitate synchronization.
            Diag.debug("Backup group disabled, removing the group permanently.")
            db.addDeletedObject(uuid: self.uuid)
            for group in allGroupsRecursive {
                db.addDeletedObject(uuid: group.uuid)
            }
            for entry in allEntriesRecursive {
                db.addDeletedObject(uuid: entry.uuid)
            }
            deleteWithoutBackup() // also detaches all children
        }
        allGroupsRecursive.removeAll() //erase()
        allEntriesRecursive.removeAll() //erase()
        Diag.debug("moveToBackup OK")
        return true
    }

    /// Loads group properties from the <Group> XML element
    /// - Throws: `Xml2.ParsingError`, `ProgressInterruption`
    func load(xml: AEXMLElement, streamCipher: StreamCipher) throws {
        assert(xml.name == Xml2.group)
        Diag.verbose("Loading XML: group")
        
        // Keep refs to parent group and database, as they will not be read from XML here
        let parent = self.parent
        erase()
        self.parent = parent
        
        let db2: Database2 = database as! Database2
        let meta: Meta2 = db2.meta
        
        for tag in xml.children {
            switch tag.name {
            case Xml2.uuid:
                self.uuid = UUID(base64Encoded: tag.value) ?? UUID.ZERO
                if uuid == meta.recycleBinGroupUUID && meta.isRecycleBinEnabled {
                    Diag.verbose("Is a backup group")
                    self.isDeleted = true // may also be set higher in call stack
                }
            case Xml2.name:
                self.name = tag.value ?? ""
            case Xml2.notes:
                self.notes = tag.value ?? ""
            case Xml2.iconID:
                if let iconID = IconID(tag.value) {
                    self.iconID = iconID
                } else {
                    self.iconID = isExpanded ? Group.defaultOpenIconID : Group.defaultIconID
                }
            case Xml2.customIconUUID:
                self.customIconUUID = UUID(base64Encoded: tag.value) ?? UUID.ZERO
            case Xml2.times:
                try loadTimes(xml: tag)
                Diag.verbose("Group times loaded OK")
            case Xml2.isExpanded:
                self.isExpanded = Bool(string: tag.value)
            case Xml2.defaultAutoTypeSequence:
                self.defaultAutoTypeSequence = tag.value ?? ""
            case Xml2.enableAutoType:
                self.enableAutoType = Bool(optString: tag.value) // value can be "True"/"False"/"null"
            case Xml2.enableSearching:
                self.enableSearching = Bool(optString: tag.value) // value can be "True"/"False"/"null"
            case Xml2.lastTopVisibleEntry:
                self.lastTopVisibleEntryUUID = UUID(base64Encoded: tag.value) ?? UUID.ZERO
            case Xml2.customData:
                assert(db2.header.formatVersion == .v4)
                try customData.load(xml: tag, streamCipher: streamCipher, xmlParentName: "Group")
                Diag.verbose("Custom data loaded OK")
            case Xml2.group:
                let subGroup = Group2(database: database)
                try subGroup.load(xml: tag, streamCipher: streamCipher) // throws ProgressInterruption
                self.add(group: subGroup)
                subGroup.isDeleted = self.isDeleted // propagate the deleted flag recursively
                Diag.verbose("Subgroup loaded OK")
            case Xml2.entry:
                let entry = Entry2(database: database)
                try entry.load(xml: tag, streamCipher: streamCipher) // throws ProgressInterruption
                self.add(entry: entry)
                entry.isDeleted = self.isDeleted // propagate the deleted flag recursively
                Diag.verbose("Entry loaded OK")
            default:
                Diag.error("Unexpected XML tag in Group: \(tag.name)")
                throw Xml2.ParsingError.unexpectedTag(actual: tag.name, expected: "Group/*")
            }
        }
    }
    
    
    /// Reads group timestammps from the <Times> element
    /// - Throws: Xml2.ParsingError
    func loadTimes(xml: AEXMLElement) throws {
        assert(xml.name == Xml2.times)
        Diag.verbose("Loading XML: group times")
        
        let db = database as! Database2
        for tag in xml.children {
            switch tag.name {
            case Xml2.lastModificationTime:
                guard let time = db.xmlStringToDate(tag.value) else {
                    Diag.error("Cannot parse Group/Times/LastModificationTime as Date")
                    throw Xml2.ParsingError.malformedValue(
                        tag: "Group/Times/LastModificationTime",
                        value: tag.value)
                }
                lastModificationTime = time
            case Xml2.creationTime:
                guard let time = db.xmlStringToDate(tag.value) else {
                    Diag.error("Cannot parse Group/Times/CreationTime as Date")
                    throw Xml2.ParsingError.malformedValue(
                        tag: "Group/Times/CreationTime",
                        value: tag.value)
                }
                creationTime = time
            case Xml2.lastAccessTime:
                guard let time = db.xmlStringToDate(tag.value) else {
                    Diag.error("Cannot parse Group/Times/LastAccessTime as Date")
                    throw Xml2.ParsingError.malformedValue(
                        tag: "Group/Times/LastAccessTime",
                        value: tag.value)
                }
                lastAccessTime = time
            case Xml2.expiryTime:
                guard let time = db.xmlStringToDate(tag.value) else {
                    Diag.error("Cannot parse Group/Times/ExpiryTime as Date")
                    throw Xml2.ParsingError.malformedValue(
                        tag: "Group/Times/ExpiryTime",
                        value: tag.value)
                }
                expiryTime = time
            case Xml2.expires:
                canExpire = Bool(string: tag.value)
            case Xml2.usageCount:
                usageCount = UInt32(tag.value) ?? 0
            case Xml2.locationChanged:
                guard let time = db.xmlStringToDate(tag.value) else {
                    Diag.error("Cannot parse Group/Times/LocationChanged as Date")
                    throw Xml2.ParsingError.malformedValue(
                        tag: "Group/Times/LocationChanged",
                        value: tag.value)
                }
                locationChangedTime = time
            default:
                Diag.error("Unexpected XML tag in Group/Times: \(tag.name)")
                throw Xml2.ParsingError.unexpectedTag(actual: tag.name, expected: "Group/Times/*")
            }
        }
    }
    
    /// Stores the group with all its entries, subgroups and their subentries to an XML element.
    /// - Throws: `ProgressInterruption`
    func toXml(streamCipher: StreamCipher) throws -> AEXMLElement {
        Diag.verbose("Generating XML: group")
        let xmlGroup = AEXMLElement(name: Xml2.group)
        xmlGroup.addChild(name: Xml2.uuid, value: uuid.base64EncodedString())
        xmlGroup.addChild(name: Xml2.name, value: name)
        xmlGroup.addChild(name: Xml2.notes, value: notes)
        xmlGroup.addChild(name: Xml2.iconID, value: String(iconID.rawValue))
        if customIconUUID != UUID.ZERO {
            xmlGroup.addChild(
                name: Xml2.customIconUUID,
                value: customIconUUID.base64EncodedString())
        }
        
        let db2 = database as! Database2
        // Times
        let xmlTimes = AEXMLElement(name: Xml2.times)
        xmlTimes.addChild(
            name: Xml2.creationTime,
            value: db2.xmlDateToString(creationTime))
        xmlTimes.addChild(
            name: Xml2.lastModificationTime,
            value: db2.xmlDateToString(lastModificationTime))
        xmlTimes.addChild(
            name: Xml2.lastAccessTime,
            value: db2.xmlDateToString(lastAccessTime))
        xmlTimes.addChild(
            name: Xml2.expiryTime,
            value: db2.xmlDateToString(expiryTime))
        xmlTimes.addChild(
            name: Xml2.expires,
            value: canExpire ? Xml2._true : Xml2._false)
        xmlTimes.addChild(
            name: Xml2.usageCount,
            value: String(usageCount))
        xmlTimes.addChild(
            name: Xml2.locationChanged,
            value: db2.xmlDateToString(locationChangedTime))
        xmlGroup.addChild(xmlTimes)
        xmlGroup.addChild(
            name: Xml2.isExpanded,
            value: isExpanded ? Xml2._true : Xml2._false)
        xmlGroup.addChild(
            name: Xml2.defaultAutoTypeSequence,
            value: defaultAutoTypeSequence)
        
        if enableAutoType == nil {
            xmlGroup.addChild(name: Xml2.enableAutoType, value: Xml2.null)
        } else {
            xmlGroup.addChild(
                name: Xml2.enableAutoType,
                value: enableAutoType! ? Xml2._true : Xml2._false)
        }
        
        if enableSearching == nil {
            xmlGroup.addChild(name: Xml2.enableSearching, value: Xml2.null)
        } else {
            xmlGroup.addChild(
                name: Xml2.enableSearching,
                value: enableSearching! ? Xml2._true : Xml2._false)
        }
        xmlGroup.addChild(
            name: Xml2.lastTopVisibleEntry,
            value: lastTopVisibleEntryUUID.base64EncodedString())

        if db2.header.formatVersion == .v4 && !customData.isEmpty{
            xmlGroup.addChild(customData.toXml())
        }
        
        // entries
        for entry in entries {
            let entry2 = entry as! Entry2
            xmlGroup.addChild(try entry2.toXml(streamCipher: streamCipher))
                // throws ProgressInterruption
        }

        // subgroups
        for group in groups {
            let group2 = group as! Group2
            let groupXML = try group2.toXml(streamCipher: streamCipher)
                // throws ProgressInterruption
            xmlGroup.addChild(groupXML)
        }
        return xmlGroup
    }
}