//
// Wormhole.swift
// SwiftWormhole
//
// Created by Kay Butter on 27/05/15.
// Copyright (c) 2015 Kay Butter. All rights reserved.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

import Foundation

public class Wormhole {
    
    private let notificationCenter: NSDistributedNotificationCenter
    private let applicationGroup: String
    private let directoryName: String
    private let fileManager: NSFileManager
    
    public typealias Listener = AnyObject -> Void
    
    private var listeners: [String: [Listener]] = [:]
    
    private let loggingEnabled: Bool
 
    public init(applicationGroup: String, directoryName: String = "wormhole", notificationCenter: NSDistributedNotificationCenter = NSDistributedNotificationCenter.notificationCenterForType(NSLocalNotificationCenterType), fileManager: NSFileManager = NSFileManager.defaultManager(), loggingEnabled: Bool = false) {
        precondition(directoryName.characters.count > 0, "directory name cannot be empty")
        
        self.notificationCenter = notificationCenter
        self.applicationGroup = applicationGroup
        self.directoryName = directoryName
        self.fileManager = fileManager
        
        self.loggingEnabled = loggingEnabled
    }
    
    // MARK: - ping
    
    public func pingWithIdentifier(identifier: String, timeout: NSTimeInterval = 2.0, pong: (success: Bool) -> ()) {
        var observer: AnyObject?
        
        observer = notificationCenter.addObserverForName("Pong\(identifier)", object: nil, queue: NSOperationQueue.mainQueue()) { [notificationCenter] notification in
            // success
            pong(success: true)
            notificationCenter.removeObserver(observer!)
            observer = nil
        }
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, Int64(timeout * Double(NSEC_PER_SEC))), dispatch_get_main_queue()) { [notificationCenter] in
            if let observer: AnyObject = observer {
                // no pong yet, remove observer
                notificationCenter.removeObserver(observer)
                pong(success: false)
            }
        }
        
        notificationCenter.postNotificationName("Ping\(identifier)", object: nil, userInfo: nil, deliverImmediately: true)
    }
    
    public func replyToPingsWithIdentifier(identifier: String) {
        notificationCenter.addObserver(self,
            selector: "didReceivePingNotification:",
            name: "Ping\(identifier)",
            object: nil,
            suspensionBehavior: .DeliverImmediately
        )
    }
    
    dynamic func didReceivePingNotification(notification: NSNotification) {
        let notificationName = notification.name
        let identifierStartIndex = advance(notificationName.startIndex, "Ping".characters.count)
        let identifier = notificationName.substringFromIndex(identifierStartIndex)
        
        notificationCenter.postNotificationName("Pong\(identifier)", object: nil, userInfo: nil, deliverImmediately: true)
    }
    
    // MARK: - listening
    
    public func listenForMessagesWithIdentifier(identifier: String, listener: Listener) {
        if listeners[identifier] == nil {
            listeners[identifier] = [listener]
            notificationCenter.addObserver(self,
                selector: "didReceiveNotification:",
                name: identifier,
                object: nil,
                suspensionBehavior: .DeliverImmediately
            )
        } else {
            listeners[identifier]?.append(listener)
        }
    }
    
    public func stopListeningForMessageWithIdentifier(identifier: String) {
        notificationCenter.removeObserver(self, name: identifier, object: nil)
        listeners.removeValueForKey(identifier)
    }
    
    // MARK: - message passing
    
    public func payloadForIdentifier(identifier: String) -> AnyObject? {
        precondition(identifier.characters.count > 0, "identifier must not be empty")
        
        let fileURL = fileURLForIdentifier(identifier)
        
        return NSData(contentsOfURL: fileURL)
            .flatMap(NSKeyedUnarchiver.unarchiveObjectWithData)
    }
    
    public func sendMessageWithIdentifier(identifier: String, payload: AnyObject) {
        precondition(identifier.characters.count > 0, "identifier must not be empty")
        
        let data = NSKeyedArchiver.archivedDataWithRootObject(payload)
        let fileURL = fileURLForIdentifier(identifier)
        
        if data.writeToURL(fileURL, atomically: true) {
            notificationCenter.postNotificationName(identifier, object: nil, userInfo: nil)
        } else {
            log("couldn't write payload to disk")
        }
    }
    
    // MARK: - private
    
    private var messagePassingDirectoryURL: NSURL {
        let containerURL = fileManager.containerURLForSecurityApplicationGroupIdentifier(applicationGroup)!
        let directoryURL = containerURL.URLByAppendingPathComponent(directoryName)
        
        do {
            try fileManager.createDirectoryAtURL(directoryURL,
                withIntermediateDirectories: true,
                attributes: nil)
        } catch _ {
        }
        
        return directoryURL
    }
    
    private func fileURLForIdentifier(identifier: String) -> NSURL {
        precondition(identifier.characters.count > 0, "identifier must not be empty")
        
        return messagePassingDirectoryURL.URLByAppendingPathComponent("\(identifier).archive")
    }
    
    // MARK: - notification
    
    dynamic func didReceiveNotification(notification: NSNotification) {
        if let object: AnyObject = payloadForIdentifier(notification.name) {
            log("received notification \(notification.name)")
            for listener in listeners[notification.name] ?? [] {
                listener(object)
            }
        } else {
            log("received a notification, but couldn't get the payload")
        }
    }
    
    // MARK: - logging
    
    private func log(@autoclosure message: Void -> String) {
        if loggingEnabled {
            NSLog(message())
        }
    }
}
