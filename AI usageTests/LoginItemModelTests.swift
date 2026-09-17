import ServiceManagement
import Testing
@testable import AI_usage

@MainActor
struct LoginItemModelTests {
    @Test
    func initMapsEnabledStatus() {
        let service = MockLoginItemService()
        service.status = .enabled

        let model = LoginItemModel(service: service)

        #expect(model.isEnabled)
        #expect(!model.needsApproval)
    }

    @Test
    func enablingRegistersAndReflectsStatus() {
        let service = MockLoginItemService()
        let model = LoginItemModel(service: service)

        model.setEnabled(true)

        #expect(service.registerCalls == 1)
        #expect(service.unregisterCalls == 0)
        #expect(model.isEnabled)
        #expect(model.errorMessage == nil)
    }

    @Test
    func disablingUnregistersAndReflectsStatus() {
        let service = MockLoginItemService()
        service.status = .enabled
        let model = LoginItemModel(service: service)

        model.setEnabled(false)

        #expect(service.registerCalls == 0)
        #expect(service.unregisterCalls == 1)
        #expect(!model.isEnabled)
        #expect(model.errorMessage == nil)
    }

    @Test
    func registrationFailureSurfacesErrorAndKeepsDisabledStatus() {
        let service = MockLoginItemService()
        service.registerError = MockLoginItemError.registrationFailed
        let model = LoginItemModel(service: service)

        model.setEnabled(true)

        #expect(service.registerCalls == 1)
        #expect(model.errorMessage != nil)
        #expect(!model.isEnabled)
    }

    @Test
    func unregistrationFailureSurfacesErrorAndKeepsEnabledStatus() {
        let service = MockLoginItemService()
        service.status = .enabled
        service.unregisterError = MockLoginItemError.unregistrationFailed
        let model = LoginItemModel(service: service)

        model.setEnabled(false)

        #expect(service.unregisterCalls == 1)
        #expect(model.errorMessage != nil)
        #expect(model.isEnabled)
    }

    @Test
    func refreshReflectsExternalStatusChanges() {
        let service = MockLoginItemService()
        let model = LoginItemModel(service: service)

        service.status = .enabled
        model.refresh()
        #expect(model.isEnabled)

        service.status = .notRegistered
        model.refresh()
        #expect(!model.isEnabled)
    }

    @Test
    func requiresApprovalDisablesEnableAction() {
        let service = MockLoginItemService()
        service.status = .requiresApproval
        let model = LoginItemModel(service: service)

        model.setEnabled(true)

        #expect(model.needsApproval)
        #expect(!model.isEnabled)
        #expect(service.registerCalls == 0)
    }

    @Test
    func refreshClearsStaleError() {
        let service = MockLoginItemService()
        service.registerError = MockLoginItemError.registrationFailed
        let model = LoginItemModel(service: service)
        model.setEnabled(true)
        #expect(model.errorMessage != nil)

        model.refresh()

        #expect(model.errorMessage == nil)
    }

    @Test
    func settingCurrentValueDoesNothing() {
        let service = MockLoginItemService()
        let model = LoginItemModel(service: service)

        model.setEnabled(false)

        #expect(service.registerCalls == 0)
        #expect(service.unregisterCalls == 0)
    }
}

private enum MockLoginItemError: Error {
    case registrationFailed
    case unregistrationFailed
}

@MainActor
private final class MockLoginItemService: LoginItemService {
    var status: SMAppService.Status = .notRegistered
    var registerError: Error?
    var unregisterError: Error?
    private(set) var registerCalls = 0
    private(set) var unregisterCalls = 0

    func register() throws {
        registerCalls += 1
        if let registerError {
            throw registerError
        }
        status = .enabled
    }

    func unregister() throws {
        unregisterCalls += 1
        if let unregisterError {
            throw unregisterError
        }
        status = .notRegistered
    }
}
