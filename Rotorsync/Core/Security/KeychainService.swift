import Foundation
import Security

class KeychainService {
    
    // MARK: - Configuration
    
    private static let service = "com.rotorsync"
    private static let tokenKey = "authToken"
    
    // MARK: - Token Management
    
    /// Save authentication token to Keychain
    /// - Parameter token: The authentication token to save
    /// - Returns: Boolean indicating success or failure
    static func saveToken(_ token: String) -> Bool {
        guard let data = token.data(using: .utf8) else {
            print("Keychain: Failed to convert token to data")
            return false
        }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tokenKey,
            kSecValueData as String: data
        ]
        
        // Delete existing token first
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        if status == errSecSuccess {
            print("Keychain: Token saved successfully")
            return true
        } else {
            print("Keychain: Failed to save token with status: \(status)")
            return false
        }
    }
    
    /// Retrieve authentication token from Keychain
    /// - Returns: The stored token, or nil if not found
    static func getToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tokenKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        guard status == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8) else {
            if status != errSecItemNotFound {
                print("Keychain: Failed to retrieve token with status: \(status)")
            }
            return nil
        }
        
        return token
    }
    
    /// Delete authentication token from Keychain
    /// - Returns: Boolean indicating success or failure
    @discardableResult
    static func deleteToken() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tokenKey
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        if status == errSecSuccess || status == errSecItemNotFound {
            print("Keychain: Token deleted successfully")
            return true
        } else {
            print("Keychain: Failed to delete token with status: \(status)")
            return false
        }
    }
    
    // MARK: - Generic Keychain Operations
    
    /// Save any string value to Keychain
    /// - Parameters:
    ///   - value: The string value to save
    ///   - key: The key to identify the value
    /// - Returns: Boolean indicating success or failure
    static func save(value: String, forKey key: String) -> Bool {
        guard let data = value.data(using: .utf8) else {
            print("Keychain: Failed to convert value to data for key: \(key)")
            return false
        }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        
        // Delete existing value first
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        if status == errSecSuccess {
            print("Keychain: Value saved successfully for key: \(key)")
            return true
        } else {
            print("Keychain: Failed to save value for key: \(key) with status: \(status)")
            return false
        }
    }
    
    /// Retrieve any string value from Keychain
    /// - Parameter key: The key to identify the value
    /// - Returns: The stored string, or nil if not found
    static func getValue(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            if status != errSecItemNotFound {
                print("Keychain: Failed to retrieve value for key: \(key) with status: \(status)")
            }
            return nil
        }
        
        return value
    }
    
    /// Delete any value from Keychain
    /// - Parameter key: The key to identify the value
    /// - Returns: Boolean indicating success or failure
    @discardableResult
    static func deleteValue(forKey key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        if status == errSecSuccess || status == errSecItemNotFound {
            print("Keychain: Value deleted successfully for key: \(key)")
            return true
        } else {
            print("Keychain: Failed to delete value for key: \(key) with status: \(status)")
            return false
        }
    }
    
    /// Update an existing value in Keychain
    /// - Parameters:
    ///   - value: The new string value
    ///   - key: The key to identify the value
    /// - Returns: Boolean indicating success or failure
    static func update(value: String, forKey key: String) -> Bool {
        guard let data = value.data(using: .utf8) else {
            print("Keychain: Failed to convert value to data for key: \(key)")
            return false
        }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        
        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]
        
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        
        if status == errSecSuccess {
            print("Keychain: Value updated successfully for key: \(key)")
            return true
        } else if status == errSecItemNotFound {
            // Item doesn't exist, create it instead
            return save(value: value, forKey: key)
        } else {
            print("Keychain: Failed to update value for key: \(key) with status: \(status)")
            return false
        }
    }
    
    // MARK: - Utility Methods
    
    /// Check if a token exists in Keychain
    /// - Returns: Boolean indicating if token exists
    static func hasToken() -> Bool {
        return getToken() != nil
    }
    
    /// Check if a value exists for a given key
    /// - Parameter key: The key to check
    /// - Returns: Boolean indicating if value exists
    static func hasValue(forKey key: String) -> Bool {
        return getValue(forKey: key) != nil
    }
    
    /// Clear all Keychain items for this service
    /// - Returns: Boolean indicating success or failure
    @discardableResult
    static func clearAll() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        if status == errSecSuccess || status == errSecItemNotFound {
            print("Keychain: All items cleared successfully")
            return true
        } else {
            print("Keychain: Failed to clear all items with status: \(status)")
            return false
        }
    }
}

// MARK: - Keychain Error Extension
extension KeychainService {
    
    /// Get human-readable error message for Keychain status codes
    /// - Parameter status: The OSStatus code
    /// - Returns: Human-readable error message
    static func errorMessage(for status: OSStatus) -> String {
        switch status {
        case errSecSuccess:
            return "Success"
        case errSecItemNotFound:
            return "Item not found"
        case errSecDuplicateItem:
            return "Duplicate item"
        case errSecAuthFailed:
            return "Authentication failed"
        case errSecParam:
            return "Invalid parameter"
        case errSecAllocate:
            return "Memory allocation failed"
        case errSecNotAvailable:
            return "Service not available"
        case errSecInteractionNotAllowed:
            return "User interaction not allowed"
        case errSecDecode:
            return "Decode failed"
        default:
            return "Unknown error: \(status)"
        }
    }
}
