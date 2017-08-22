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
    
    private let notificationCenter: DistributedNotificationCenter
    private let applicationGroup: String
    private let directoryName: String
    private let fileManager: FileManager
    
    public typealias Listener = (Any) -> Void
    
    private var listeners: [String: [Listener]] = [:]
    
    private let loggingEnabled: Bool
 
    public init(applicationGroup: String, directoryName: String = "wormhole", notificationCenter: DistributedNotificationCenter = DistributedNotificationCenter.forType(DistributedNotificationCenter.CenterType.localNotificationCenterType), fileManager: FileManager = FileManager.default, loggingEnabled: Bool = false) {
        precondition(directoryName.characters.count > 0, "directory name cannot be empty")
        
        self.notificationCenter = notificationCenter
        self.applicationGroup = applicationGroup
        self.directoryName = directoryName
        self.fileManager = fileManager
        
        self.loggingEnabled = loggingEnabled
    }
    
    // MARK: - ping
    
    public func sendPing(identifier: String, timeout: TimeInterval = 2.0, pong: @escaping (_ success: Bool) -> ()) {
        var observer: Any?
        
        observer = notificationCenter.addObserver(forName: NSNotification.Name(rawValue: "Pong\(identifier)"), object: nil, queue: OperationQueue.main) { [notificationCenter] notification in
            // success
            pong(true)
            notificationCenter.removeObserver(observer!)
            observer = nil
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [notificationCenter] in
            if let observer: Any = observer {
                // no pong yet, remove observer
                notificationCenter.removeObserver(observer)
                pong(false)
            }
        }
        
        notificationCenter.postNotificationName(NSNotification.Name(rawValue: "Ping\(identifier)"), object: nil, userInfo: nil, deliverImmediately: true)
    }
    
    public func replyToPings(matching identifier: String) {
        notificationCenter.addObserver(self,
            selector: #selector(Wormhole.didReceivePing(_:)),
            name: Notification.Name("Ping\(identifier)"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
    }
    
    @objc func didReceivePing(_ notification: Notification) {
        let notificationName = notification.name.rawValue
        let identifierStartIndex = notificationName.characters.index(notificationName.startIndex, offsetBy: "Ping".characters.count)
        let identifier = notificationName.substring(from: identifierStartIndex)

        let pongNotificationname = Notification.Name("Pong\(identifier)")
        notificationCenter.postNotificationName(pongNotificationname, object: nil, userInfo: nil, deliverImmediately: true)
    }
    
    // MARK: - listening
    
    public func listenForMessages(matching identifier: String, listener: @escaping Listener) {
        if listeners[identifier] == nil {
            listeners[identifier] = [listener]
            notificationCenter.addObserver(self,
                selector: #selector(Wormhole.didReceive(_:)),
                name: Notification.Name(identifier),
                object: nil,
                suspensionBehavior: .deliverImmediately
            )
        } else {
            listeners[identifier]?.append(listener)
        }
    }
    
    public func stopListeningForMessage(matching identifier: String) {
        notificationCenter.removeObserver(self, name: Notification.Name(identifier), object: nil)
        listeners.removeValue(forKey: identifier)
    }
    
    // MARK: - message passing
    
    public func payload(fromMessageMatching identifier: String) -> Any? {
        precondition(identifier.characters.count > 0, "identifier must not be empty")
        
        let fileURL = self.fileURL(forIdentifier: identifier)
        
        return (try? Data(contentsOf: fileURL))
            .flatMap(NSKeyedUnarchiver.unarchiveObject(with:))
    }
    
    public func sendMessage(identifier: String, payload: Any) {
        precondition(identifier.characters.count > 0, "identifier must not be empty")
        
        let data = NSKeyedArchiver.archivedData(withRootObject: payload)
        let fileURL = self.fileURL(forIdentifier: identifier)
        
        if (try? data.write(to: fileURL, options: [.atomic])) != nil {
            notificationCenter.post(name: Notification.Name(identifier), object: nil, userInfo: nil)
        } else {
            log("couldn't write payload to disk")
        }
    }
    
    // MARK: - private
    
    private var messagePassingDirectoryURL: URL {
        let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: applicationGroup)!
        let directoryURL = containerURL.appendingPathComponent(directoryName)
        
        do {
            try fileManager.createDirectory(at: directoryURL,
                withIntermediateDirectories: true,
                attributes: nil)
        } catch _ {
        }
        
        return directoryURL
    }
    
    private func fileURL(forIdentifier identifier: String) -> URL {
        precondition(identifier.characters.count > 0, "identifier must not be empty")
        
        return messagePassingDirectoryURL.appendingPathComponent("\(identifier).archive")
    }
    
    // MARK: - notification
    
    @objc func didReceive(_ notification: Notification) {
        if let object: Any = payload(fromMessageMatching: notification.name.rawValue) {
            log("received notification \(notification.name)")
            for listener in listeners[notification.name.rawValue] ?? [] {
                listener(object)
            }
        } else {
            log("received a notification, but couldn't get the payload")
        }
    }
    
    // MARK: - logging
    
    private func log(_ message: @autoclosure (Void) -> String) {
        if loggingEnabled {
            NSLog(message())
        }
    }
}
