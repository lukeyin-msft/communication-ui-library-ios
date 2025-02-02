//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License.
//

extension ControlBarViewModel {
    func dismissConfirmLeaveDrawerList() {
        self.isConfirmLeaveListDisplayed = false
    }

    func isMoreButtonDisabled() -> Bool {
        isBypassLoadingOverlay()
    }

    func isMicDisabled() -> Bool {
        audioState.operation == .pending || callingStatus == .localHold || isBypassLoadingOverlay()
    }

    func isAudioDeviceDisabled() -> Bool {
        callingStatus == .localHold || isBypassLoadingOverlay()
    }

    func isBypassLoadingOverlay() -> Bool {
        operationStatus == .skipSetupRequested && callingStatus != .connected &&
        callingStatus != .inLobby
    }
}
