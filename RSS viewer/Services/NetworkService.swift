//
//  NetworkService.swift
//  RSS viewer
//
//  Created by Андрей Валянский on 16.01.2026.
//

import Foundation

class NetworkService {
    func fetch(url: URL) async throws -> Data {
        if url.scheme != "https" {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.scheme = "https"
            guard let httpsURL = components?.url else {
                throw URLError(.badURL)
            }
            return try await fetchData(url: httpsURL)
        } else {
            return try await fetchData(url: url)
        }
        
        func fetchData(url: URL) async throws -> Data {
            let (data, responce) = try await URLSession.shared.data(from: url)
            guard let httpResponce = responce as? HTTPURLResponse, httpResponce.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            
            return data
        }
    }
}
