//
//  FeedListViewController.swift
//  RSS viewer
//
//  Created by Андрей Валянский on 18.01.2026.
//

import UIKit
import CoreData
import SafariServices

class FeedListViewController: UIViewController {
    let storageService: StorageService
    let feedId: UUID
    
    init(title: String, storageService: StorageService, feedId: UUID) {
        self.storageService = storageService
        self.feedId = feedId
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private let titleView = UILabel()
    private let subtitleView = UILabel()
    lazy var stackView: UIStackView = {
        titleView.text = title
        titleView.font = .preferredFont(forTextStyle: .headline)
        
        subtitleView.text = storageService.lastFetchFeedInfo(id: feedId)
        subtitleView.font = .preferredFont(forTextStyle: .caption1)
        subtitleView.textColor = .secondaryLabel
        subtitleView.textAlignment = .center
        
        let stackView = UIStackView(arrangedSubviews: [titleView, subtitleView])
        stackView.axis = .vertical
        stackView.alignment = .center
        
        return stackView
    }()
    
    lazy var fetchedResultsController: NSFetchedResultsController<Item> = {
        let request: NSFetchRequest<Item> = Item.fetchRequest()
        request.predicate = NSPredicate(format: "feed.id == %@", feedId as CVarArg)
        request.sortDescriptors = [
            NSSortDescriptor(key: "publishedAt", ascending: false)
        ]

        let frc = NSFetchedResultsController(
            fetchRequest: request,
            managedObjectContext: storageService.context,
            sectionNameKeyPath: "publishedAt",
            cacheName: nil
        )

        frc.delegate = self
        return frc
    }()
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
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.titleView = stackView
        
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
    
    @objc func refresh() {
        Task {
            do {
                try await storageService.saveFeed(feedId)
            } catch let error as StorageError {
                await MainActor.run {
                    showError(error.localizedDescription)
                }
            } catch {
                await MainActor.run {
                    showError("Ошибка обновления: \(error.localizedDescription)")
                }
            }
            
            await MainActor.run {
                subtitleView.text = storageService.lastFetchFeedInfo(id: feedId)
                stackView.setNeedsLayout()
                stackView.layoutIfNeeded()
                refreshControl.endRefreshing()
            }
        }
    }
}

extension FeedListViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        fetchedResultsController.sections?.count ?? 0
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        fetchedResultsController.sections?[section].numberOfObjects ?? 0
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        dateFormatter.locale = Locale.current
        
        if let item = fetchedResultsController.sections?[section].objects?.first as? Item, let date = item.publishedAt {
            return dateFormatter.string(from: date)
        }
        else {
            return "Неизвестно"
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        
        let item = fetchedResultsController.object(at: indexPath)
        
        var config = cell.defaultContentConfiguration()
        config.text = item.title
        config.secondaryText = item.summary

        cell.accessoryType = .disclosureIndicator
        
        cell.contentConfiguration = config
        
        return cell
    }
}

extension FeedListViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let link = fetchedResultsController.object(at: indexPath).link else { showError("Новость не содержит ссылку"); return }
        guard let url = URL(string: link) else { showError("Ссылка не валидна"); return }
        let safariViewController = SFSafariViewController(url: url)
        present(safariViewController, animated: true)
        tableView.deselectRow(at: indexPath, animated: true)
    }
}

extension FeedListViewController: NSFetchedResultsControllerDelegate {
    func controllerWillChangeContent(_ controller: NSFetchedResultsController<any NSFetchRequestResult>) {
        tableView.beginUpdates()
    }
    
    func controller(_ controller: NSFetchedResultsController<any NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
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
        tableView.endUpdates()
    }
}
