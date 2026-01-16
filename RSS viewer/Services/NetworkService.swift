//
//  NetworkService.swift
//  RSS viewer
//
//  Created by Андрей Валянский on 16.01.2026.
//

import Foundation

class NetworkService {
    func fetchFeed(url: URL) async throws -> Data {
        let (data, responce) = try await URLSession.shared.data(from: url)
        guard let httpResponce = responce as? HTTPURLResponse, httpResponce.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        return data
    }
}
