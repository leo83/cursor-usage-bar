import Foundation

enum UsageError: Error, LocalizedError {
    case noToken
    case unauthorized
    case http(Int)
    case network(String)
    case decode(String)

    var errorDescription: String? {
        switch self {
        case .noToken:
            return "Токен Cursor не найден — обычно это значит, что Cursor не запущен или в нём не выполнен вход. Откройте Cursor и залогиньтесь, либо укажите CURSOR_API_KEY/CURSOR_TOKEN или сохраните токен в настройках."
        case .unauthorized:
            return "Cursor отклонил авторизацию (401/403). Откройте Cursor и убедитесь, что аккаунт залогинен."
        case .http(let code):
            if code == 429 { return "Слишком много запросов (429)" }
            return "HTTP \(code)"
        case .network(let msg):
            return "Сеть: \(msg)"
        case .decode(let msg):
            return "Ошибка разбора ответа: \(msg)"
        }
    }

    var isTransient: Bool {
        switch self {
        case .http(let code):
            return code == 429 || (500...599).contains(code)
        case .network:
            return true
        case .noToken, .unauthorized, .decode:
            return false
        }
    }
}

final class UsageClient {
    private static let maxRetries = 2
    private static let retryDelay: TimeInterval = 1.5

    func fetch(completion: @escaping (Result<[BarSpec], UsageError>) -> Void) {
        guard let token = Credentials.accessToken() else {
            completion(.failure(.noToken))
            return
        }
        attempt(endpoints: Settings.fallbackUsageEndpoints, token: token, retriesLeft: Self.maxRetries, completion: completion)
    }

    func fetchOnce(completion: @escaping (Result<[BarSpec], UsageError>) -> Void) {
        guard let token = Credentials.accessToken() else {
            completion(.failure(.noToken))
            return
        }
        attempt(endpoints: [Settings.usageEndpoint], token: token, retriesLeft: 0, completion: completion)
    }

    static func friendlyNetworkMessage(_ error: Error) -> String {
        let ns = error as NSError
        if ns.domain == (kCFErrorDomainCFNetwork as String) {
            switch ns.code {
            case 310, 311, 306:
                return "нет связи с прокси (\(ns.code))"
            case 307:
                return "прокси отклонил логин/пароль (307)"
            default:
                break
            }
        }
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorTimedOut:
                return "таймаут запроса"
            case NSURLErrorNotConnectedToInternet:
                return "нет интернета"
            case NSURLErrorCannotConnectToHost, NSURLErrorCannotFindHost:
                return "не удаётся подключиться к серверу"
            case NSURLErrorNetworkConnectionLost:
                return "соединение прервано"
            default:
                break
            }
        }
        return ns.localizedDescription
    }

    private func attempt(
        endpoints: [String],
        token: String,
        retriesLeft: Int,
        completion: @escaping (Result<[BarSpec], UsageError>) -> Void
    ) {
        guard let endpoint = endpoints.first, let url = URL(string: endpoint) else {
            completion(.failure(.network("нет валидного endpoint")))
            return
        }

        var request = URLRequest(url: url)
        let isConnectRPC = endpoint.contains("/aiserver.v1.")
        request.httpMethod = isConnectRPC ? "POST" : "GET"
        request.timeoutInterval = 20
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if isConnectRPC {
            request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
            request.httpBody = "{}".data(using: .utf8)
        }
        request.setValue("CursorUsageTray/0.1", forHTTPHeaderField: "User-Agent")

        let proxy = Settings.activeProxy
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = false
        if let proxy = proxy {
            var proxyDict: [AnyHashable: Any] = [
                kCFNetworkProxiesHTTPEnable as String: true,
                kCFNetworkProxiesHTTPProxy as String: proxy.host,
                kCFNetworkProxiesHTTPPort as String: proxy.port,
                "HTTPSEnable": true,
                "HTTPSProxy": proxy.host,
                "HTTPSPort": proxy.port,
            ]
            if let user = proxy.username, let pass = proxy.password {
                proxyDict[kCFProxyUsernameKey as String] = user
                proxyDict[kCFProxyPasswordKey as String] = pass
            }
            config.connectionProxyDictionary = proxyDict
        }

        let delegate = ProxyAuthDelegate(username: proxy?.username, password: proxy?.password)
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)

        let task = session.dataTask(with: request) { [weak self] data, response, error in
            defer { session.finishTasksAndInvalidate() }

            let deliver: (Result<[BarSpec], UsageError>) -> Void = { result in
                if case .failure(let err) = result {
                    if case .http(let code) = err, [404, 405].contains(code), endpoints.count > 1, let self {
                        self.attempt(endpoints: Array(endpoints.dropFirst()), token: token, retriesLeft: retriesLeft, completion: completion)
                        return
                    }
                    if err.isTransient, retriesLeft > 0, let self {
                        DispatchQueue.global().asyncAfter(deadline: .now() + Self.retryDelay) {
                            self.attempt(endpoints: endpoints, token: token, retriesLeft: retriesLeft - 1, completion: completion)
                        }
                        return
                    }
                }
                DispatchQueue.main.async { completion(result) }
            }

            if let error = error {
                deliver(.failure(.network(Self.friendlyNetworkMessage(error))))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                deliver(.failure(.network("нет ответа")))
                return
            }
            if http.statusCode == 401 || http.statusCode == 403 {
                deliver(.failure(.unauthorized))
                return
            }
            guard (200..<300).contains(http.statusCode) else {
                deliver(.failure(.http(http.statusCode)))
                return
            }
            guard let data = data else {
                deliver(.failure(.decode("пустое тело")))
                return
            }
            let contentType = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
            if !contentType.contains("json"), endpoints.count > 1 {
                self?.attempt(endpoints: Array(endpoints.dropFirst()), token: token, retriesLeft: retriesLeft, completion: completion)
                return
            }
            do {
                let decoded = try JSONDecoder().decode(UsageResponse.self, from: data)
                guard !decoded.bars.isEmpty else {
                    deliver(.failure(.decode("не найдены usage-бакеты Cursor")))
                    return
                }
                deliver(.success(decoded.bars))
            } catch {
                deliver(.failure(.decode(error.localizedDescription)))
            }
        }
        task.resume()
    }
}

private final class ProxyAuthDelegate: NSObject, URLSessionTaskDelegate {
    let username: String?
    let password: String?

    init(username: String?, password: String?) {
        self.username = username
        self.password = password
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let method = challenge.protectionSpace.authenticationMethod
        let proxyMethods = [
            NSURLAuthenticationMethodHTTPBasic,
            NSURLAuthenticationMethodHTTPDigest,
            NSURLAuthenticationMethodNTLM,
        ]
        if proxyMethods.contains(method),
           challenge.previousFailureCount == 0,
           let username, let password {
            let credential = URLCredential(user: username, password: password, persistence: .forSession)
            completionHandler(.useCredential, credential)
            return
        }
        completionHandler(.performDefaultHandling, nil)
    }
}
