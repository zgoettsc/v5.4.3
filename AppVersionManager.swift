//
//  AppVersionManager.swift
//  TIPsApp
//
//  Created by Zack Goettsche on 6/28/25.
//


import Foundation
import SwiftUI

class AppVersionManager: ObservableObject {
    @Published var hasUpdate = false
    @Published var latestVersion = ""
    @Published var currentVersion = ""
    @Published var isChecking = false
    
    private let appStoreId = "6745797970" // Replace with your actual App Store ID
    
    init() {
        currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }
    
    func checkForUpdate() {
        guard !isChecking else { return }
        
        isChecking = true
        
        // iTunes Search API to get app store version
        let urlString = "https://itunes.apple.com/lookup?id=\(appStoreId)"
        guard let url = URL(string: urlString) else {
            isChecking = false
            return
        }
        
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isChecking = false
                
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let results = json["results"] as? [[String: Any]],
                      let firstResult = results.first,
                      let storeVersion = firstResult["version"] as? String else {
                    return
                }
                
                self?.latestVersion = storeVersion
                self?.hasUpdate = self?.isNewerVersion(storeVersion: storeVersion, currentVersion: self?.currentVersion ?? "") ?? false
            }
        }.resume()
    }
    
    private func isNewerVersion(storeVersion: String, currentVersion: String) -> Bool {
        let storeComponents = storeVersion.split(separator: ".").compactMap { Int($0) }
        let currentComponents = currentVersion.split(separator: ".").compactMap { Int($0) }
        
        let maxCount = max(storeComponents.count, currentComponents.count)
        
        for i in 0..<maxCount {
            let storeNumber = i < storeComponents.count ? storeComponents[i] : 0
            let currentNumber = i < currentComponents.count ? currentComponents[i] : 0
            
            if storeNumber > currentNumber {
                return true
            } else if storeNumber < currentNumber {
                return false
            }
        }
        
        return false
    }
    
    func openAppStore() {
        let urlString = "https://apps.apple.com/app/id\(appStoreId)"
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
    }
}
