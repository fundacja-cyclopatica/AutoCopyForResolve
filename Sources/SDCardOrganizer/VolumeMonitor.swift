import Foundation
import AppKit

/// Wykrywa montowanie i odmontowywanie nośników wymiennych (kart SD) i udostępnia
/// listę aktualnie zamontowanych kart.
public final class VolumeMonitor: ObservableObject {
    @Published public private(set) var removableVolumes: [Volume] = []

    private let workspace = NSWorkspace.shared
    private var observers: [NSObjectProtocol] = []

    public init() {
        refresh()
        let center = workspace.notificationCenter
        observers.append(center.addObserver(
            forName: NSWorkspace.didMountNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.refresh() })
        observers.append(center.addObserver(
            forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.refresh() })
        observers.append(center.addObserver(
            forName: NSWorkspace.didRenameVolumeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.refresh() })
    }

    deinit {
        observers.forEach { workspace.notificationCenter.removeObserver($0) }
    }

    /// Odświeża listę zamontowanych nośników wymiennych.
    public func refresh() {
        let keys: Set<URLResourceKey> = [
            .volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeIsRemovableKey
        ]
        let mountedURLs = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: Array(keys),
            options: [.skipHiddenVolumes]
        ) ?? []

        let volumes = mountedURLs.compactMap { url -> Volume? in
            guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
            // Uwzględniamy tylko nośniki wymienne (karty SD, dyski USB).
            guard values.volumeIsRemovable == true else { return nil }
            return Volume(
                url: url,
                name: values.volumeName ?? url.lastPathComponent,
                totalCapacity: values.volumeTotalCapacity,
                availableCapacity: values.volumeAvailableCapacity
            )
        }
        removableVolumes = volumes.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

/// Reprezentacja zamontowanego nośnika wymiennego.
public struct Volume: Identifiable, Equatable, Hashable {
    public let url: URL
    public let name: String
    public let totalCapacity: Int?
    public let availableCapacity: Int?

    public var id: String { url.path }

    public init(url: URL, name: String, totalCapacity: Int?, availableCapacity: Int?) {
        self.url = url
        self.name = name
        self.totalCapacity = totalCapacity
        self.availableCapacity = availableCapacity
    }
}
