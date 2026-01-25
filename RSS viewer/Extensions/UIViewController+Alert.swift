//
//  UIViewController+Alert.swift
//  RSS viewer
//
//  Created by Андрей Валянский on 25.01.2026.
//

import UIKit

extension UIViewController {
    func showError(_ message: String, title: String = "Ошибка") {
        let alert = UIAlertController(
            title: title,
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
