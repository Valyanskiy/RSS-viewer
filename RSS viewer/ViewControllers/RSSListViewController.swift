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
    
    private let titleView = UILabel()
    private let subtitleView = UILabel()
    lazy var stackView: UIStackView = {
        titleView.text = "RSS каналы"
        titleView.font = .preferredFont(forTextStyle: .headline)
        
        subtitleView.text = "Обновление..."
        subtitleView.font = .preferredFont(forTextStyle: .caption1)
        subtitleView.textColor = .secondaryLabel
        subtitleView.textAlignment = .center
        
        let stackView = UIStackView(arrangedSubviews: [titleView, subtitleView])
        stackView.axis = .vertical
        stackView.alignment = .center
        
        return stackView
    }()
    
    lazy var addFeedButton = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(showAddFeedAlert))
    
    lazy var refreshControl: UIRefreshControl = {
        $0.addTarget(self, action: #selector(refresh), for: .valueChanged)
        return $0
    }(UIRefreshControl())
    
    lazy var tableView: UITableView = {
        $0.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        $0.dataSource = self
        $0.delegate = self
        $0.refreshControl = refreshControl
        $0.translatesAutoresizingMaskIntoConstraints = false
        return $0
    }(UITableView(frame: .zero, style: .insetGrouped))
    
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
        navigationItem.titleView = stackView
        navigationController?.setToolbarHidden(false, animated: false)
        navigationItem.leftBarButtonItem = editButtonItem
        navigationItem.rightBarButtonItem = addFeedButton
        
        view.addSubview(tableView)
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        do {
            try fetchedResultsController.performFetch()
        } catch {
            print("Ошибка загрузки данных: \(error)")
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        Task {
            do {
                _ = try await storageService.updateAllFeeds()
            } catch {
                print("Ошибка обновления: \(error)")
            }
            
            await MainActor.run {
                subtitleView.text = storageService.lastFetchAllFeedsInfo()
                stackView.setNeedsLayout()
                stackView.layoutIfNeeded()
            }
        }
    }
    
    override func setEditing(_ editing: Bool, animated: Bool) {
        super.setEditing(editing, animated: animated)
        tableView.setEditing(editing, animated: animated)
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
    
    @objc func refresh() {
        Task {
            do {
                _ = try await storageService.updateAllFeeds(force: true)
            } catch {
                showError("Не удалось обновить данные", title: "Ошибка обновления")
                print("Ошибка обновления: \(error)")
            }
            
            await MainActor.run {
                subtitleView.text = storageService.lastFetchAllFeedsInfo()
                stackView.setNeedsLayout()
                stackView.layoutIfNeeded()
                tableView.reloadData()
                refreshControl.endRefreshing()
            }
        }
    }
    
    func addFeed(urlString: String) async {
        do {
            try await storageService.saveFeed(urlString)
        } catch let error as StorageError {
            await MainActor.run {
                showError(error.localizedDescription)
            }
        } catch {
            await MainActor.run {
                showError("Неизвестная ошибка: \(error.localizedDescription)")
            }
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
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let feed = fetchedResultsController.object(at: indexPath)
        
        guard let feedId = feed.id else {
            showError("Ошибка: не удалось открыть канал")
            tableView.deselectRow(at: indexPath, animated: true)
            return
        }
        
        let vc = FeedListViewController(
            title: feed.title ?? "Без названия",
            storageService: storageService,
            feedId: feedId
        )
        navigationController?.pushViewController(vc, animated: true)
        tableView.deselectRow(at: indexPath, animated: true)
    }
    
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
        guard !refreshControl.isRefreshing else { return }
        tableView.beginUpdates()
    }
    
    func controller(_ controller: NSFetchedResultsController<any NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        guard !refreshControl.isRefreshing else { return }
        
        switch type {
        case .insert:
            guard let newIndexPath else { return }
            tableView.insertRows(at: [newIndexPath], with: .automatic)
        case .delete:
            guard let indexPath else { return }
            tableView.deleteRows(at: [indexPath], with: .automatic)
        case .update:
            guard let indexPath else { return }
            tableView.reloadRows(at: [indexPath], with: .automatic)
        case .move:
            guard let indexPath, let newIndexPath else { return }
            tableView.moveRow(at: indexPath, to: newIndexPath)
        @unknown default:
            break
        }
    }
    
    func controllerDidChangeContent(
        _ controller: NSFetchedResultsController<NSFetchRequestResult>
    ) {
        guard !refreshControl.isRefreshing else { return }
        tableView.endUpdates()
    }
}
