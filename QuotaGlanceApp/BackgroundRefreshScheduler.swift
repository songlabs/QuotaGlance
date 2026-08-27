import BackgroundTasks
import Foundation

@MainActor
final class BackgroundRefreshScheduler {
    static let taskIdentifier = "com.songlabs.QuotaGlance.refresh"

    private weak var store: DashboardStore?
    private var isAppInBackground = false
    private var activeExecution: BackgroundRefreshExecution?

    init(store: DashboardStore) {
        self.store = store
        store.automaticRefreshConfigurationDidChange = { [weak self] in
            self?.automaticRefreshConfigurationDidChange()
        }
        _ = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.taskIdentifier,
            using: .main
        ) { [weak self] task in
            MainActor.assumeIsolated {
                guard let appRefreshTask = task as? BGAppRefreshTask else {
                    task.setTaskCompleted(success: false)
                    return
                }
                self?.handle(appRefreshTask)
            }
        }
    }

    func appEnteredForeground() {
        isAppInBackground = false
        if store?.effectiveRefreshInterval == .disabled {
            cancelPendingRefresh()
        }
    }

    func appEnteredBackground() {
        isAppInBackground = true
        scheduleNextRefresh()
    }

    private func automaticRefreshConfigurationDidChange() {
        guard store?.effectiveRefreshInterval != .disabled else {
            cancelPendingRefresh()
            return
        }
        if isAppInBackground {
            scheduleNextRefresh()
        }
    }

    private func scheduleNextRefresh(now: Date = Date()) {
        guard let earliestBeginDate = store?.effectiveRefreshInterval
            .earliestBackgroundBeginDate(from: now)
        else {
            cancelPendingRefresh()
            return
        }

        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskIdentifier)
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = earliestBeginDate
        try? BGTaskScheduler.shared.submit(request)
    }

    private func cancelPendingRefresh() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskIdentifier)
    }

    private func handle(_ task: BGAppRefreshTask) {
        isAppInBackground = true
        scheduleNextRefresh()

        activeExecution?.expire()
        let execution = BackgroundRefreshExecution(task: task, store: store)
        execution.onComplete = { [weak self, weak execution] in
            guard let self, self.activeExecution === execution else { return }
            self.activeExecution = nil
        }
        activeExecution = execution
        execution.start()
    }
}

@MainActor
private final class BackgroundRefreshExecution {
    let task: BGAppRefreshTask
    weak var store: DashboardStore?
    var onComplete: (() -> Void)?

    private var work: Task<Void, Never>?
    private var isCompleted = false

    init(task: BGAppRefreshTask, store: DashboardStore?) {
        self.task = task
        self.store = store
    }

    func start() {
        task.expirationHandler = { [weak self] in
            Task { @MainActor in
                self?.expire()
            }
        }
        work = Task { @MainActor [weak self] in
            guard let self else { return }
            guard let store = self.store else {
                self.complete(success: false)
                return
            }
            let succeeded = await store.performBackgroundAutomaticRefresh()
            self.complete(success: succeeded && !Task.isCancelled)
        }
    }

    func expire() {
        work?.cancel()
        complete(success: false)
    }

    private func complete(success: Bool) {
        guard !isCompleted else { return }
        isCompleted = true
        task.expirationHandler = nil
        task.setTaskCompleted(success: success)
        work = nil
        onComplete?()
    }
}
