import Foundation
import Darwin

/// Lit la liste des processus avec les API du noyau (sysctl, libproc), sans lancer `ps`.
/// Garde l'échantillon précédent pour calculer le % CPU.
public final class ProcessSampler: @unchecked Sendable {
    private struct CPUSample {
        var start: Int
        var cpu: UInt64
        var wall: UInt64
    }

    private struct ArgumentKey: Hashable {
        var pid: Int32
        var start: Int
    }

    private let lock = NSLock()
    private var previous: [Int32: CPUSample] = [:]
    private var argumentCache: [ArgumentKey: [String]] = [:]
    private var pathBuffer = [UInt8](repeating: 0, count: 4096)

    public init() {}

    /// Infos de base pour tous les processus de la machine.
    public func snapshot() -> [RawProcess] {
        lock.lock()
        defer { lock.unlock() }

        let wall = mach_absolute_time()
        var next: [Int32: CPUSample] = [:]
        var result: [RawProcess] = []

        for info in Self.allKinfo() {
            let pid = info.kp_proc.p_pid
            if Int32(info.kp_proc.p_stat) == SZOMB { continue }

            let comm = Self.string(fromTuple: info.kp_proc.p_comm)
            let startSeconds = Int(info.kp_proc.p_un.__p_starttime.tv_sec)
            let start = startSeconds > 0 ? Date(timeIntervalSince1970: TimeInterval(startSeconds)) : nil
            let path = pid > 0 ? executablePath(pid) : ""

            var memory: UInt64?
            var cpuPercent: Double?
            if pid > 0, let usage = Self.usage(pid) {
                memory = usage.footprint
                if let prev = previous[pid], prev.start == startSeconds, wall > prev.wall, usage.cpu >= prev.cpu {
                    // ri_user_time/ri_system_time et mach_absolute_time sont dans la même unité (ticks Mach).
                    cpuPercent = Double(usage.cpu - prev.cpu) / Double(wall - prev.wall) * 100
                }
                next[pid] = CPUSample(start: startSeconds, cpu: usage.cpu, wall: wall)
            }

            let name: String
            if pid == 0 {
                name = "kernel_task"
            } else if path.isEmpty {
                name = comm
            } else {
                name = (path as NSString).lastPathComponent
            }

            result.append(RawProcess(
                pid: pid,
                ppid: info.kp_eproc.e_ppid,
                uid: info.kp_eproc.e_ucred.cr_uid,
                name: name,
                path: path,
                startTime: start,
                memory: memory,
                cpuPercent: cpuPercent,
                responsiblePID: pid > 1 ? Self.responsiblePID(pid) : nil
            ))
        }

        previous = next
        let alive = Set(result.map(\.pid))
        argumentCache = argumentCache.filter { alive.contains($0.key.pid) }
        return result
    }

    /// Dossier de travail, arguments et ports en écoute. Réservé aux processus de dev (quelques dizaines).
    public func details(for process: RawProcess) -> ProcessDetails {
        let key = ArgumentKey(pid: process.pid, start: Int(process.startTime?.timeIntervalSince1970 ?? 0))
        lock.lock()
        let cached = argumentCache[key]
        lock.unlock()

        let arguments = cached ?? Self.arguments(process.pid)
        if cached == nil {
            lock.lock()
            argumentCache[key] = arguments
            lock.unlock()
        }
        return ProcessDetails(
            cwd: Self.currentDirectory(process.pid),
            arguments: arguments,
            sockets: Self.listeningSockets(process.pid)
        )
    }

    // MARK: - Appels système

    private static func allKinfo() -> [kinfo_proc] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL]
        let stride = MemoryLayout<kinfo_proc>.stride
        for _ in 0..<3 {
            var size = 0
            guard sysctl(&mib, 3, nil, &size, nil, 0) == 0 else { return [] }
            var buffer = [kinfo_proc](repeating: kinfo_proc(), count: size / stride + 64)
            size = buffer.count * stride
            let rc = buffer.withUnsafeMutableBytes { sysctl(&mib, 3, $0.baseAddress, &size, nil, 0) }
            if rc == 0 {
                return Array(buffer.prefix(size / stride))
            }
            if errno != ENOMEM { return [] }
        }
        return []
    }

    private func executablePath(_ pid: Int32) -> String {
        let count = pathBuffer.withUnsafeMutableBytes { proc_pidpath(pid, $0.baseAddress, UInt32($0.count)) }
        guard count > 0 else { return "" }
        return String(decoding: pathBuffer[0..<Int(count)], as: UTF8.self)
    }

    private static func usage(_ pid: Int32) -> (footprint: UInt64, cpu: UInt64)? {
        var info = rusage_info_v4()
        let rc = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        guard rc == 0 else { return nil }
        return (info.ri_phys_footprint, info.ri_user_time &+ info.ri_system_time)
    }

    private typealias ResponsibleFunction = @convention(c) (pid_t) -> pid_t

    /// Fonction non documentée de macOS, utilisée par le Moniteur d'activité pour rattacher
    /// un service à l'app qui l'a demandé. Chargée dynamiquement : si elle disparaît, Vigie s'en passe.
    private static let responsibleFunction: ResponsibleFunction? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid") else {
            return nil
        }
        return unsafeBitCast(symbol, to: ResponsibleFunction.self)
    }()

    private static func responsiblePID(_ pid: Int32) -> Int32? {
        guard let function = responsibleFunction else { return nil }
        let responsible = function(pid)
        return responsible > 0 && responsible != pid ? responsible : nil
    }

    static func currentDirectory(_ pid: Int32) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = withUnsafeBytes(of: info.pvi_cdir.vip_path) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        return path.isEmpty ? nil : path
    }

    static func arguments(_ pid: Int32) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return [] }
        var buffer = [UInt8](repeating: 0, count: size)
        let rc = buffer.withUnsafeMutableBytes { sysctl(&mib, 3, $0.baseAddress, &size, nil, 0) }
        guard rc == 0, size > MemoryLayout<Int32>.size else { return [] }

        let argc = buffer.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        var index = MemoryLayout<Int32>.size
        while index < size, buffer[index] != 0 { index += 1 }  // chemin de l'exécutable
        while index < size, buffer[index] == 0 { index += 1 }  // remplissage

        var arguments: [String] = []
        while arguments.count < Int(argc), index < size {
            let begin = index
            while index < size, buffer[index] != 0 { index += 1 }
            arguments.append(String(decoding: buffer[begin..<index], as: UTF8.self))
            index += 1
        }
        return arguments
    }

    static func listeningPorts(_ pid: Int32) -> [Int] {
        Array(Set(listeningSockets(pid).map(\.port))).sorted()
    }

    /// Ports TCP en écoute d'un processus, avec l'adresse : seulement ce Mac (127.0.0.1, ::1) ou tout le réseau.
    public static func listeningSockets(_ pid: Int32) -> [ListeningSocket] {
        let bufferSize = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard bufferSize > 0 else { return [] }
        let stride = MemoryLayout<proc_fdinfo>.stride
        var descriptors = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(bufferSize) / stride)
        let used = descriptors.withUnsafeMutableBytes { proc_pidinfo(pid, PROC_PIDLISTFDS, 0, $0.baseAddress, bufferSize) }
        guard used > 0 else { return [] }

        var sockets: [ListeningSocket] = []
        for descriptor in descriptors.prefix(Int(used) / stride) where descriptor.proc_fdtype == UInt32(PROX_FDTYPE_SOCKET) {
            var socket = socket_fdinfo()
            let socketSize = Int32(MemoryLayout<socket_fdinfo>.size)
            guard proc_pidfdinfo(pid, descriptor.proc_fd, PROC_PIDFDSOCKETINFO, &socket, socketSize) == socketSize else { continue }
            guard Int(socket.psi.soi_kind) == Int(SOCKINFO_TCP) else { continue }
            let tcp = socket.psi.soi_proto.pri_tcp
            guard Int(tcp.tcpsi_state) == Int(TSI_S_LISTEN) else { continue }
            let port = Int(UInt16(bigEndian: UInt16(truncatingIfNeeded: tcp.tcpsi_ini.insi_lport)))
            guard port > 0 else { continue }
            let info = tcp.tcpsi_ini
            let address: String
            if info.insi_vflag & UInt8(INI_IPV6) != 0 {
                var raw = info.insi_laddr.ina_6
                var text = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
                inet_ntop(AF_INET6, &raw, &text, socklen_t(text.count))
                address = String(cString: text)
            } else {
                var raw = info.insi_laddr.ina_46.i46a_addr4
                var text = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                inet_ntop(AF_INET, &raw, &text, socklen_t(text.count))
                address = String(cString: text)
            }
            let item = ListeningSocket(port: port, address: address)
            if !sockets.contains(item) { sockets.append(item) }
        }
        return sockets.sorted { ($0.port, $0.address) < ($1.port, $1.address) }
    }

    static func string<T>(fromTuple tuple: T) -> String {
        withUnsafeBytes(of: tuple) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}

public enum SystemMemory {
    private static let host = mach_host_self()

    /// Mémoire utilisée au sens du Moniteur d'activité (mémoire des apps + mémoire résidente + compressée).
    public static func current() -> (used: UInt64, total: UInt64) {
        let total = ProcessInfo.processInfo.physicalMemory
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, total) }
        var pageSize: vm_size_t = 0
        host_page_size(host, &pageSize)
        let internalPages = UInt64(stats.internal_page_count)
        let purgeable = UInt64(stats.purgeable_count)
        let appPages = internalPages > purgeable ? internalPages - purgeable : 0
        let pages = appPages + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)
        return (pages * UInt64(pageSize), total)
    }
}

public enum ProcessSignals {
    /// Envoie un signal en ignorant les pids réservés et Vigie elle-même. Renvoie les pids visés.
    @discardableResult
    public static func send(_ signal: Int32, to pids: [Int32]) -> [Int32] {
        let me = getpid()
        let targets = pids.filter { $0 > 1 && $0 != me }
        for pid in targets {
            kill(pid, signal)
        }
        return targets
    }

    public static func isAlive(_ pid: Int32) -> Bool {
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }
}
