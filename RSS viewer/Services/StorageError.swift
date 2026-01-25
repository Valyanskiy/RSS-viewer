//
//  StorageError.swift
//  RSS viewer
//
//  Created by Андрей Валянский on 25.01.2026.
//

import Foundation

enum StorageError: LocalizedError {
    case invalidURL
    case networkError
    case feedNotFound
    case invalidFeedData
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Неверный URL адрес"
        case .networkError:
            return "Не удалось загрузить данные"
        case .feedNotFound:
            return "Канал не найден"
        case .invalidFeedData:
            return "Данные канала повреждены"
        }
    }
}
