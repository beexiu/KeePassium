//
//  Group.swift
//  KeePassium
//
//  Created by Andrei Popleteev on 2018-03-01.
//  Copyright © 2018 Andrei Popleteev. All rights reserved.
//

import Foundation

public class Group: Eraseable {
    public static let defaultIconID = IconID.folder
    public static let defaultOpenIconID = IconID.folderOpen
    
    // "up" refs are weak, refs to children are strong
    public unowned let database: Database
    public weak var parent: Group?
    public var uuid: UUID
    public var iconID: IconID
    public var name: String
    public var notes: String
    public internal(set) var creationTime: Date
    public internal(set) var lastModificationTime: Date
    public internal(set) var lastAccessTime: Date
    public var expiryTime: Date
    public var canExpire: Bool
    /// Returns true if the group has expired.
    public var isExpired: Bool {
        return canExpire && Date() > expiryTime
    }
    /// True if the group is in Recycle Bin
    public var isDeleted: Bool
    
    private var isChildrenModified: Bool
    public var groups = [Group]()
    public var entries = [Entry]()
    
    public var isRoot: Bool { return database.root === self }

    /// Checks if a group name is reserved for internal use and cannot be assigned by the user.
    public func isNameReserved(name: String) -> Bool {
        return false
    }

    init(database: Database) {
        self.database = database
        parent = nil
        
        uuid = UUID.ZERO
        iconID = Group.defaultIconID
        name = ""
        notes = ""
        isChildrenModified = true
        canExpire = false
        isDeleted = false
        groups = []
        entries = []

        let now = Date()
        creationTime = now
        lastModificationTime = now
        lastAccessTime = now
        expiryTime = now
    }
    deinit {
        erase()
    }
    public func erase() {
        entries.removeAll() //erase()
        groups.removeAll() //erase()

        uuid = UUID.ZERO
        iconID = Group.defaultIconID
        name.erase()
        notes.erase()
        isChildrenModified = true
        canExpire = false
        isDeleted = false
        
        parent = nil
        // database = nil  -- database reference does not change on erase

        let now = Date()
        creationTime = now
        lastModificationTime = now
        lastAccessTime = now
        expiryTime = now
    }
    
    /// Creates a shallow copy of this group with the same properties, but no children items.
    /// Subclasses must override and return an instance of a version-appropriate Group subclass.
    public func clone() -> Group {
        fatalError("Pure virtual method")
    }
    
    /// Copies properties of this group to `target`. Complex properties are cloned.
    /// Does not affect children items, parent group or parent database.
    public func apply(to target: Group) {
        target.uuid = uuid
        target.iconID = iconID
        target.name = name
        target.notes = notes
        target.canExpire = canExpire
        target.isDeleted = isDeleted
        
        // parent - not changed
        // database - not changed
        
        target.creationTime = creationTime
        target.lastModificationTime = lastModificationTime
        target.lastAccessTime = lastAccessTime
        target.expiryTime = expiryTime
    }
    
    /// Returns the number of immediate children of this group
    public func count(includeGroups: Bool = true, includeEntries: Bool = true) {
        var result = 0
        if includeGroups {
            result += groups.count
        }
        if includeEntries {
            result += entries.count
        }
    }
    
    /// Removes the group from the parent group, if any; does NOT make a copy in Backup/Recycle Bin group.
    public func deleteWithoutBackup() {
        parent?.remove(group: self)
    }
    
    /// Moves the group and all of its children to Backup/Recycle Bin group.
    /// Exact behavior is DB version specific.
    /// Pure abstract method, must be overriden.
    /// - Returns: true if successful, false otherwise.
    public func moveToBackup() -> Bool {
        fatalError("Pure virtual method")
    }
    
    public func add(group: Group) {
        group.parent = self
        groups.append(group)
        isChildrenModified = true
    }
    
    public func remove(group: Group) {
        guard group.parent === self else {
            return
        }
        groups.remove(group)
        group.parent = nil
        isChildrenModified = true
    }
    
    public func add(entry: Entry) {
        entry.parent = self
        entries.append(entry)
        isChildrenModified = true
    }
    
    public func remove(entry: Entry) {
        guard entry.parent === self else {
            return
        }
        entries.remove(entry)
        entry.parent = nil
        isChildrenModified = true
    }

    /// Moves entry from its parent group to this one.
    public func moveEntry(entry: Entry) {
        // Ok, we need to add the entry to this group and remove it from the original one,
        // making sure that no updates are emitted while in intermediate state.

        let originalParentGroup: Group? = entry.parent
        entry.parent = self
        entries.append(entry)
        isChildrenModified = true
        originalParentGroup?.entries.remove(entry)
        originalParentGroup?.isChildrenModified = true
    }


    /// Finds (sub)group with the given UUID (searching the full tree).
    /// - Returns: the first subgroup with the given UUID, or nil if none found.
    public func findGroup(byUUID uuid: UUID) -> Group? {
        if self.uuid == uuid {
            return self
        }
        for group in groups {
            if let result = group.findGroup(byUUID: uuid) {
                return result
            }
        }
        return nil
    }

    /// Creates an entry in this group.
    /// Subclasses must override and return an instance of a version-appropriate Entry subclass.
    /// - Returns: created entry
    public func createEntry() -> Entry {
        fatalError("Pure virtual method")
    }
    
    /// Creates a group inside this group.
    /// Subclasses must override and return an instance of a version-appropriate Group subclass.
    /// - Returns: created group
    public func createGroup() -> Group {
        fatalError("Pure virtual method")
    }
    
    /// Updates last access timestamp to current time
    public func accessed() {
        lastAccessTime = Date.now
    }
    /// Updates modification timestamp to current time
    public func modified() {
        accessed()
        lastModificationTime = Date.now
    }

    /// Recursively iterates through all the children groups and entries of this group
    /// and adds them to the given lists. The group itself is excluded.
    public func collectAllChildren(groups: inout Array<Group>, entries: inout Array<Entry>) {
        for group in self.groups {
            groups.append(group)
            group.collectAllChildren(groups: &groups, entries: &entries)
        }
        entries.append(contentsOf: self.entries)
    }
    
    /// Finds entries which match the query, and adds them to the `result`.
    public func filterEntries(query: SearchQuery, result: inout Array<Entry>) {
        if self.isDeleted && !query.includeDeleted {
            return
        }
        
        if query.includeSubgroups {
            for group in groups {
                group.filterEntries(query: query, result: &result)
            }
        }
        
        for entry in entries {
            if entry.matches(query: query) {
                result.append(entry)
            }
        }
    }
}

extension Array where Element == Group {
    mutating func remove(_ group: Group) {
        if let index = index(where: {$0 === group}) {
            remove(at: index)
        }
    }
}

