//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License.
//

import Combine
import Foundation

// swiftlint:disable file_length
protocol CallingMiddlewareHandling {
    @discardableResult
    func setupCall(state: AppState, dispatch: @escaping ActionDispatch) -> Task<Void, Never>
    @discardableResult
    func startCall(state: AppState, dispatch: @escaping ActionDispatch) -> Task<Void, Never>
    @discardableResult
    func endCall(state: AppState, dispatch: @escaping ActionDispatch) -> Task<Void, Never>
    @discardableResult
    func holdCall(state: AppState, dispatch: @escaping ActionDispatch) -> Task<Void, Never>
    @discardableResult
    func resumeCall(state: AppState, dispatch: @escaping ActionDispatch) -> Task<Void, Never>
    @discardableResult
    func enterBackground(state: AppState, dispatch: @escaping ActionDispatch) -> Task<Void, Never>
    @discardableResult
    func enterForeground(state: AppState, dispatch: @escaping ActionDispatch) -> Task<Void, Never>
    @discardableResult
    func willTerminate(state: AppState, dispatch: @escaping ActionDispatch) -> Task<Void, Never>
    @discardableResult
    func audioSessionInterrupted(state: AppState, dispatch: @escaping ActionDispatch) -> Task<Void, Never>
    @discardableResult
    func requestCameraPreviewOn(state: AppState, dispatch: @escaping ActionDispatch) -> Task<Void, Never>
    @discardableResult
    func requestCameraOn(state: AppState, dispatch: @escaping ActionDispatch) -> Task<Void, Never>
    @discardableResult
    func requestCameraOff(state: AppState, dispatch: @escaping ActionDispatch) -> Task<Void, Never>
    @discardableResult
    func requestCameraSwitch(state: AppState, dispatch: @escaping ActionDispatch) -> Task<Void, Never>
    @discardableResult
    func requestMicrophoneMute(state: AppState, dispatch: @escaping ActionDispatch) -> Task<Void, Never>
    @discardableResult
    func requestMicrophoneUnmute(state: AppState, dispatch: @escaping ActionDispatch) -> Task<Void, Never>
    @discardableResult
    func onCameraPermissionIsSet(state: AppState, dispatch: @escaping ActionDispatch) -> Task<Void, Never>
    @discardableResult
    func admitAllLobbyParticipants(state: AppState, dispatch: @escaping ActionDispatch) -> Task<Void, Never>
    @discardableResult
    func declineAllLobbyParticipants(state: AppState, dispatch: @escaping ActionDispatch) -> Task<Void, Never>
    @discardableResult
    func admitLobbyParticipant(state: AppState,
                               dispatch: @escaping ActionDispatch,
                               participantId: String) -> Task<Void, Never>
    @discardableResult
    func declineLobbyParticipant(state: AppState,
                                 dispatch: @escaping ActionDispatch,
                                 participantId: String) -> Task<Void, Never>
    @discardableResult
    func capabilitiesUpdated(state: AppState, dispatch: @escaping ActionDispatch) -> Task<Void, Never>

    @discardableResult
    func onNetworkQualityCallDiagnosticsUpdated(state: AppState,
                                                dispatch: @escaping ActionDispatch,
                                                diagnisticModel: NetworkQualityDiagnosticModel) -> Task<Void, Never>
    @discardableResult
    func onNetworkCallDiagnosticsUpdated(state: AppState,
                                         dispatch: @escaping ActionDispatch,
                                         diagnisticModel: NetworkDiagnosticModel) -> Task<Void, Never>
    @discardableResult
    func onMediaCallDiagnosticsUpdated(state: AppState,
                                       dispatch: @escaping ActionDispatch,
                                       diagnisticModel: MediaDiagnosticModel) -> Task<Void, Never>

    @discardableResult
    func dismissNotification(state: AppState,
                             dispatch: @escaping ActionDispatch) -> Task<Void, Never>

    @discardableResult
    func removeParticipant(state: AppState,
                           dispatch: @escaping ActionDispatch,
                           participantId: String) -> Task<Void, Never>
}

// swiftlint:disable type_body_length
class CallingMiddlewareHandler: CallingMiddlewareHandling {

    private let callingService: CallingServiceProtocol
    private let logger: Logger
    private let cancelBag = CancelBag()
    private let subscription = CancelBag()
    private let capabilitiesManager: CapabilitiesManager

    init(callingService: CallingServiceProtocol, logger: Logger, capabilitiesManager: CapabilitiesManager) {
        self.callingService = callingService
        self.logger = logger
        self.capabilitiesManager = capabilitiesManager
    }

    func setupCall(state: AppState, dispatch: @escaping ActionDispatch) -> Task<Void, Never> {
        Task {
            do {
                try await callingService.setupCall()
                if state.defaultUserState.cameraState == .on,
                   state.errorState.internalError == nil {
                    await requestCameraPreviewOn(state: state, dispatch: dispatch).value
                }

                if state.callingState.operationStatus == .skipSetupRequested {
                    dispatch(.callingAction(.callStartRequested))
                }
            } catch {
                handle(error: error, errorType: .callJoinFailed, dispatch: dispatch)
            }
        }
    }

    func startCall(state: AppState, dispatch: @escaping ActionDispatch) -> Task<Void, Never> {
        Task {
            do {
                try await callingService.startCall(
                    isCameraPreferred: state.localUserState.cameraState.operation == .on,
                    isAudioPreferred: state.localUserState.audioState.operation == .on
                )
                subscription(dispatch: dispatch)
            } catch {
                handle(error: error, errorType: .callJoinFailed, dispatch: dispatch)
            }
        }
    }

    func endCall(state: AppState, dispatch: @escaping ActionDispatch) -> Task<Void, Never> {
        Task {
            do {
                try await callingService.endCall()
                dispatch(.callingAction(.callEnded))
            } catch {
                handle(error: error, errorType: .callEndFailed, dispatch: dispatch)
                dispatch(.callingAction(.requestFailed))
            }
        }
    }

    func holdCall(state: AppState, dispatch: @escaping ActionDispatch) -> Task<Void, Never> {
        Task {
            guard state.callingState.status == .connected else {
                return
            }

            do {
                try await callingService.holdCall()
                await requestCameraPause(state: state, dispatch: dispatch).value
            } catch {
                handle(error: error, errorType: .callHoldFailed, dispatch: dispatch)
            }
        }
    }

    func resumeCall(state: AppState, dispatch: @escaping ActionDispatch) -> Task<Void, Never> {
        Task {
            guard state.callingState.status == .localHold else {
                return
            }

            do {
                try await callingService.resumeCall()
                if state.localUserState.cameraState.operation == .paused {
                    await requestCameraOn(state: state, dispatch: dispatch).value
                }
            } catch {
                handle(error: error, errorType: .callResumeFailed, dispatch: dispatch)
            }
        }
    }

    func enterBackground(state: AppState, dispatch: @escaping ActionDispatch) -> Task<Void, Never> {
        Task {
            await requestCameraPause(state: state, dispatch: dispatch).value
        }
    }

    func enterForeground(state: AppState, dispatch: @escaping ActionDispatch) -> Task<Void, Never> {
        Task {
            guard state.lifeCycleState.currentStatus == .background,
                  state.callingState.status == .connected,
                  state.localUserState.cameraState.operation == .paused else {
                return
            }
            await requestCameraOn(state: state, dispatch: dispatch).value
        }
    }

    func willTerminate(state: AppState, dispatch: @escaping ActionDispatch) -> Task<Void, Never> {
        Task {
            guard state.callingState.status == .connected else {
                return
            }
            dispatch(.callingAction(.callEndRequested))
        }
    }

    func requestCameraPreviewOn(state: AppState, dispatch: @escaping ActionDispatch) -> Task<Void, Never> {
        Task {
            if state.permissionState.cameraPermission == .notAsked {
                dispatch(.permissionAction(.cameraPermissionRequested))
            } else if state.permissionState.cameraPermission == .denied {
                dispatch(.localUserAction(.cameraOffTriggered))
            } else {
                do {
                    let identifier = try await callingService.requestCameraPreviewOn()
                    dispatch(.localUserAction(.cameraOnSucceeded(videoStreamIdentifier: identifier)))
                } catch {
                    dispatch(.localUserAction(.cameraOnFailed(error: error)))
                }
            }
        }
    }

    func requestCameraOn(state: AppState, dispatch: @escaping ActionDispatch) -> Task<Void, Never> {
        Task {
            if state.permissionState.cameraPermission == .notAsked {
                dispatch(.permissionAction(.cameraPermissionRequested))
            } else {
                do {
                    let streamId = try await callingService.startLocalVideoStream()
                    try await Task.sleep(nanoseconds: NSEC_PER_SEC)
                    dispatch(.localUserAction(.cameraOnSucceeded(videoStreamIdentifier: streamId)))
                } catch {
                    dispatch(.localUserAction(.cameraOnFailed(error: error)))
                }
            }
        }
    }

    func requestCameraOff(state: AppState, dispatch: @escaping ActionDispatch) -> Task<Void, Never> {
        Task {
            do {
                try await callingService.stopLocalVideoStream()
                dispatch(.localUserAction(.cameraOffSucceeded))
            } catch {
                dispatch(.localUserAction(.cameraOffFailed(error: error)))
            }
        }
    }

    func requestCameraPause(state: AppState, dispatch: @escaping ActionDispatch) -> Task<Void, Never> {
        Task {
            guard state.callingState.status == .connected,
                  state.localUserState.cameraState.operation == .on else {
                return
            }

            do {
                try await callingService.stopLocalVideoStream()
                dispatch(.localUserAction(.cameraPausedSucceeded))
            } catch {
                dispatch(.localUserAction(.cameraPausedFailed(error: error)))
            }
        }
    }

    func requestCameraSwitch(state: AppState, dispatch: @escaping ActionDispatch) -> Task<Void, Never> {
        Task {
            let currentCamera = state.localUserState.cameraState.device
            do {
                let device = try await callingService.switchCamera()
                try await Task.sleep(nanoseconds: NSEC_PER_SEC)
                dispatch(.localUserAction(.cameraSwitchSucceeded(cameraDevice: device)))
            } catch {
                dispatch(.localUserAction(.cameraSwitchFailed(previousCamera: currentCamera, error: error)))
            }
        }
    }

    func requestMicrophoneMute(state: AppState, dispatch: @escaping ActionDispatch) -> Task<Void, Never> {
        Task {
            do {
                try await callingService.muteLocalMic()
            } catch {
                dispatch(.localUserAction(.microphoneOffFailed(error: error)))
            }
        }
    }

    func requestMicrophoneUnmute(state: AppState, dispatch: @escaping ActionDispatch) -> Task<Void, Never> {
        Task {
            do {
                try await callingService.unmuteLocalMic()
            } catch {
                dispatch(.localUserAction(.microphoneOnFailed(error: error)))
            }
        }
    }

    func onCameraPermissionIsSet(state: AppState, dispatch: @escaping ActionDispatch) -> Task<Void, Never> {
        Task {
            guard state.permissionState.cameraPermission == .requesting else {
                return
            }

            switch state.localUserState.cameraState.transmission {
            case .local:
                if state.navigationState.status == .inCall {
                    dispatch(.localUserAction(.cameraOnTriggered))
                } else {
                    dispatch(.localUserAction(.cameraPreviewOnTriggered))
                }
            case .remote:
                dispatch(.localUserAction(.cameraOnTriggered))
            }
        }
    }

    func audioSessionInterrupted(state: AppState, dispatch: @escaping ActionDispatch) -> Task<Void, Never> {
        Task {
            guard state.callingState.status == .connected else {
                return
            }

            dispatch(.callingAction(.holdRequested))
        }
    }

    func admitAllLobbyParticipants(state: AppState, dispatch: @escaping ActionDispatch) -> Task<Void, Never> {
        Task {
            guard state.callingState.status == .connected else {
                return
            }

            do {
                try await callingService.admitAllLobbyParticipants()
            } catch {
                let errorCode = LobbyErrorCode.convertToLobbyErrorCode(error as NSError)
                dispatch(.remoteParticipantsAction(.lobbyError(errorCode: errorCode)))
            }
        }
    }

    func declineAllLobbyParticipants(state: AppState, dispatch: @escaping ActionDispatch) -> Task<Void, Never> {
        Task {
            guard state.callingState.status == .connected else {
                return
            }
            let participantIds = state.remoteParticipantsState.participantInfoList.filter { participant in
                participant.status == .inLobby
            }.map { participant in
                participant.userIdentifier
            }

            for participantId in participantIds {
                do {
                    try await callingService.declineLobbyParticipant(participantId)
                } catch {
                    let errorCode = LobbyErrorCode.convertToLobbyErrorCode(error as NSError)
                    dispatch(.remoteParticipantsAction(.lobbyError(errorCode: errorCode)))
                }
            }
        }
    }

    func admitLobbyParticipant(state: AppState,
                               dispatch: @escaping ActionDispatch,
                               participantId: String) -> Task<Void, Never> {
        Task {
            guard state.callingState.status == .connected else {
                return
            }

            do {
                try await callingService.admitLobbyParticipant(participantId)
            } catch {
                let errorCode = LobbyErrorCode.convertToLobbyErrorCode(error as NSError)
                dispatch(.remoteParticipantsAction(.lobbyError(errorCode: errorCode)))
            }
        }
    }

    func declineLobbyParticipant(state: AppState,
                                 dispatch: @escaping ActionDispatch,
                                 participantId: String) -> Task<Void, Never> {
        Task {
            guard state.callingState.status == .connected else {
                return
            }

            do {
                try await callingService.declineLobbyParticipant(participantId)
            } catch {
                let errorCode = LobbyErrorCode.convertToLobbyErrorCode(error as NSError)
                dispatch(.remoteParticipantsAction(.lobbyError(errorCode: errorCode)))
            }
        }
    }

    func capabilitiesUpdated(state: AppState, dispatch: @escaping ActionDispatch) -> Task<Void, Never> {
        Task {
            guard state.callingState.status != .disconnected else {
                return
            }

            do {
                let isInitialCapabilitySetting = state.localUserState.capabilities.isEmpty
                if !capabilitiesManager.hasCapability(capabilities: state.localUserState.capabilities,
                                                      capability: ParticipantCapabilityType.turnVideoOn) &&
                    state.localUserState.cameraState.operation != .off {
                    dispatch(.localUserAction(.cameraOffTriggered))
                } else {
                    if isInitialCapabilitySetting && state.callingState.operationStatus == .skipSetupRequested {
                        await requestCameraOn(state: state, dispatch: dispatch).value
                    }
                }

                if !capabilitiesManager.hasCapability(capabilities: state.localUserState.capabilities,
                                                      capability: ParticipantCapabilityType.unmuteMicrophone) &&
                    state.localUserState.audioState.operation != .off {
                    dispatch(.localUserAction(.microphoneOffTriggered))
                }
            }
        }
    }

    func onNetworkQualityCallDiagnosticsUpdated(state: AppState,
                                                dispatch: @escaping ActionDispatch,
                                                diagnisticModel: NetworkQualityDiagnosticModel) -> Task<Void, Never> {
        Task {
            if diagnisticModel.value == .bad || diagnisticModel.value == .poor {
                switch diagnisticModel.diagnostic {
                case .networkReceiveQuality:
                    dispatch(.toastNotificationAction(.showNotification(kind: .networkReceiveQuality)))
                case .networkReconnectionQuality:
                    dispatch(.toastNotificationAction(.showNotification(kind: .networkReconnectionQuality)))
                case .networkSendQuality:
                    dispatch(.toastNotificationAction(.showNotification(kind: .networkSendQuality)))
                }
            } else {
                dispatch(.toastNotificationAction(.dismissNotification))
            }
        }
    }

    func onNetworkCallDiagnosticsUpdated(state: AppState,
                                         dispatch: @escaping ActionDispatch,
                                         diagnisticModel: NetworkDiagnosticModel) -> Task<Void, Never> {
        Task {
            if diagnisticModel.value {
                switch diagnisticModel.diagnostic {
                case .networkRelaysUnreachable:
                    dispatch(.toastNotificationAction(.showNotification(kind: .networkRelaysUnreachable)))
                case .networkUnavailable:
                    dispatch(.toastNotificationAction(.showNotification(kind: .networkUnavailable)))
                }
            }
        }
    }

    func onMediaCallDiagnosticsUpdated(state: AppState,
                                       dispatch: @escaping ActionDispatch,
                                       diagnisticModel: MediaDiagnosticModel) -> Task<Void, Never> {
        Task {
            switch diagnisticModel.diagnostic {
            case .speakingWhileMicrophoneIsMuted:
                if diagnisticModel.value {
                    dispatch(.toastNotificationAction(.showNotification(kind: .speakingWhileMicrophoneIsMuted)))
                } else {
                    dispatch(.toastNotificationAction(.dismissNotification))
                }
            case .cameraStartFailed:
                if diagnisticModel.value {
                    dispatch(.toastNotificationAction(.showNotification(kind: .cameraStartFailed)))
                }
            case .cameraStartTimedOut:
                if diagnisticModel.value {
                    dispatch(.toastNotificationAction(.showNotification(kind: .cameraStartTimedOut)))
                }
            default:
                break
            }
        }
    }

    func dismissNotification(state: AppState, dispatch: @escaping ActionDispatch) -> Task<Void, Never> {
        Task {
            guard let toastState = state.toastNotificationState.status else {
                return
            }
            switch toastState {
            case ToastNotificationKind.networkUnavailable:
                dispatch(.callDiagnosticAction(.dismissNetwork(diagnostic: .networkUnavailable)))
            case .networkRelaysUnreachable:
                dispatch(.callDiagnosticAction(.dismissNetwork(diagnostic: .networkRelaysUnreachable)))
            case .networkReceiveQuality:
                dispatch(.callDiagnosticAction(.dismissNetworkQuality(diagnostic: .networkReceiveQuality)))
            case .networkReconnectionQuality:
                dispatch(.callDiagnosticAction(.dismissNetworkQuality(diagnostic: .networkReconnectionQuality)))
            case .networkSendQuality:
                dispatch(.callDiagnosticAction(.dismissNetworkQuality(diagnostic: .networkSendQuality)))
            case .speakingWhileMicrophoneIsMuted:
                dispatch(.callDiagnosticAction(.dismissMedia(diagnostic: .speakingWhileMicrophoneIsMuted)))
            case .cameraStartFailed:
                dispatch(.callDiagnosticAction(.dismissMedia(diagnostic: .cameraStartFailed)))
            case .cameraStartTimedOut:
                dispatch(.callDiagnosticAction(.dismissMedia(diagnostic: .cameraStartTimedOut)))
            case .someFeaturesLost, .someFeaturesGained:
                break
            }
        }
    }

    func removeParticipant(state: AppState,
                           dispatch: @escaping ActionDispatch,
                           participantId: String) -> Task<Void, Never> {
        Task {
            guard state.callingState.status == .connected else {
                return
            }

            do {
                try await callingService.removeParticipant(participantId)
            } catch {
                dispatch(.remoteParticipantsAction(.removeParticipantError))
            }
        }
    }
}

extension CallingMiddlewareHandler {
    private func subscription(dispatch: @escaping ActionDispatch) {
        logger.debug("Subscribe to calling service subjects")
        callingService.participantsInfoListSubject
            .throttle(for: 1.25, scheduler: DispatchQueue.main, latest: true)
            .sink { list in
                dispatch(.remoteParticipantsAction(.participantListUpdated(participants: list)))
            }.store(in: subscription)

        callingService.callInfoSubject
            .sink { [weak self] callInfoModel in
                guard let self = self else {
                    return
                }
                let internalError = callInfoModel.internalError
                let callingStatus = callInfoModel.status

                self.handle(callingStatus: callingStatus, dispatch: dispatch)
                self.logger.debug("Dispatch State Update: \(callingStatus)")

                if let internalError = internalError {
                    self.handleCallInfo(internalError: internalError,
                                        dispatch: dispatch) {
                        self.logger.debug("Subscription cancelled with Error Code: \(internalError)")
                        self.subscription.cancel()
                    }
                    // to fix the bug that resume call won't work without Internet
                    // we exit the UI library when we receive the wrong status .remoteHold
                } else if callingStatus == .disconnected {
                    self.logger.debug("Subscription cancel happy path")
                    dispatch(.compositeExitAction)
                    self.subscription.cancel()
                }

            }.store(in: subscription)

        callingService.isRecordingActiveSubject
            .removeDuplicates()
            .sink { isRecordingActive in
                dispatch(.callingAction(.recordingStateUpdated(isRecordingActive: isRecordingActive)))
            }.store(in: subscription)

        callingService.isTranscriptionActiveSubject
            .removeDuplicates()
            .sink { isTranscriptionActive in
                dispatch(.callingAction(.transcriptionStateUpdated(isTranscriptionActive: isTranscriptionActive)))
            }.store(in: subscription)

        callingService.isLocalUserMutedSubject
            .removeDuplicates()
            .sink { isLocalUserMuted in
                dispatch(.localUserAction(.microphoneMuteStateUpdated(isMuted: isLocalUserMuted)))
            }.store(in: subscription)

        callingService.callIdSubject
            .removeDuplicates()
            .sink { callId in
                dispatch(.callingAction(.callIdUpdated(callId: callId)))
            }.store(in: subscription)

        callingService.dominantSpeakersSubject
            .throttle(for: 0.5, scheduler: DispatchQueue.main, latest: true)
            .sink { speakers in
                dispatch(.remoteParticipantsAction(.dominantSpeakersUpdated(speakers: speakers)))
            }.store(in: subscription)

        callingService.participantRoleSubject
            .removeDuplicates()
            .sink { participantRole in
                dispatch(.localUserAction(.participantRoleChanged(participantRole: participantRole)))
            }.store(in: subscription)

        callingService.networkDiagnosticsSubject
            .removeDuplicates()
            .sink { networkDiagnostic in
                dispatch(.callDiagnosticAction(.network(diagnostic: networkDiagnostic)))
            }.store(in: subscription)

        callingService.networkQualityDiagnosticsSubject
            .removeDuplicates()
            .sink { networkQualityDiagnostic in
                dispatch(.callDiagnosticAction(.networkQuality(diagnostic: networkQualityDiagnostic)))
            }.store(in: subscription)

        callingService.mediaDiagnosticsSubject
            .removeDuplicates()
            .sink { mediaDiagnostic in
                dispatch(.callDiagnosticAction(.media(diagnostic: mediaDiagnostic)))
            }.store(in: subscription)

        subscibeCapabilitiesUpdate(dispatch: dispatch)
    }

    private func subscibeCapabilitiesUpdate(dispatch: @escaping ActionDispatch) {
        callingService.capabilitiesChangedSubject
            .removeDuplicates()
            .sink { _ in
                Task {
                    do {
                        let capabilities = try await self.callingService.getCapabilities()
                        dispatch(.localUserAction(.capabilitiesUpdated(capabilities: capabilities)))
                    } catch {
                        self.logger.error("Fetch capabilities Failed with error : \(error)")
                    }
                }
            }.store(in: subscription)
    }
}
// swiftlint:enable type_body_length
