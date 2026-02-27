import Foundation
import Security

enum TLSIdentityError: Error {
    case opensslMissing
    case opensslFailed(String)
    case identityImportFailed
    case appSupportDirectoryUnavailable
}

final class TLSIdentityManager {
    private let passphrase = "zebra-emulator"

    func loadOrCreateIdentity() throws -> (identity: SecIdentity, certificates: [SecCertificate]) {
        let paths = try certificatePaths()
        if !FileManager.default.fileExists(atPath: paths.pkcs12.path) {
            try generateCertificateFiles(paths: paths)
        }

        let data = try Data(contentsOf: paths.pkcs12)
        var importedItems: CFArray?
        var options: [String: Any] = [kSecImportExportPassphrase as String: passphrase]
        if #available(macOS 15.0, *) {
            options[kSecImportToMemoryOnly as String] = true
        }
        let status = SecPKCS12Import(data as CFData, options as CFDictionary, &importedItems)
        guard status == errSecSuccess,
              let items = importedItems as? [[String: Any]],
              let first = items.first,
              let identity = first[kSecImportItemIdentity as String] as! SecIdentity? else {
            throw TLSIdentityError.identityImportFailed
        }

        let chain = first[kSecImportItemCertChain as String] as? [SecCertificate]
        let certificates = chain ?? []
        return (identity, certificates)
    }

    private func certificatePaths() throws -> (directory: URL, cert: URL, key: URL, pkcs12: URL) {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw TLSIdentityError.appSupportDirectoryUnavailable
        }
        let directory = appSupport.appendingPathComponent("ZebraBrowserPrintEmulator", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (
            directory,
            directory.appendingPathComponent("localhost-cert.pem"),
            directory.appendingPathComponent("localhost-key.pem"),
            directory.appendingPathComponent("localhost-identity.p12")
        )
    }

    private func generateCertificateFiles(paths: (directory: URL, cert: URL, key: URL, pkcs12: URL)) throws {
        guard FileManager.default.isReadableFile(atPath: "/usr/bin/openssl") else {
            throw TLSIdentityError.opensslMissing
        }

        try runOpenSSL(arguments: [
            "req", "-x509", "-newkey", "rsa:2048", "-nodes",
            "-keyout", paths.key.path,
            "-out", paths.cert.path,
            "-days", "3650",
            "-subj", "/CN=localhost"
        ])

        try runOpenSSL(arguments: [
            "pkcs12", "-export",
            "-inkey", paths.key.path,
            "-in", paths.cert.path,
            "-out", paths.pkcs12.path,
            "-passout", "pass:\(passphrase)"
        ])
    }

    private func runOpenSSL(arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        process.arguments = arguments

        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? "Unknown OpenSSL error"
            throw TLSIdentityError.opensslFailed(output)
        }
    }
}
