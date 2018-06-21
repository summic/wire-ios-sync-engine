//
// Wire
// Copyright (C) 2018 Wire Swiss GmbH
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see http://www.gnu.org/licenses/.
//

import Foundation

private let log = ZMSLog(tag: "ConversationMessageDestructionTimeout")

public enum MessageDestructionTimerError: Error {
    case invalidOperation
    case accessDenied
    case noConversation
    case unknown
    
    init?(response: ZMTransportResponse) {
        switch (response.httpStatus, response.payloadLabel()) {
        case (403, "invalid-op"?): self = .invalidOperation
        case (403, "access-denied"): self = .accessDenied
        case (404, "no-conversation"): self = .noConversation
        case (400..<499, _): self = .unknown
        default: return nil
        }
    }
}

fileprivate extension ZMTransportResponse {
    var updateEvent: ZMUpdateEvent? {
        return payload.flatMap(papply(flip(ZMUpdateEvent.init), nil))
    }
}

extension ZMConversation {

    /// Changes the conversation message destruction timeout
    public func setMessageDestructionTimeout(
        _ timeout: MessageDestructionTimeoutValue,
        in userSession: ZMUserSession, _
        completion: @escaping (VoidResult) -> Void
        ) {

        let request = MessageDestructionTimeoutRequestFactory.set(timeout: Int(timeout.rawValue), for: self)
        request.add(ZMCompletionHandler(on: managedObjectContext!) { response in
            if response.httpStatus.isOne(of: 200, 204),  let event = response.updateEvent {
                // Process `conversation.message-timer-update` event
                userSession.syncManagedObjectContext.performGroupedBlock {
                    userSession.operationLoop.syncStrategy.processUpdateEvents([event], ignoreBuffer: true)
                }
                completion(.success)
            } else {
                let error = WirelessLinkError(response: response) ?? .unknown
                log.debug("Error updating message destruction timeout \(error): \(response)")
                completion(.failure(error))
            }
        })
        
        userSession.transportSession.enqueueOneTime(request)
    }
    
}

fileprivate struct MessageDestructionTimeoutRequestFactory {
    
    static func set(timeout: Int, for conversation: ZMConversation) -> ZMTransportRequest {
        guard let identifier = conversation.remoteIdentifier?.transportString() else { fatal("conversation inserted on backend") }
        let payload = ["message_timer": timeout]
        return .init(path: "/conversations/\(identifier)/message-timer", method: .methodPUT, payload: payload as ZMTransportData)
    }

}