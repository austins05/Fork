import Foundation

class APIService {
    static let shared = APIService()
    
    private init() {}
    
    // MARK: - Authentication
    
    func login(email: String, password: String, completion: @escaping (Result<(User, String), Error>) -> Void) {
        let url = URL(string: "https://rotorsync-web.vercel.app/api/auth/login")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["email": email, "password": password]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse, let data = data else {
                completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])))
                return
            }
            
            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                guard let success = json?["success"] as? Bool else {
                    completion(.failure(NSError(domain: "", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])))
                    return
                }
                
                if success, let dataDict = json?["data"] as? [String: Any],
                   let token = dataDict["token"] as? String,
                   let userDict = dataDict["user"] as? [String: Any],
                   let userData = try? JSONSerialization.data(withJSONObject: userDict),
                   let user = try? JSONDecoder().decode(User.self, from: userData) {
                    completion(.success((user, token)))
                } else {
                    let errorMessage = (json?["error"] as? String) ?? "Unknown error"
                    completion(.failure(NSError(domain: "", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMessage])))
                }
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
}
