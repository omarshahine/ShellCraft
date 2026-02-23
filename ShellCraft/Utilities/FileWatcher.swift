import Foundation

@Observable
final class FileWatcher {
    private var sources: [String: DispatchSourceFileSystemObject] = [:]
    private var fileDescriptors: [String: Int32] = [:]
    var onFileChanged: ((String) -> Void)?

    func watch(path: String) {
        let expandedPath = path.expandingTildeInPath
        guard fileDescriptors[expandedPath] == nil else { return }

        let fd = open(expandedPath, O_EVTONLY)
        guard fd >= 0 else { return }

        fileDescriptors[expandedPath] = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            self?.onFileChanged?(expandedPath)
        }

        source.setCancelHandler {
            close(fd)
        }

        sources[expandedPath] = source
        source.resume()
    }

    func stopWatching(path: String) {
        let expandedPath = path.expandingTildeInPath
        sources[expandedPath]?.cancel()
        sources.removeValue(forKey: expandedPath)
        fileDescriptors.removeValue(forKey: expandedPath)
    }

    func stopAll() {
        for (_, source) in sources {
            source.cancel()
        }
        sources.removeAll()
        fileDescriptors.removeAll()
    }

    deinit {
        stopAll()
    }
}
