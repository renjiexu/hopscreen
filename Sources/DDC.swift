// DDC/CI over IOAVService (Apple Silicon). Same private API used by m1ddc and MonitorControl.

import Foundation
import IOKit

@_silgen_name("IOAVServiceCreateWithService")
private func IOAVServiceCreateWithService(_ allocator: CFAllocator?, _ service: io_service_t) -> Unmanaged<CFTypeRef>?
@_silgen_name("IOAVServiceReadI2C")
private func IOAVServiceReadI2C(_ service: CFTypeRef, _ chipAddress: UInt32, _ offset: UInt32, _ buffer: UnsafeMutableRawPointer, _ size: UInt32) -> IOReturn
@_silgen_name("IOAVServiceWriteI2C")
private func IOAVServiceWriteI2C(_ service: CFTypeRef, _ chipAddress: UInt32, _ dataAddress: UInt32, _ buffer: UnsafeMutableRawPointer, _ size: UInt32) -> IOReturn
@_silgen_name("IOAVServiceCopyEDID")
private func IOAVServiceCopyEDID(_ service: CFTypeRef, _ edid: UnsafeMutablePointer<Unmanaged<CFData>?>) -> IOReturn

/// An external display reachable over DDC.
struct Display {
    /// Stable identifier derived from the EDID (vendor, product, serial).
    let id: String
    let name: String
    let vendor: String
    fileprivate let service: CFTypeRef

    static let inputSourceVCP: UInt8 = 0x60

    static func all() -> [Display] {
        var result: [Display] = []
        var iter = io_iterator_t()
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("DCPAVServiceProxy"), &iter) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iter) }
        while true {
            let entry = IOIteratorNext(iter)
            if entry == 0 { break }
            defer { IOObjectRelease(entry) }
            let location = IORegistryEntryCreateCFProperty(entry, "Location" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? String
            guard location == "External",
                  let av = IOAVServiceCreateWithService(kCFAllocatorDefault, entry)?.takeRetainedValue() else { continue }
            var edidRef: Unmanaged<CFData>?
            let edid = IOAVServiceCopyEDID(av, &edidRef) == kIOReturnSuccess ? edidRef?.takeRetainedValue() as Data? : nil
            let info = edid.flatMap(EDID.init)
            var id = info?.id ?? "unknown-\(result.count + 1)"
            // Two identical monitors without serials: keep ids unique.
            while result.contains(where: { $0.id == id }) { id += "#2" }
            result.append(Display(id: id, name: info?.name ?? "External Display \(result.count + 1)",
                                  vendor: info?.vendor ?? "", service: av))
        }
        return result
    }

    @discardableResult
    func write(vcp: UInt8, value: UInt16) -> Bool {
        var data: [UInt8] = [0x84, 0x03, vcp, UInt8(value >> 8), UInt8(value & 0xFF), 0]
        data[5] = data[0..<5].reduce(0x6E ^ 0x51, ^)
        var ok = false
        for _ in 0..<2 { // send twice, some monitors drop the first packet
            usleep(10_000)
            if IOAVServiceWriteI2C(service, 0x37, 0x51, &data, UInt32(data.count)) == kIOReturnSuccess { ok = true }
        }
        return ok
    }

    func read(vcp: UInt8) -> (current: UInt16, max: UInt16)? {
        var request: [UInt8] = [0x82, 0x01, vcp, 0]
        request[3] = request[0..<3].reduce(0x6E ^ 0x51, ^)
        for _ in 0..<4 {
            var reply = [UInt8](repeating: 0, count: 12)
            usleep(10_000)
            guard IOAVServiceWriteI2C(service, 0x37, 0x51, &request, UInt32(request.count)) == kIOReturnSuccess else { continue }
            usleep(50_000)
            guard IOAVServiceReadI2C(service, 0x37, 0x51, &reply, UInt32(reply.count)) == kIOReturnSuccess else { continue }
            // [src, len, 0x02, result, vcp, type, maxHi, maxLo, curHi, curLo, chk]
            guard reply[2] == 0x02, reply[3] == 0x00, reply[4] == vcp else { continue }
            return (UInt16(reply[8]) << 8 | UInt16(reply[9]), UInt16(reply[6]) << 8 | UInt16(reply[7]))
        }
        return nil
    }

    func setInput(_ value: UInt16) -> Bool {
        write(vcp: Self.inputSourceVCP, value: value)
    }

    /// Current input source. Many monitors (e.g. Dell) put junk in the high byte, so only the low byte is returned.
    func currentInput() -> UInt16? {
        read(vcp: Self.inputSourceVCP).map { $0.current & 0xFF }
    }
}

private struct EDID {
    let vendor: String
    let product: UInt16
    let serial: String
    let name: String?

    var id: String { "\(vendor)-\(String(format: "%04X", product))-\(serial)" }

    init?(_ data: Data) {
        let b = [UInt8](data)
        guard b.count >= 128, b[0] == 0x00, b[1] == 0xFF else { return nil }
        let m = UInt16(b[8]) << 8 | UInt16(b[9])
        vendor = String([(m >> 10) & 0x1F, (m >> 5) & 0x1F, m & 0x1F].map { Character(UnicodeScalar(UInt8($0) + 64)) })
        product = UInt16(b[11]) << 8 | UInt16(b[10])
        var name: String?
        var serialText: String?
        for offset in stride(from: 54, to: 126, by: 18) where b[offset] == 0 && b[offset + 1] == 0 && b[offset + 2] == 0 {
            let text = String(decoding: b[(offset + 5)..<(offset + 18)].prefix { $0 != 0x0A }, as: UTF8.self)
                .trimmingCharacters(in: .whitespaces)
            switch b[offset + 3] {
            case 0xFC: name = text
            case 0xFF: serialText = text
            default: break
            }
        }
        let serialNumber = UInt32(b[15]) << 24 | UInt32(b[14]) << 16 | UInt32(b[13]) << 8 | UInt32(b[12])
        serial = serialText ?? String(serialNumber)
        self.name = name
    }
}
