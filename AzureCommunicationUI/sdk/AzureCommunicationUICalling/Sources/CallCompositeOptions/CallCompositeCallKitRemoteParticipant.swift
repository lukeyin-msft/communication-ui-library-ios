//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License.
//

import CallKit

/// CallKit data for caller(incoming)/callee(outgoing)
public struct CallCompositeCallKitRemoteParticipant {
    /// Display name of the remote participant
    private(set) var displayName: String

    /// CXHandle of the remote participant, for call history
    private(set) var handle: CXHandle

    public init(displayName: String,
                handle: CXHandle) {
        self.displayName = displayName
        self.handle = handle
    }
}
