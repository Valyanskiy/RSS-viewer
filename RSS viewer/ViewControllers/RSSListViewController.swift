//
//  RSSListViewController.swift
//  RSS viewer
//
//  Created by Андрей Валянский on 16.01.2026.
//

import UIKit

class RSSListViewController: UIViewController {
    let storageService = StorageService()
    var feeds: [feedsListItem]?
    
    lazy var addFeedButton = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(showAddFeedAlert))
    lazy var tableView: UITableView = {
        $0.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        $0.dataSource = self
        return $0
    }(UITableView(frame: view.frame, style: .insetGrouped))
    
    override func viewDidLoad() {
        reloadFeedsData()
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "RSS каналы"
        navigationController?.navigationBar.prefersLargeTitles = true
        
        navigationController?.setToolbarHidden(false, animated: false)
        navigationItem.rightBarButtonItem = addFeedButton
        
        view.addSubview(tableView)
    }
    
    func reloadFeedsData() {
        do {
            try feeds = storageService.feeds()
        } catch {
            print("Ошибка: \(error)")
            feeds = []
        }
    }
    
    @objc func showAddFeedAlert() {
        let alert = UIAlertController(
            title: "Добавить RSS-ленту",
            message: "Введите URL RSS-ленты",
            preferredStyle: .alert
        )
        
        alert.addTextField { textField in
            textField.placeholder = "https://example.com/rss"
            textField.keyboardType = .URL
            textField.autocapitalizationType = .none
            textField.autocorrectionType = .no
        }
        
        let addAction = UIAlertAction(title: "Добавить", style: .default) { [weak self, weak alert] _ in
            guard let textField = alert?.textFields?.first,
                  let urlString = textField.text,
                  !urlString.isEmpty else {
                return
            }
            
            Task {
                await self?.addFeed(urlString: urlString)
            }
        }
        
        alert.addAction(addAction)
        let cancelAction = UIAlertAction(title: "Отмена", style: .cancel)
        alert.addAction(cancelAction)
        
        present(alert, animated: true)
    }
    
    
    func addFeed(urlString: String) async {
        do {
            try await storageService.newFeed(urlString)
            await MainActor.run {
                self.reloadFeedsData()
                self.tableView.reloadData()
            }
        } catch {
            print("Ошибка: \(error)")
        }
    }
}

extension RSSListViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return feeds?.count ?? 0
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var config = cell.defaultContentConfiguration()
        config.text = feeds?[indexPath.row].title
        cell.contentConfiguration = config
        
        return cell
    }
    
    
}
