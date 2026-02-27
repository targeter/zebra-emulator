import Foundation

final class ZPLRenderer {
    func render(zpl: String) async throws -> Data {
        guard let url = URL(string: "https://api.labelary.com/v1/printers/8dpmm/labels/4x6/0/") else {
            throw RendererError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data(zpl.utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("image/png", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw RendererError.remoteError
        }

        return data
    }
}

enum RendererError: Error {
    case invalidURL
    case remoteError
}
