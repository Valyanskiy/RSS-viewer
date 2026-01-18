//
//  RSSListViewController.swift
//  RSS viewer
//
//  Created by Андрей Валянский on 16.01.2026.
//

import UIKit
import CoreData

class RSSListViewController: UIViewController {
    let storageService = StorageService()
    
    lazy var addFeedButton = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(showAddFeedAlert))
    lazy var tableView: UITableView = {
        $0.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        $0.dataSource = self
        $0.delegate = self
        return $0
    }(UITableView(frame: view.frame, style: .insetGrouped))
    lazy var fetchedResultsController: NSFetchedResultsController<Feed> = {
        let request: NSFetchRequest<Feed> = Feed.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(key: "lastFetched", ascending: false)
        ]

        let frc = NSFetchedResultsController(
            fetchRequest: request,
            managedObjectContext: storageService.context,
            sectionNameKeyPath: nil,
            cacheName: nil
        )

        frc.delegate = self
        return frc
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "RSS каналы"
//        navigationController?.navigationBar.prefersLargeTitles = true
        
        navigationController?.setToolbarHidden(false, animated: false)
        navigationItem.rightBarButtonItem = addFeedButton
        
        view.addSubview(tableView)
        
        do {
            try fetchedResultsController.performFetch()
        } catch {
            print("Ошибка загрузки данных: \(error)")
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
            try await storageService.saveFeed(urlString)
        } catch {
            print("Ошибка: \(error)")
        }
    }
}

extension RSSListViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        fetchedResultsController.sections?[section].numberOfObjects ?? 0
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        
        let feed = fetchedResultsController.object(at: indexPath)
        
        var config = cell.defaultContentConfiguration()
        config.text = feed.title
        config.secondaryText = feed.channelDescription
        
        cell.contentConfiguration = config
        cell.accessoryType = .disclosureIndicator
        
        return cell
    }
}

extension RSSListViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            let feed = fetchedResultsController.object(at: indexPath)
            do {
                try storageService.deleteFeed(feed)
            } catch {
                print("Ошибка удаления:", error)
            }
        }
    }
}

extension RSSListViewController: NSFetchedResultsControllerDelegate {
    func controllerWillChangeContent(_ controller: NSFetchedResultsController<any NSFetchRequestResult>) {
        tableView.beginUpdates()
    }
    
    func controller(_ controller: NSFetchedResultsController<any NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        switch type {
        case .insert:
            tableView.insertRows(at: [newIndexPath!], with: .automatic)
        case .delete:
            tableView.deleteRows(at: [indexPath!], with: .automatic)
        case .update:
            tableView.reloadRows(at: [indexPath!], with: .automatic)
        case .move:
            tableView.moveRow(at: indexPath!, to: newIndexPath!)
        @unknown default:
            break
        }
    }
    
    func controllerDidChangeContent(
        _ controller: NSFetchedResultsController<NSFetchRequestResult>
    ) {
        tableView.endUpdates()
    }
}
