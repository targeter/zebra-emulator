import Foundation

struct HTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data

    var pathWithoutQuery: String {
        path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? path
    }

    static func parse(data: Data) -> HTTPRequest? {
        guard let text = String(data: data, encoding: .utf8) else {
            return nil
        }

        guard let headerRange = text.range(of: "\r\n\r\n") else {
            return nil
        }

        let headerText = String(text[..<headerRange.lowerBound])
        let bodyStart = text.distance(from: text.startIndex, to: headerRange.upperBound)
        let bodyData = data.count >= bodyStart ? data.suffix(from: bodyStart) : Data()
        var lines = headerText.components(separatedBy: "\r\n")

        guard let requestLine = lines.first else {
            return nil
        }

        lines.removeFirst()
        let requestParts = requestLine.split(separator: " ")
        guard requestParts.count >= 2 else {
            return nil
        }

        var headers: [String: String] = [:]
        for line in lines {
            let components = line.split(separator: ":", maxSplits: 1).map(String.init)
            if components.count == 2 {
                headers[components[0].trimmingCharacters(in: .whitespaces)] = components[1].trimmingCharacters(in: .whitespaces)
            }
        }

        return HTTPRequest(
            method: String(requestParts[0]),
            path: String(requestParts[1]),
            headers: headers,
            body: Data(bodyData)
        )
    }

    static func isCompletePayload(_ data: Data) -> Bool {
        guard let text = String(data: data, encoding: .utf8),
              let headerRange = text.range(of: "\r\n\r\n") else {
            return false
        }

        let headerText = String(text[..<headerRange.lowerBound])
        let headerLength = text.distance(from: text.startIndex, to: headerRange.upperBound)
        let contentLength = parseContentLength(from: headerText)
        if contentLength == 0 {
            return true
        }
        return data.count >= headerLength + contentLength
    }

    private static func parseContentLength(from headerText: String) -> Int {
        for line in headerText.components(separatedBy: "\r\n") {
            if line.lowercased().hasPrefix("content-length:") {
                let value = line.split(separator: ":", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces) ?? "0"
                return Int(value) ?? 0
            }
        }
        return 0
    }
}

struct HTTPResponse {
    let statusCode: Int
    let body: String
    let additionalHeaders: [String: String]

    init(statusCode: Int, body: String, additionalHeaders: [String: String] = [:]) {
        self.statusCode = statusCode
        self.body = body
        self.additionalHeaders = additionalHeaders
    }

    var serializedData: Data {
        var headers: [String: String] = [
            "Content-Length": "\(body.utf8.count)",
            "Connection": "close"
        ]
        for (key, value) in additionalHeaders {
            headers[key] = value
        }

        let headerBlock = headers
            .map { "\($0.key): \($0.value)" }
            .joined(separator: "\r\n")
        let statusText = HTTPResponse.statusText(for: statusCode)
        let raw = "HTTP/1.1 \(statusCode) \(statusText)\r\n\(headerBlock)\r\n\r\n\(body)"
        return Data(raw.utf8)
    }

    private static func statusText(for code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 204: return "No Content"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 500: return "Internal Server Error"
        default: return "Status"
        }
    }
}
